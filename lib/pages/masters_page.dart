part of '../main.dart';

/// Shared "Import master Excel" flow for both master pages.
Future<bool> showMasterImportDialog(BuildContext context) async {
  final api = AppScope.read(context).api;
  final file = await pickExcelFile();
  if (file == null || !context.mounted) return false;
  final preview = await guard(
      context,
      () => api.postJson('/masters/import/preview',
          {'fileName': file.name, 'data': file.base64}));
  if (preview == null || !context.mounted) return false;
  final notes = (preview['notes'] as List? ?? const []).cast<dynamic>();
  final ok = await showGlassDialog<bool>(
    context: context,
    builder: (ctx) => AppDialog(
      title: 'Import master data',
      subtitle: file.name,
      icon: Icons.table_view_outlined,
      width: 560,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
            'Sheets found: ${(preview['sheets'] as List).map((s) => '${s['name']} (${s['kind'] == 'MATERIAL' ? 'materials' : 'suppliers'})').join(', ')}',
            style: DsType.meta),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final e in [
            ('New suppliers', preview['suppliersNew'], DsColors.greenFg),
            ('Suppliers updated', preview['suppliersUpdated'], DsColors.blueFg),
            ('New materials', preview['materialsNew'], DsColors.greenFg),
            ('Materials updated', preview['materialsUpdated'], DsColors.blueFg),
            ('Unchanged', preview['materialsUnchanged'], DsColors.muted),
            ('Skipped rows', preview['skipped'], DsColors.amberFg),
          ])
            Container(
              width: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: e.$3.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e.$2 ?? 0}', style: DsType.stat(20, color: e.$3)),
                    Text(e.$1, style: DsType.metaSm),
                  ]),
            ),
        ]),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          const DsSectionLabel('Notes'),
          const SizedBox(height: 6),
          for (final n in notes.take(10)) Text('• $n', style: DsType.metaSm),
        ],
        const SizedBox(height: 12),
        const InfoStrip(
          text:
              'Import only adds and updates — nothing is deleted. Duplicate supplier + material rows are merged, '
              'keeping the longer lead time. Open POs keep their plan; use Workflow › Recalculate to re-plan them.',
        ),
      ]),
      actions: [
        DsOutlineButton(
            label: 'Cancel',
            height: 40,
            onPressed: () => Navigator.pop(ctx, false)),
        DsPrimaryButton(
            label: 'Import',
            icon: Icons.cloud_upload_outlined,
            height: 40,
            onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final result = await guard(
      context,
      () => api.postJson('/masters/import/commit',
          {'fileName': file.name, 'data': file.base64}));
  if (result == null || !context.mounted) return false;
  AppToast.success(context,
      'Master imported: ${result['suppliersNew']} new / ${result['suppliersUpdated']} updated suppliers, ${result['materialsNew']} new / ${result['materialsUpdated']} updated materials');
  return true;
}

class _MasterToolbar extends StatelessWidget {
  const _MasterToolbar(
      {required this.search,
      required this.onSearch,
      required this.children,
      required this.onAdd,
      required this.onImported});
  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final List<Widget> children;
  final VoidCallback onAdd;
  final VoidCallback onImported;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
      child: Row(children: [
        Expanded(
          child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                      controller: search,
                      onChanged: onSearch,
                      decoration: dsInput(hint: 'Search…', icon: Icons.search)),
                ),
                ...children,
              ]),
        ),
        DsIconButton(
          icon: Icons.download_outlined,
          tooltip: 'Export the master to Excel',
          onTap: () => unawaited(downloadFromApi(context, '/masters/export',
              'material-master-${scope.sectionCode}.xlsx')),
        ),
        if (scope.isSectionAdmin) ...[
          const SizedBox(width: 8),
          DsOutlineButton(
            label: 'Import Excel',
            icon: Icons.upload_file,
            height: 40,
            onPressed: () async {
              if (await showMasterImportDialog(context)) onImported();
            },
          ),
          const SizedBox(width: 8),
          DsPrimaryButton(
              label: 'Add', icon: Icons.add, height: 40, onPressed: onAdd),
        ],
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Supplier Master
// ---------------------------------------------------------------------------

