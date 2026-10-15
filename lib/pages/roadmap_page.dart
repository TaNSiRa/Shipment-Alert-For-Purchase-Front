part of '../main.dart';

/// "Shipment progress road map": every open PO as one row, the workflow steps as
/// columns, each cell showing done / current / still to come.
class RoadmapPage extends StatefulWidget {
  const RoadmapPage({super.key});
  @override
  State<RoadmapPage> createState() => _RoadmapPageState();
}

class _RoadmapPageState extends State<RoadmapPage> {
  final search = TextEditingController();
  Timer? _debounce;
  String status = 'ACTIVE';
  List<Map<String, dynamic>> steps = [];
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? error;
  int _tick = -1;
  // One screen = one page (RAP): as many rows as fit, paged client-side.
  int page = 0;
  int pageSize = 0;
  static const _rowH = 62.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).refreshTick;
    if (tick != _tick) {
      _tick = tick;
      unawaited(load());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await AppScope.read(context).api.getJson(
          '/pos/roadmap${qs({'status': status, 'q': search.text.trim()})}');
      if (!mounted) return;
      setState(() {
        steps = (r['steps'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        rows = (r['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (pageSize > 0) page = page.clamp(0, max(0, (rows.length - 1) ~/ pageSize));
        loading = false;
        error = null;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = friendlyError(e.message);
        });
      }
    }
  }

  // The PO column is just wide enough for the number and a short supplier
  // name; the step columns share the rest, so the map fits the screen
  // without scrolling sideways (horizontal scroll only below _wCellMin).
  static const _wPo = 150.0;
  static const _wCellMin = 72.0;
  static const _wEta = 96.0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final minWidth = _wPo + _wCellMin * steps.length + _wEta + 24;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
        child: Row(children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: search,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  page = 0;
                  unawaited(load());
                });
              },
              decoration: dsInput(
                  hint: 'Search PO, supplier, S/I no.…', icon: Icons.search),
            ),
          ),
          const SizedBox(width: 10),
          DsSegmented(
            selected: status == 'ACTIVE' ? 0 : 1,
            length: 2,
            itemBuilder: (context, i, t) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(['Open', 'Completed (90 days)'][i],
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(DsColors.muted, DsColors.navyDeep, t))),
            ),
            onSelect: (i) {
              status = i == 0 ? 'ACTIVE' : 'COMPLETED';
              page = 0;
              setState(() => loading = true);
              unawaited(load());
            },
          ),
          const Spacer(),
          const _Legend(),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
          child: DsCard(
            padding: EdgeInsets.zero,
            clip: true,
            color: DsColors.sheet,
            child: loading
                ? const DsSkeletonList(rows: 8)
                : error != null
                    ? Center(child: ErrorPanel(message: error!, onRetry: load))
                    : rows.isEmpty
                        ? const DsEmptyState(
                            icon: Icons.route_outlined,
                            message: 'No shipments to show')
                        : LayoutBuilder(builder: (context, box) {
                            final w = max(box.maxWidth, minWidth);
                            final cell = (w - _wPo - _wEta - 24) / max(1, steps.length);
                            final size = max(1, pageSize);
                            final pages = max(1, (rows.length / size).ceil());
                            final p = page.clamp(0, pages - 1);
                            final visible = rows.skip(p * size).take(size).toList();
                            return Column(children: [
                              Expanded(
                                child: Scrollbar(
                                  thumbVisibility: w > box.maxWidth,
                                  notificationPredicate: (n) =>
                                      n.metrics.axis == Axis.horizontal,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: w,
                                      child: Column(children: [
                                        _header(cell),
                                        const Divider(height: 1),
                                        Expanded(
                                          child: DsFitRows(
                                            rowHeight: _rowH,
                                            onFit: (fit) {
                                              if (fit == pageSize) return;
                                              final first = page * max(1, pageSize);
                                              setState(() {
                                                pageSize = fit;
                                                page = first ~/ fit;
                                              });
                                            },
                                            child: Column(children: [
                                              for (final r in visible)
                                                Container(
                                                  height: _rowH,
                                                  decoration: const BoxDecoration(
                                                      border: Border(
                                                          bottom: BorderSide(
                                                              color: DsColors.lineSoft))),
                                                  child: _row(scope, r, cell),
                                                ),
                                            ]),
                                          ),
                                        ),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                              const Divider(height: 1),
                              Row(children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 14),
                                  child: Text(plural(rows.length, 'PO'), style: DsType.meta),
                                ),
                                const Spacer(),
                                PaginationBar(
                                  topBorder: false,
                                  page: p,
                                  totalItems: rows.length,
                                  pageSize: size,
                                  onChanged: (n) => setState(() => page = n),
                                ),
                              ]),
                            ]);
                          }),
          ),
        ),
      ),
    ]);
  }

  Widget _header(double cell) {
    return Container(
      color: DsColors.subtle,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        const SizedBox(
            width: _wPo, child: Text('PURCHASE ORDER', style: DsType.eyebrow)),
        for (final s in steps)
          SizedBox(
            width: cell,
            child: Tooltip(
              message: '${s['stepNo']}. ${s['name']}',
              child: Column(children: [
                Icon(stepIcon(s['icon']), size: 16, color: DsColors.icon),
                const SizedBox(height: 3),
                Text('${s['stepNo']}. ${s['shortName']}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsType.metaSm),
              ]),
            ),
          ),
        const Expanded(
            child: Text('ETA FACTORY',
                textAlign: TextAlign.right, style: DsType.eyebrow)),
      ]),
    );
  }

  Widget _row(AppScope scope, Map<String, dynamic> po, double cell) {
    final stepRows = (po['steps'] as List).cast<Map>();
    final current = intFrom(po['currentStep']) ?? steps.length + 1;
    final today = todayIso();
    return InkWell(
      onTap: () => unawaited(scope.openPo(intFrom(po['id'])!)),
      hoverColor: const Color(0x30ffffff),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        child: Row(children: [
          SizedBox(
            width: _wPo,
            child: Row(children: [
              DueDot(state: '${po['dueState']}'),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${po['poNo']}',
                          style: mono(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: DsColors.heading)),
                      Text('${po['supplierShort'] ?? po['supplierName'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.metaSm),
                    ]),
              ),
            ]),
          ),
          for (var n = 1; n <= steps.length; n++)
            SizedBox(
              width: cell,
              child: _cell(
                  n,
                  stepRows.firstWhere((s) => intFrom(s['stepNo']) == n,
                      orElse: () => {}),
                  current,
                  po,
                  today),
            ),
          Expanded(
            child:
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtDate(po['etaDate']),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: DsColors.navyDeep)),
              Text('${po['leadTimeDays'] ?? '-'} d lead', style: DsType.metaSm),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _cell(
      int n, Map s, int current, Map<String, dynamic> po, String today) {
    final actual = s['actual'] as String?;
    final due = s['due'] as String?;
    final isCurrent = n == current && po['status'] == 'ACTIVE';
    late final Color color;
    late final Widget icon;
    late final String label;
    if (actual != null) {
      final late = due != null && actual.compareTo(due) > 0;
      color = late ? DsColors.amberFg : DsColors.greenFg;
      icon = const Icon(Icons.check, size: 13, color: Colors.white);
      label = fmtDateShort(actual);
    } else if (isCurrent) {
      final overdue = due != null && due.compareTo(today) < 0;
      color = overdue ? DsColors.redFg : DsColors.navy;
      icon = Icon(overdue ? Icons.priority_high : Icons.more_horiz,
          size: 13, color: Colors.white);
      label = fmtDateShort(due);
    } else {
      color = DsColors.faint2;
      icon = const SizedBox();
      label = fmtDateShort(due);
    }
    final filled = actual != null || isCurrent;
    return Tooltip(
      message: actual != null
          ? 'Done ${fmtDate(actual)} (due ${fmtDate(due)})'
          : isCurrent
              ? 'Waiting · due ${fmtDate(due)}'
              : 'Planned ${fmtDate(due)}',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
              child: Container(
                  height: 2,
                  color: n == 1
                      ? Colors.transparent
                      : (actual != null || isCurrent
                          ? color.withValues(alpha: .5)
                          : DsColors.line))),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: filled ? color : Colors.transparent,
              shape: BoxShape.circle,
              border: filled
                  ? null
                  : Border.all(color: DsColors.inputBorder, width: 1.6),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: .4), blurRadius: 8)
                    ]
                  : null,
            ),
            child: Center(child: icon),
          ),
          Expanded(
              child: Container(
                  height: 2,
                  color: n == steps.length
                      ? Colors.transparent
                      : (actual != null
                          ? color.withValues(alpha: .5)
                          : DsColors.line))),
        ]),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: filled ? color : DsColors.faint2)),
      ]),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t, {bool hollow = false}) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: hollow ? Colors.transparent : c,
              shape: BoxShape.circle,
              border: hollow
                  ? Border.all(color: DsColors.inputBorder, width: 1.5)
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(t, style: DsType.metaSm),
        ]);
    return Wrap(spacing: 12, children: [
      item(DsColors.greenFg, 'Done on time'),
      item(DsColors.amberFg, 'Done late'),
      item(DsColors.navy, 'Waiting'),
      item(DsColors.redFg, 'Overdue'),
      item(DsColors.faint2, 'Planned', hollow: true),
    ]);
  }
}
