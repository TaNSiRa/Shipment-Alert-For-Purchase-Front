part of '../main.dart';

class PoTablePage extends StatefulWidget {
  const PoTablePage({super.key, this.args});

  /// Preset filters when another page links here (e.g. {'due': 'OVERDUE'}).
  final Map<String, dynamic>? args;

  @override
  State<PoTablePage> createState() => _PoTablePageState();
}

class _PoTablePageState extends State<PoTablePage> {
  final search = TextEditingController();
  Timer? _debounce;
  String status = 'ACTIVE';
  String due = '';
  int? step;
  int? supplierId;
  String shipMode = '';
  String sort = 'due';
  int page = 1;
  /// Rows that fit the table's height (0 until the first layout).
  int pageSize = 0;
  Timer? _fitDebounce;
  static const _rowH = 61.0;

  List<Map<String, dynamic>> rows = [];
  int total = 0;
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> steps = [];
  List<Map<String, dynamic>> suppliers = [];
  int _tick = -1;

  @override
  void initState() {
    super.initState();
    final a = widget.args ?? const {};
    due = '${a['due'] ?? ''}';
    step = intFrom(a['step']);
    supplierId = intFrom(a['supplierId']);
    if (a['status'] != null) status = '${a['status']}';
    if (a['q'] != null) search.text = '${a['q']}';
    if (a['sort'] != null) sort = '${a['sort']}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).refreshTick;
    if (tick != _tick) {
      final first = _tick == -1;
      _tick = tick;
      if (first) unawaited(_loadLookups());
      unawaited(load(quiet: !first));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fitDebounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    final api = AppScope.read(context).api;
    try {
      final s = await WorkflowCache.steps(context);
      final lookup = await api.getJson('/masters/lookup');
      if (!mounted) return;
      setState(() {
        steps = s;
        suppliers = (lookup['suppliers'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  Map<String, dynamic> get _query => {
        'status': status,
        'q': search.text.trim(),
        'due': due,
        'step': step,
        'supplierId': supplierId,
        'shipMode': shipMode,
        'sort': sort,
      };

  Future<void> load({bool quiet = false}) async {
    // The first load waits for the table to be measured (see _onFit).
    if (pageSize == 0) return;
    final api = AppScope.read(context).api;
    if (!quiet) setState(() => loading = true);
    try {
      final result = await api.getJson(
          '/pos${qs({..._query, 'page': page, 'pageSize': pageSize})}');
      if (!mounted) return;
      final data = (result['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        rows = data;
        total = intFrom(result['total']) ?? 0;
        loading = false;
        error = null;
        // A delete or filter can leave the page past the end.
        final last = max(1, (total / pageSize).ceil());
        if (page > last) {
          page = last;
          unawaited(load(quiet: true));
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = friendlyError(e.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Could not load shipments';
        });
      }
    }
  }

  void _filterChanged() {
    page = 1;
    unawaited(load());
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _filterChanged);
  }

  Future<void> _import() async {
    final changed = await showPoImportDialog(context);
    if (changed) unawaited(load(quiet: true));
  }

  Future<void> _create() async {
    final id = await showPoCreateDialog(context);
    if (id != null) {
      unawaited(load(quiet: true));
      if (mounted) unawaited(AppScope.read(context).openPo(id));
    }
  }

  /// The table got taller or shorter: page size follows, and the page is
  /// moved so the first row on screen stays on screen.
  void _onFit(int fit) {
    if (fit == pageSize) return;
    _fitDebounce?.cancel();
    _fitDebounce = Timer(Duration(milliseconds: pageSize == 0 ? 0 : 200), () {
      if (!mounted) return;
      final first = pageSize == 0 ? 0 : (page - 1) * pageSize;
      final initial = pageSize == 0;
      setState(() {
        pageSize = fit;
        page = first ~/ fit + 1;
      });
      unawaited(load(quiet: !initial));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final width = MediaQuery.of(context).size.width;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: width < 1200 ? 260 : 340,
                      child: TextField(
                        controller: search,
                        onChanged: _onSearch,
                        decoration: dsInput(
                          hint: 'Search PO, supplier, material, S/I no.…',
                          icon: Icons.search,
                          suffix: search.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close, size: 17),
                                  onPressed: () {
                                    search.clear();
                                    _filterChanged();
                                  }),
                        ),
                      ),
                    ),
                    _statusSegment(),
                  ]),
            ),
            if (scope.canEdit) ...[
              const SizedBox(width: 10),
              DsOutlineButton(
                  label: 'New PO',
                  icon: Icons.add,
                  height: 40,
                  onPressed: _create),
              const SizedBox(width: 8),
              DsPrimaryButton(
                  label: 'Import Excel',
                  icon: Icons.upload_file,
                  height: 40,
                  onPressed: _import),
            ],
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _dueChip('', 'All', null),
                    _dueChip('OVERDUE', 'Overdue', DsColors.redFg),
                    _dueChip('TODAY', 'Due today', DsColors.amberFg),
                    _dueChip('SOON', 'Due soon', DsColors.amberFg),
                    const SizedBox(width: 6),
                    _dropdown<int>(
                      width: 210,
                      hint: 'All steps',
                      value: step,
                      items: [
                        for (final s in steps
                            .where((s) => (intFrom(s['stepNo']) ?? 0) >= 2))
                          SearchableDropdownItem(
                              value: intFrom(s['stepNo']),
                              label: '${s['stepNo']}. ${s['shortName']}',
                              subtitle: '${s['name']}'),
                      ],
                      onChanged: (v) {
                        step = v;
                        _filterChanged();
                      },
                    ),
                    _dropdown<int>(
                      width: 210,
                      hint: 'All suppliers',
                      value: supplierId,
                      items: [
                        for (final s in suppliers)
                          SearchableDropdownItem(
                              value: intFrom(s['id']),
                              label: '${s['shortName'] ?? s['name']}',
                              subtitle:
                                  '${s['supplierCode'] ?? ''} · ${s['name']}'),
                      ],
                      onChanged: (v) {
                        supplierId = v;
                        _filterChanged();
                      },
                    ),
                    _dropdown<String>(
                      width: 140,
                      hint: 'All modes',
                      value: shipMode.isEmpty ? null : shipMode,
                      items: [
                        for (final m in shipModeItems)
                          if (m.value != null) m,
                      ],
                      onChanged: (v) {
                        shipMode = v ?? '';
                        _filterChanged();
                      },
                    ),
                    _dropdown<String>(
                      width: 190,
                      hint: 'Sort',
                      value: sort,
                      clearable: false,
                      items: const [
                        SearchableDropdownItem(
                            value: 'due', label: 'Sort: next due date'),
                        SearchableDropdownItem(value: 'eta', label: 'Sort: ETA'),
                        SearchableDropdownItem(
                            value: 'docDate', label: 'Sort: newest PO'),
                        SearchableDropdownItem(
                            value: 'po', label: 'Sort: PO number'),
                        SearchableDropdownItem(
                            value: 'supplier', label: 'Sort: supplier'),
                        SearchableDropdownItem(value: 'step', label: 'Sort: step'),
                        SearchableDropdownItem(
                            value: 'updated', label: 'Sort: last updated'),
                      ],
                      onChanged: (v) {
                        sort = v ?? 'due';
                        _filterChanged();
                      },
                    ),
                  ]),
            ),
            DsIconButton(
              icon: Icons.download_outlined,
              tooltip: 'Export this list to Excel',
              onTap: () => unawaited(downloadFromApi(
                  context,
                  '/pos/export${qs(_query)}',
                  'purchase-shipments-${todayIso()}.xlsx')),
            ),
          ]),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: DsCard(
            padding: EdgeInsets.zero,
            clip: true,
            color: DsColors.sheet,
            // The pager sits outside the sideways scroll so it stays in view
            // on narrow screens.
            child: Column(children: [
              Expanded(
                child: MinWidthScroll(
                    minWidth: 1120,
                    child: Column(children: [
                      _header(scope),
                      const Divider(height: 1),
                      Expanded(
                          child: DsFitRows(
                              rowHeight: _rowH,
                              onFit: _onFit,
                              builder: (_, rowH) => _body(scope, rowH))),
                    ])),
              ),
              const Divider(height: 1),
              // The pager brings its own vertical padding; the floor is the
              // pager's height, so the footer does not grow once the first
              // page arrives (that would change the page size and refetch).
              Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Text(loading ? 'Loading…' : plural(total, 'PO'),
                      style: DsType.meta),
                  const Spacer(),
                  PaginationBar(
                    topBorder: false,
                    page: page - 1,
                    totalItems: total,
                    pageSize: max(1, pageSize),
                    onChanged: (p) {
                      page = p + 1;
                      unawaited(load());
                    },
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _statusSegment() {
    const options = [
      ('ACTIVE', 'Open'),
      ('COMPLETED', 'Completed'),
      ('CANCELLED', 'Cancelled')
    ];
    final index = options.indexWhere((o) => o.$1 == status);
    return DsSegmented(
      selected: index < 0 ? 0 : index,
      length: options.length,
      itemBuilder: (context, i, t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(options[i].$2,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color.lerp(DsColors.muted, DsColors.navyDeep, t))),
      ),
      onSelect: (i) {
        status = options[i].$1;
        if (status != 'ACTIVE') due = '';
        _filterChanged();
      },
    );
  }

  Widget _dueChip(String value, String label, Color? color) {
    final active = due == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      showCheckmark: false,
      avatar: color == null ? null : DsDot(color, size: 8),
      labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? DsColors.navyDeep : DsColors.text2),
      selectedColor: DsColors.navySoft,
      side:
          BorderSide(color: active ? DsColors.navyBorder : DsColors.cardBorder),
      onSelected: status != 'ACTIVE' && value.isNotEmpty
          ? null
          : (_) {
              due = value;
              _filterChanged();
            },
    );
  }

  Widget _dropdown<T>({
    required double width,
    required String hint,
    required T? value,
    required List<SearchableDropdownItem<T>> items,
    required ValueChanged<T?> onChanged,
    bool clearable = true,
  }) {
    return SizedBox(
      width: width,
      height: 38,
      child: SearchableDropdownField<T>(
        value: items.any((i) => i.value == value) ? value : null,
        dense: true,
        dialogTitle: hint,
        decoration: dsInput(hint: hint).copyWith(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
        items: [
          if (clearable) SearchableDropdownItem<T>(value: null, label: hint),
          ...items,
        ],
        onChanged: (v) {
          // Choosing the selected entry again is not a change.
          if (v != value) onChanged(v);
        },
      ),
    );
  }

  // Column widths. Supplier and the step column flex; the rest are fixed.
  static const _wPo = 128.0;
  static const _wDate = 96.0;
  static const _wLines = 54.0;
  static const _wMode = 78.0;
  static const _wDue = 150.0;
  static const _wEta = 100.0;
  static const _wAct = 96.0;

  Widget _header(AppScope scope) {
    Widget h(String t, double? w, {TextAlign align = TextAlign.left}) {
      final text =
          Text(t.toUpperCase(), textAlign: align, style: DsType.eyebrow);
      return w == null
          ? Expanded(child: text)
          : SizedBox(width: w, child: text);
    }

    return Container(
      color: DsColors.subtle,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(children: [
        const SizedBox(width: 8),
        h('PO No.', _wPo),
        h('Supplier', null),
        h('PO date', _wDate),
        h('Lines', _wLines),
        h('Mode', _wMode),
        const SizedBox(width: 12),
        SizedBox(width: 190, child: Text('PROGRESS', style: DsType.eyebrow)),
        h('Next due', _wDue),
        h('ETA', _wEta),
        h('', _wAct),
      ]),
    );
  }

  Widget _body(AppScope scope, double rowH) {
    if (loading && rows.isEmpty) return _skeleton(scope, rowH);
    if (error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: ErrorPanel(message: error!, onRetry: load)));
    }
    if (rows.isEmpty) {
      final filtered = search.text.isNotEmpty ||
          due.isNotEmpty ||
          step != null ||
          supplierId != null ||
          shipMode.isNotEmpty;
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DsEmptyState(
            icon: filtered
                ? Icons.filter_alt_off_outlined
                : Icons.inventory_2_outlined,
            message: filtered
                ? 'No PO matches these filters'
                : status == 'ACTIVE'
                    ? 'No open shipments yet'
                    : 'Nothing here',
          ),
          if (!filtered && status == 'ACTIVE' && scope.canEdit)
            DsPrimaryButton(
                label: 'Import the SAP Excel',
                icon: Icons.upload_file,
                height: 40,
                onPressed: _import),
        ]),
      );
    }
    // One page fills the table: fixed-height rows, no scrolling.
    return Column(children: [
      for (final r in rows)
        Container(
          height: rowH,
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
          child: _row(scope, r),
        ),
    ]);
  }

  /// The rows of [_row], column for column, while the first page loads.
  Widget _skeleton(AppScope scope, double rowH) {
    return DsSkeletonRows(
      rowHeight: rowH,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      columns: [
        DsSkelCol((_) => const SizedBox(), width: 8),
        DsSkelCol((i) => DsSkel.lines(DsSkel.vary(i, 78, .2), DsSkel.vary(i + 3, 56)),
            width: _wPo),
        DsSkelCol((i) => DsSkel.lines(DsSkel.vary(i + 1, 150), DsSkel.vary(i + 5, 100))),
        DsSkelCol((_) => DsSkel.line(72), width: _wDate),
        DsSkelCol((_) => DsSkel.line(16), width: _wLines),
        DsSkelCol(
            (_) => Row(mainAxisSize: MainAxisSize.min, children: [
                  DsSkel.circle(14),
                  const SizedBox(width: 5),
                  DsSkel.line(30),
                ]),
            width: _wMode),
        DsSkelCol((_) => const SizedBox(), width: 12),
        DsSkelCol(
            (i) => Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DsSkel.line(DsSkel.vary(i, 92), height: 13),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: DsSkel.fill(5, radius: 3)),
                          const SizedBox(width: 6),
                          DsSkel.line(22, height: 9),
                        ]),
                      ]),
                ),
            width: 190),
        DsSkelCol(
            (i) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DsSkel.line(76, height: 11),
                      const SizedBox(height: 5),
                      DsSkel.chip(DsSkel.vary(i + 2, 70), height: 16),
                    ]),
            width: _wDue),
        DsSkelCol((_) => DsSkel.line(74, height: 11), width: _wEta),
        DsSkelCol(
            (_) => Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  if (scope.canEdit) DsSkel.circle(34),
                  const SizedBox(width: 14),
                  DsSkel.box(4, 16, radius: 2), // the ⋮ menu
                  const SizedBox(width: 14),
                ]),
            width: _wAct,
            align: Alignment.centerRight),
      ],
    );
  }

  Widget _row(AppScope scope, Map<String, dynamic> po) {
    final id = intFrom(po['id'])!;
    final active = po['status'] == 'ACTIVE';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        hoverColor: const Color(0x30ffffff),
        onTap: () async {
          await scope.openPo(id);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            const SizedBox(width: 8),
            SizedBox(
              width: _wPo,
              child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${po['poNo']}',
                        style: mono(
                            size: 12.5,
                            weight: FontWeight.w700,
                            color: DsColors.heading)),
                    if ('${po['shipmentRef'] ?? ''}'.isNotEmpty)
                      Text('${po['shipmentRef']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.metaSm),
                  ]),
            ),
            Expanded(
              child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${po['supplierShort'] ?? po['supplierName'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsType.rowTitle),
                    Text(
                        '${po['supplierCode'] ?? ''}${(po['remark'] ?? '').toString().isNotEmpty ? ' · ${po['remark']}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsType.metaSm),
                  ]),
            ),
            SizedBox(
                width: _wDate,
                child: Text(fmtDate(po['documentDate']), style: DsType.meta)),
            SizedBox(
                width: _wLines,
                child: Text('${po['itemCount']}', style: mono(size: 12))),
            SizedBox(
                width: _wMode,
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: ShipModeTag(mode: po['shipMode']))),
            const SizedBox(width: 12),
            SizedBox(
                width: 190,
                child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: StepProgress(po: po, width: 176))),
            SizedBox(
              width: _wDue,
              child: active
                  ? Column(
                      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(fmtDate(po['nextDueDate']),
                              style: DsType.rowTitle),
                          const SizedBox(height: 3),
                          DueChip(po: po, dense: true),
                        ])
                  : DueChip(po: po, dense: true),
            ),
            SizedBox(
              width: _wEta,
              child: Text(fmtDate(po['etaDate']),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: DsColors.navyDeep)),
            ),
            SizedBox(
              width: _wAct,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (active && scope.canEdit)
                  Tooltip(
                    message: 'Mark "${po['currentStepShort']}" done',
                    child: IconButton.filledTonal(
                      style: IconButton.styleFrom(
                          backgroundColor: DsColors.greenBg,
                          foregroundColor: DsColors.greenFg,
                          minimumSize: const Size(34, 34)),
                      icon: const Icon(Icons.check, size: 18),
                      onPressed: () async {
                        if (await showAdvanceDialog(context, [po])) {
                          unawaited(load(quiet: true));
                        }
                      },
                    ),
                  ),
                _rowMenu(scope, po),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _rowMenu(AppScope scope, Map<String, dynamic> po) {
    final active = po['status'] == 'ACTIVE';
    final cancelled = po['status'] == 'CANCELLED';
    final step = intFrom(po['currentStep']) ?? 2;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert, size: 19, color: DsColors.icon),
      onSelected: (v) async {
        bool changed = false;
        switch (v) {
          case 'open':
            await scope.openPo(intFrom(po['id'])!);
          case 'edit':
            changed = await editPoDialog(context, po);
          case 'undo':
            await WorkflowCache.steps(context);
            if (mounted) changed = await undoLastStep(context, po);
          case 'cancel':
            changed = await cancelPoDialog(context, po);
          case 'reopen':
            changed = await reopenPo(context, po);
          case 'delete':
            changed = await deletePo(context, po);
        }
        if (changed) unawaited(load(quiet: true));
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: 'open',
            child: ListTile(
                dense: true,
                leading: Icon(Icons.open_in_new, size: 18),
                title: Text('Open details'))),
        if (scope.canEdit && !cancelled)
          const PopupMenuItem(
              value: 'edit',
              child: ListTile(
                  dense: true,
                  leading: Icon(Icons.edit_outlined, size: 18),
                  title: Text('Edit'))),
        if (scope.canEdit && !cancelled && step > 2)
          const PopupMenuItem(
              value: 'undo',
              child: ListTile(
                  dense: true,
                  leading: Icon(Icons.undo, size: 18),
                  title: Text('Undo last step'))),
        if (scope.canEdit && active)
          const PopupMenuItem(
              value: 'cancel',
              child: ListTile(
                  dense: true,
                  leading: Icon(Icons.block, size: 18),
                  title: Text('Cancel PO'))),
        if (scope.isSectionAdmin && cancelled)
          const PopupMenuItem(
              value: 'reopen',
              child: ListTile(
                  dense: true,
                  leading: Icon(Icons.restore, size: 18),
                  title: Text('Reopen'))),
        if (scope.isSectionAdmin)
          const PopupMenuItem(
              value: 'delete',
              child: ListTile(
                  dense: true,
                  leading: Icon(Icons.delete_outline,
                      size: 18, color: DsColors.redFg),
                  title: Text('Delete permanently'))),
      ],
    );
  }
}