class SupplierMasterPage extends StatefulWidget {
  const SupplierMasterPage({super.key});
  @override
  State<SupplierMasterPage> createState() => _SupplierMasterPageState();
}

class _SupplierMasterPageState extends State<SupplierMasterPage> {
  final search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? error;
  int _tick = -1;

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
      final r = await AppScope.read(context)
          .api
          .getJson('/masters/suppliers${qs({'q': search.text.trim()})}');
      if (mounted) {
        setState(() {
          rows = (r['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          loading = false;
          error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = friendlyError(e.message);
        });
      }
    }
  }

  Future<void> edit([Map<String, dynamic>? s]) async {
    final api = AppScope.read(context).api;
    final code = TextEditingController(text: '${s?['supplierCode'] ?? ''}');
    final name = TextEditingController(text: '${s?['name'] ?? ''}');
    final short = TextEditingController(text: '${s?['shortName'] ?? ''}');
    final country = TextEditingController(text: '${s?['country'] ?? ''}');
    final lead = TextEditingController(
        text: s?['defaultLeadTimeDays'] == null
            ? ''
            : '${s!['defaultLeadTimeDays']}');
    final email = TextEditingController(text: '${s?['contactEmail'] ?? ''}');
    final remark = TextEditingController(text: '${s?['remark'] ?? ''}');
    bool active = s?['isActive'] != false;
    String? error;
    final saved = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> save() async {
          final lt =
              lead.text.trim().isEmpty ? null : int.tryParse(lead.text.trim());
          if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
            return setState(() => error = 'Supplier ID and name are required');
          }
          if (lead.text.trim().isNotEmpty && (lt == null || lt < 1 || lt > 365)) {
            return setState(() => error = 'Lead time must be 1–365 days');
          }
          final body = {
            'supplierCode': code.text.trim(),
            'name': name.text.trim(),
            'shortName': short.text.trim(),
            'country': country.text.trim(),
            'defaultLeadTimeDays': lt,
            'contactEmail': email.text.trim(),
            'remark': remark.text.trim(),
            'isActive': active,
          };
          try {
            if (s == null) {
              await api.postJson('/masters/suppliers', body);
            } else {
              await api.patchJson('/masters/suppliers/${s['id']}', body);
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on ApiException catch (e) {
            setState(() => error = friendlyError(e.message));
          }
        }

        return AppDialog(
          title: s == null ? 'Add supplier' : 'Edit supplier',
          icon: Icons.storefront_outlined,
          width: 600,
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(
                  width: 160,
                  child: DsLabeledField(
                      label: 'Supplier ID *',
                      child: TextField(
                          controller: code,
                          decoration: dsInput(hint: '12200003')))),
              const SizedBox(width: 12),
              Expanded(
                  child: DsLabeledField(
                      label: 'Name *',
                      child:
                          TextField(controller: name, decoration: dsInput()))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: DsLabeledField(
                      label: 'Short name (search term)',
                      child: TextField(
                          controller: short,
                          decoration: dsInput(hint: 'NIHON H/O')))),
              const SizedBox(width: 12),
              Expanded(
                  child: DsLabeledField(
                      label: 'Country',
                      child: TextField(
                          controller: country,
                          decoration: dsInput(hint: 'Japan')))),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: DsLabeledField(
                  label: 'Default lead time',
                  child: TextField(
                    controller: lead,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: dsInput(hint: 'days'),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DsLabeledField(
                label: 'Contact email',
                child: TextField(
                    controller: email,
                    decoration: dsInput(icon: Icons.mail_outline))),
            const SizedBox(height: 12),
            DsLabeledField(
                label: 'Remark',
                child: TextField(
                    controller: remark, maxLines: 2, decoration: dsInput())),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: active,
              title: const Text('Active', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                  'Inactive suppliers are hidden from the New PO form',
                  style: DsType.metaSm),
              onChanged: (v) => setState(() => active = v),
            ),
            const InfoStrip(
                text:
                    'The default lead time is used for PO lines whose material is not in the Material Master.'),
            if (error != null) ...[
              const SizedBox(height: 10),
              InfoStrip(
                  text: error!,
                  icon: Icons.error_outline,
                  color: DsColors.redFg)
            ],
          ]),
          actions: [
            DsOutlineButton(
                label: 'Cancel',
                height: 40,
                onPressed: () => Navigator.pop(ctx, false)),
            DsPrimaryButton(
                label: 'Save',
                icon: Icons.save_outlined,
                height: 40,
                onPressed: save),
          ],
        );
      }),
    );
    if (saved == true) {
      if (mounted) AppToast.success(context, 'Supplier saved');
      unawaited(load());
    }
  }

  Future<void> delete(Map<String, dynamic> s) async {
    final ok = await confirmAction(context,
        title: 'Delete supplier ${s['supplierCode']}?',
        message: '${s['name']} will be removed from the master.',
        confirmLabel: 'Delete',
        danger: true);
    if (!ok || !mounted) return;
    final api = AppScope.read(context).api;
    if (await guard(
            context, () => api.deleteJson('/masters/suppliers/${s['id']}'),
            success: 'Supplier deleted') !=
        null) {
      unawaited(load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Column(children: [
      _MasterToolbar(
        search: search,
        onSearch: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), load);
        },
        onAdd: () => edit(),
        onImported: load,
        children: [Text(plural(rows.length, 'supplier'), style: DsType.meta)],
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
                            icon: Icons.storefront_outlined,
                            message:
                                'No suppliers yet — add one or import the master Excel')
                        : MinWidthScroll(
                            minWidth: 1100,
                            child: Column(children: [
                              _row(null, scope, header: true),
                              const Divider(height: 1),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: rows.length,
                                  separatorBuilder: (_, __) => const Divider(
                                      height: 1, color: DsColors.lineSoft),
                                  itemBuilder: (_, i) => _row(rows[i], scope),
                                ),
                              ),
                            ])),
          ),
        ),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic>? s, AppScope scope, {bool header = false}) {
    Widget c(String t, double? w, {TextStyle? style}) {
      final text = Text(header ? t.toUpperCase() : t,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: header
              ? DsType.eyebrow
              : style ?? const TextStyle(fontSize: 12.5, color: DsColors.text));
      return w == null
          ? Expanded(child: text)
          : SizedBox(width: w, child: text);
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        SizedBox(
            width: 110,
            child: header
                ? c('Supplier ID', 110)
                : Text('${s!['supplierCode']}',
                    style: mono(size: 12.5, weight: FontWeight.w700))),
        c(header ? 'Name' : '${s!['name']}', null, style: DsType.rowTitle),
        c(header ? 'Short name' : '${s!['shortName'] ?? '-'}', 140),
        c(header ? 'Country' : '${s!['country'] ?? '-'}', 100),
        c(
            header
                ? 'Default LT'
                : (s!['defaultLeadTimeDays'] == null
                    ? '-'
                    : '${s['defaultLeadTimeDays']} d'),
            100),
        c(header ? 'Materials' : '${s!['materialCount']}', 90),
        c(header ? 'Open POs' : '${s!['activePoCount']}', 90),
        SizedBox(
          width: 90,
          child: header
              ? const Text('STATUS', style: DsType.eyebrow)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: s!['isActive'] == true
                      ? const DsTag('Active',
                          color: DsColors.greenFg, bg: DsColors.greenBg)
                      : const DsTag('Inactive'),
                ),
        ),
        SizedBox(
          width: 120,
          child: header
              ? const SizedBox()
              : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  DsIconButton(
                    icon: Icons.science_outlined,
                    tooltip: 'Show its materials',
                    onTap: () => scope.navigate(AppPage.materials,
                        args: {'supplierId': s!['id']}),
                  ),
                  if (scope.isSectionAdmin) ...[
                    DsIconButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit',
                        onTap: () => edit(s)),
                    DsIconButton(
                        icon: Icons.delete_outline,
                        tooltip: 'Delete',
                        color: DsColors.redFg,
                        onTap: () => delete(s!)),
                  ],
                ]),
        ),
      ]),
    );
    if (header) return Container(color: DsColors.subtle, child: content);
    return InkWell(
        onTap: scope.isSectionAdmin ? () => edit(s) : null, child: content);
  }
}

// ---------------------------------------------------------------------------
// Material Master
// ---------------------------------------------------------------------------

class MaterialMasterPage extends StatefulWidget {
  const MaterialMasterPage({super.key, this.args});
  final Map<String, dynamic>? args;
  @override
  State<MaterialMasterPage> createState() => _MaterialMasterPageState();
}

class _MaterialMasterPageState extends State<MaterialMasterPage> {
  final search = TextEditingController();
  Timer? _debounce;
  int? supplierId;
  String? type;
  bool missingCode = false;
  int page = 1;
  static const pageSize = 50;
  List<Map<String, dynamic>> rows = [];
  int total = 0;
  List<Map<String, dynamic>> suppliers = [];
  List<String> types = [];
  bool loading = true;
  String? error;
  int _tick = -1;

  @override
  void initState() {
    super.initState();
    supplierId = intFrom(widget.args?['supplierId']);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).refreshTick;
    if (tick != _tick) {
      final first = _tick == -1;
      _tick = tick;
      if (first) unawaited(_lookups());
      unawaited(load());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _lookups() async {
    final api = AppScope.read(context).api;
    try {
      final s = await api.getJson('/masters/suppliers');
      final t = await api.getJson('/masters/material-types');
      if (!mounted) return;
      setState(() {
        suppliers = (s['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        types =
            (t['data'] as List).map((e) => '${(e as Map)['type']}').toList();
      });
    } catch (_) {}
  }

  Future<void> load() async {
    try {
      final r =
          await AppScope.read(context).api.getJson('/masters/materials${qs({
                    'q': search.text.trim(),
                    'supplierId': supplierId,
                    'type': type,
                    'missingCode': missingCode ? 'true' : null,
                    'page': page,
                    'pageSize': pageSize,
                  })}');
      if (mounted) {
        setState(() {
          rows = (r['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          total = intFrom(r['total']) ?? 0;
          loading = false;
          error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = friendlyError(e.message);
        });
      }
    }
  }

  void _changed() {
    page = 1;
    unawaited(load());
  }

  Future<void> edit([Map<String, dynamic>? m]) async {
    final api = AppScope.read(context).api;
    int? sup = intFrom(m?['supplierId']) ?? supplierId;
    final code = TextEditingController(text: '${m?['materialCode'] ?? ''}');
    final mtype = TextEditingController(text: '${m?['materialType'] ?? ''}');
    final vendor = TextEditingController(text: '${m?['vendorMaterial'] ?? ''}');
    final desc = TextEditingController(text: '${m?['description'] ?? ''}');
    final lead = TextEditingController(text: '${m?['leadTimeDays'] ?? ''}');
    bool active = m?['isActive'] != false;
    String? error;
    final saved = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> save() async {
          final lt = int.tryParse(lead.text.trim());
          if (sup == null) return setState(() => error = 'Choose the supplier');
          if (lt == null || lt < 1 || lt > 365) {
            return setState(() => error = 'Lead time must be 1–365 days');
          }
          final body = {
            'supplierId': sup,
            'materialCode': code.text.trim(),
            'materialType': mtype.text.trim(),
            'vendorMaterial': vendor.text.trim(),
            'description': desc.text.trim(),
            'leadTimeDays': lt,
            'isActive': active,
          };
          try {
            if (m == null) {
              await api.postJson('/masters/materials', body);
            } else {
              await api.patchJson('/masters/materials/${m['id']}', body);
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on ApiException catch (e) {
            setState(() => error = friendlyError(e.message));
          }
        }

        return AppDialog(
          title: m == null ? 'Add material' : 'Edit material',
          icon: Icons.science_outlined,
          width: 640,
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DsLabeledField(
              label: 'Supplier *',
              child: SearchableDropdownField<int>(
                value: sup,
                dialogTitle: 'Choose supplier',
                decoration: dsInput(hint: 'Search supplier'),
                items: [
                  for (final s in suppliers)
                    SearchableDropdownItem<int>(
                        value: intFrom(s['id']),
                        label: '${s['name']}',
                        subtitle:
                            '${s['supplierCode']} · ${s['shortName'] ?? ''}'),
                ],
                onChanged: (v) => setState(() => sup = v),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: DsLabeledField(
                      label: 'Material code (SAP)',
                      child: TextField(
                          controller: code,
                          decoration: dsInput(hint: '13000543')))),
              const SizedBox(width: 12),
              Expanded(
                child: DsLabeledField(
                  label: 'Type',
                  child: TextField(
                      controller: mtype, decoration: dsInput(hint: 'RM-CHE')),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 140,
                child: DsLabeledField(
                  label: 'Lead time (days) *',
                  child: TextField(
                    controller: lead,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: dsInput(),
                  ),
                ),
              ),
            ]),
            if (types.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                const Text('Types in use: ', style: DsType.metaSm),
                for (final t in types)
                  InkWell(
                    onTap: () => setState(() => mtype.text = t),
                    child: DsTag(t,
                        color: mtype.text == t ? DsColors.navyDeep : null,
                        bg: mtype.text == t ? DsColors.navySoft : null),
                  ),
              ]),
            ],
            const SizedBox(height: 12),
            DsLabeledField(
              label: 'Vendor material (supplier\'s product name)',
              child: TextField(
                  controller: vendor,
                  decoration: dsInput(hint: 'PZH-N (FLUOROZIRCONIC ACID 40%)')),
            ),
            const SizedBox(height: 12),
            DsLabeledField(
                label: 'Material description',
                child: TextField(
                    controller: desc, decoration: dsInput(hint: 'TA22B'))),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: active,
              title: const Text('Active', style: TextStyle(fontSize: 13)),
              onChanged: (v) => setState(() => active = v),
            ),
            if (error != null)
              InfoStrip(
                  text: error!,
                  icon: Icons.error_outline,
                  color: DsColors.redFg),
          ]),
          actions: [
            DsOutlineButton(
                label: 'Cancel',
                height: 40,
                onPressed: () => Navigator.pop(ctx, false)),
            DsPrimaryButton(
                label: 'Save',
                icon: Icons.save_outlined,
                height: 40,
                onPressed: save),
          ],
        );
      }),
    );
    if (saved == true) {
      if (mounted) AppToast.success(context, 'Material saved');
      unawaited(load());
    }
  }

  Future<void> delete(Map<String, dynamic> m) async {
    final ok = await confirmAction(context,
        title: 'Delete material ${m['materialCode'] ?? m['vendorMaterial']}?',
        message:
            'It will be removed from the master. POs that already have it keep their copy.',
        confirmLabel: 'Delete',
        danger: true);
    if (!ok || !mounted) return;
    final api = AppScope.read(context).api;
    if (await guard(
            context, () => api.deleteJson('/masters/materials/${m['id']}'),
            success: 'Material deleted') !=
        null) {
      unawaited(load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return Column(children: [
      _MasterToolbar(
        search: search,
        onSearch: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), _changed);
        },
        onAdd: () => edit(),
        onImported: () {
          unawaited(_lookups());
          unawaited(load());
        },
        children: [
          SizedBox(
            width: 230,
            height: 40,
            child: DropdownButtonFormField<int>(
              key: ValueKey('sup-$supplierId-${suppliers.length}'),
              initialValue: suppliers.any((s) => intFrom(s['id']) == supplierId)
                  ? supplierId
                  : null,
              isExpanded: true,
              decoration: dsInput(hint: 'All suppliers'),
              style: const TextStyle(fontSize: 12.5, color: DsColors.heading),
              items: [
                const DropdownMenuItem<int>(
                    value: null, child: Text('All suppliers')),
                for (final s in suppliers)
                  DropdownMenuItem(
                      value: intFrom(s['id']),
                      child: Text('${s['shortName'] ?? s['name']}',
                          overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                supplierId = v;
                _changed();
              },
            ),
          ),
          SizedBox(
            width: 160,
            height: 40,
            child: DropdownButtonFormField<String>(
              key: ValueKey('type-$type-${types.length}'),
              initialValue: type,
              isExpanded: true,
              decoration: dsInput(hint: 'All types'),
              style: const TextStyle(fontSize: 12.5, color: DsColors.heading),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('All types')),
                for (final t in types)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                type = v;
                _changed();
              },
            ),
          ),
          FilterChip(
            label: const Text('No material code'),
            selected: missingCode,
            onSelected: (v) {
              missingCode = v;
              _changed();
            },
          ),
        ],
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
                    : MinWidthScroll(
                        minWidth: 1100,
                        child: Column(children: [
                          _row(null, scope, header: true),
                          const Divider(height: 1),
                          Expanded(
                            child: rows.isEmpty
                                ? const DsEmptyState(
                                    icon: Icons.science_outlined,
                                    message: 'No material matches')
                                : ListView.separated(
                                    itemCount: rows.length,
                                    separatorBuilder: (_, __) => const Divider(
                                        height: 1, color: DsColors.lineSoft),
                                    itemBuilder: (_, i) => _row(rows[i], scope),
                                  ),
                          ),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            child: Row(children: [
                              Text(plural(total, 'material'),
                                  style: DsType.meta),
                              const Spacer(),
                              PaginationBar(
                                page: page - 1,
                                totalItems: total,
                                pageSize: pageSize,
                                onChanged: (p) {
                                  page = p + 1;
                                  unawaited(load());
                                },
                              ),
                            ]),
                          ),
                        ])),
          ),
        ),
      ),
    ]);
  }

  Widget _row(Map<String, dynamic>? m, AppScope scope, {bool header = false}) {
    Widget c(String t, double? w, {TextStyle? style, int flex = 1}) {
      final text = Text(header ? t.toUpperCase() : t,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: header
              ? DsType.eyebrow
              : style ?? const TextStyle(fontSize: 12.5, color: DsColors.text));
      return w == null
          ? Expanded(flex: flex, child: text)
          : SizedBox(width: w, child: text);
    }

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        c(
            header
                ? 'Supplier'
                : '${m!['supplierShort'] ?? m['supplierName'] ?? '-'}',
            150,
            style: DsType.rowTitle),
        SizedBox(
          width: 110,
          child: header
              ? const Text('MATERIAL CODE', style: DsType.eyebrow)
              : m!['materialCode'] == null
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: DsTag('no code',
                          color: DsColors.amberFg, bg: DsColors.amberBg))
                  : Text('${m['materialCode']}',
                      style: mono(size: 12.5, weight: FontWeight.w700)),
        ),
        c(header ? 'Type' : '${m!['materialType'] ?? '-'}', 100),
        c(header ? 'Vendor material' : '${m!['vendorMaterial'] ?? '-'}', null,
            flex: 3),
        c(header ? 'Description' : '${m!['description'] ?? '-'}', null,
            flex: 2),
        SizedBox(
          width: 90,
          child: header
              ? const Text('LEAD TIME', style: DsType.eyebrow)
              : Text('${m!['leadTimeDays']} days',
                  style: mono(size: 12, weight: FontWeight.w700)),
        ),
        SizedBox(
          width: 80,
          child: header
              ? const Text('STATUS', style: DsType.eyebrow)
              : Align(
                  alignment: Alignment.centerLeft,
                  child: m!['isActive'] == true
                      ? const DsTag('Active',
                          color: DsColors.greenFg, bg: DsColors.greenBg)
                      : const DsTag('Inactive'),
                ),
        ),
        SizedBox(
          width: 80,
          child: header || !scope.isSectionAdmin
              ? const SizedBox()
              : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  DsIconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onTap: () => edit(m)),
                  DsIconButton(
                      icon: Icons.delete_outline,
                      tooltip: 'Delete',
                      color: DsColors.redFg,
                      onTap: () => delete(m!)),
                ]),
        ),
      ]),
    );
    if (header) return Container(color: DsColors.subtle, child: content);
    return InkWell(
        onTap: scope.isSectionAdmin ? () => edit(m) : null, child: content);
  }
}
