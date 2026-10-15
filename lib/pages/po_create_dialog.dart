part of '../main.dart';

/// Manual entry of one PO (for when there is no SAP file). Returns the new id.
Future<int?> showPoCreateDialog(BuildContext context) {
  final api = AppScope.read(context).api;
  return showGlassDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PoCreateDialog(api: api));
}

class _Line {
  int? materialId;
  final code = TextEditingController();
  final text = TextEditingController();
  final qty = TextEditingController();
  final unit = TextEditingController();
  final price = TextEditingController();
  int? leadTime;
  void dispose() {
    for (final c in [code, text, qty, unit, price]) {
      c.dispose();
    }
  }
}

class _PoCreateDialog extends StatefulWidget {
  const _PoCreateDialog({required this.api});
  final ApiClient api;
  @override
  State<_PoCreateDialog> createState() => _PoCreateDialogState();
}

class _PoCreateDialogState extends State<_PoCreateDialog> {
  final poNo = TextEditingController();
  final remark = TextEditingController();
  final currency = TextEditingController();
  DateTime docDate = DateTime.now();
  String? mode;
  int? supplierId;
  List<Map<String, dynamic>> suppliers = [];
  List<Map<String, dynamic>> materials = [];
  final List<_Line> lines = [_Line()];
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSuppliers());
  }

  @override
  void dispose() {
    poNo.dispose();
    remark.dispose();
    currency.dispose();
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    try {
      final r = await widget.api.getJson('/masters/lookup');
      setState(() => suppliers = (r['suppliers'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {}
  }

  Future<void> _loadMaterials() async {
    if (supplierId == null) return;
    try {
      final r =
          await widget.api.getJson('/masters/lookup?supplierId=$supplierId');
      setState(() => materials = (r['materials'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {}
  }

  int? get _leadPreview {
    final days = lines.map((l) => l.leadTime).whereType<int>().toList();
    if (days.isNotEmpty) return days.reduce(max);
    final s = suppliers.where((s) => intFrom(s['id']) == supplierId).toList();
    return s.isEmpty ? null : intFrom(s.first['defaultLeadTimeDays']);
  }

  Future<void> save() async {
    if (poNo.text.trim().isEmpty) {
      return setState(() => error = 'Enter the PO number');
    }
    if (!RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(poNo.text.trim())) {
      return setState(
          () => error = 'PO No. may only contain letters, digits and . _ / -');
    }
    if (supplierId == null) {
      return setState(() => error = 'Choose the supplier');
    }
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.materialId == null &&
          l.code.text.trim().isEmpty &&
          l.text.text.trim().isEmpty) {
        continue;
      }
      items.add({
        'itemNo': '${(i + 1) * 10}',
        if (l.materialId != null) 'materialId': l.materialId,
        if (l.code.text.trim().isNotEmpty) 'materialCode': l.code.text.trim(),
        if (l.text.text.trim().isNotEmpty) 'shortText': l.text.text.trim(),
        if (double.tryParse(l.qty.text.replaceAll(',', '')) != null)
          'orderQty': double.parse(l.qty.text.replaceAll(',', '')),
        if (l.unit.text.trim().isNotEmpty) 'orderUnit': l.unit.text.trim(),
        if (double.tryParse(l.price.text.replaceAll(',', '')) != null)
          'netPrice': double.parse(l.price.text.replaceAll(',', '')),
        if (currency.text.trim().isNotEmpty)
          'currency': currency.text.trim().toUpperCase(),
      });
    }
    if (items.isEmpty) {
      return setState(() => error = 'Add at least one material line');
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api.postJson('/pos', {
        'poNo': poNo.text.trim(),
        'supplierId': supplierId,
        'documentDate': isoDate(docDate),
        if (mode != null) 'shipMode': mode,
        if (remark.text.trim().isNotEmpty) 'remark': remark.text.trim(),
        'items': items,
      });
      if (mounted) {
        AppToast.success(context, 'PO ${poNo.text.trim()} added');
        Navigator.pop(context, intFrom(r['id']));
      }
    } on ApiException catch (e) {
      setState(() {
        busy = false;
        error = friendlyError(e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lead = _leadPreview;
    return AppDialog(
      title: 'New PO (manual entry)',
      subtitle:
          'กรอก PO เอง — for POs not in an SAP file. The PO date is the only date you enter.',
      icon: Icons.add_box_outlined,
      width: 900,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: DsLabeledField(
              label: 'PO No. *',
              child: TextField(
                  controller: poNo,
                  autofocus: true,
                  decoration: dsInput(hint: '1910000451', icon: Icons.tag)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DsLabeledField(
              label: 'Supplier *',
              child: SearchableDropdownField<int>(
                value: supplierId,
                dialogTitle: 'Choose supplier',
                searchHint: 'Search supplier name or ID',
                decoration: dsInput(hint: 'Search the Supplier Master'),
                items: [
                  for (final s in suppliers)
                    SearchableDropdownItem<int>(
                      value: intFrom(s['id']),
                      label: '${s['name']}',
                      subtitle:
                          '${s['supplierCode']}${s['shortName'] == null ? '' : ' · ${s['shortName']}'}'
                          '${s['defaultLeadTimeDays'] == null ? '' : ' · ${s['defaultLeadTimeDays']} days'}',
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    supplierId = v;
                    materials = [];
                    for (final l in lines) {
                      l.materialId = null;
                      l.leadTime = null;
                    }
                  });
                  unawaited(_loadMaterials());
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DsLabeledField(
              label: 'PO date (N1) *',
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                      context: context,
                      initialDate: docDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now());
                  if (picked != null) setState(() => docDate = picked);
                },
                child: InputDecorator(
                    decoration: dsInput(icon: Icons.event_outlined),
                    child: Text(fmtDate(isoDate(docDate)))),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: DsLabeledField(
              label: 'Shipping mode',
              child: SearchableDropdownField<String>(
                value: mode,
                dialogTitle: 'Shipping mode',
                decoration: dsInput(),
                items: shipModeItems,
                onChanged: (v) => setState(() => mode = v),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: DsLabeledField(
                label: 'Currency',
                child: TextField(
                    controller: currency, decoration: dsInput(hint: 'JPY'))),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DsLabeledField(
                label: 'Remark',
                child: TextField(
                    controller: remark, decoration: dsInput(hint: 'Optional'))),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          const DsSectionLabel('Material lines'),
          const Spacer(),
          if (supplierId != null && materials.isEmpty)
            const Text(
                'This supplier has no materials in the master — type the code by hand',
                style: DsType.metaSm),
        ]),
        const SizedBox(height: 8),
        for (var i = 0; i < lines.length; i++) _lineRow(i),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: lines.length >= 200
                ? null
                : () => setState(() => lines.add(_Line())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add line'),
          ),
        ),
        const SizedBox(height: 8),
        InfoStrip(
          icon: Icons.timelapse,
          text: lead == null
              ? 'Lead time: the section default will be used (no material or supplier lead time yet).'
              : 'Lead time $lead days → expected at the factory around ${fmtDate(isoDate(docDate.add(Duration(days: lead))))}.',
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          InfoStrip(
              text: error!, icon: Icons.error_outline, color: DsColors.redFg),
        ],
      ]),
      actions: [
        DsOutlineButton(
            label: 'Cancel',
            height: 40,
            onPressed: busy ? null : () => Navigator.pop(context)),
        DsPrimaryButton(
            label: busy ? 'Saving…' : 'Add PO',
            icon: Icons.check,
            height: 40,
            onPressed: busy ? null : save),
      ],
    );
  }

  Widget _lineRow(int i) {
    final l = lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
            width: 34,
            child: Text('${(i + 1) * 10}',
                style: mono(size: 11.5, color: DsColors.faint2))),
        Expanded(
          flex: 3,
          child: materials.isEmpty
              ? TextField(
                  controller: l.code,
                  decoration: dsInput(hint: 'Material code'))
              : SearchableDropdownField<int>(
                  value: l.materialId,
                  dialogTitle: 'Choose material',
                  searchHint: 'Search code, vendor material or description',
                  decoration: dsInput(hint: 'Material'),
                  items: [
                    for (final m in materials)
                      SearchableDropdownItem<int>(
                        value: intFrom(m['id']),
                        label:
                            '${m['materialCode'] ?? '(no code)'} · ${m['description'] ?? ''}',
                        subtitle:
                            '${m['vendorMaterial'] ?? ''} · ${m['materialType'] ?? ''} · ${m['leadTimeDays']} days',
                      ),
                  ],
                  onChanged: (v) {
                    final m = materials.firstWhere((x) => intFrom(x['id']) == v,
                        orElse: () => {});
                    setState(() {
                      l.materialId = v;
                      l.leadTime = intFrom(m['leadTimeDays']);
                      l.code.text = '${m['materialCode'] ?? ''}';
                      if (l.text.text.isEmpty) {
                        l.text.text = '${m['description'] ?? ''}';
                      }
                    });
                  },
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
            flex: 3,
            child: TextField(
                controller: l.text, decoration: dsInput(hint: 'Short text'))),
        const SizedBox(width: 8),
        SizedBox(
          width: 90,
          child: TextField(
            controller: l.qty,
            decoration: dsInput(hint: 'Qty'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
            width: 74,
            child: TextField(
                controller: l.unit, decoration: dsInput(hint: 'Unit'))),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: TextField(
            controller: l.price,
            decoration: dsInput(hint: 'Net price'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
          ),
        ),
        SizedBox(
          width: 60,
          child: l.leadTime == null
              ? const SizedBox()
              : Center(child: Text('${l.leadTime} d', style: DsType.metaSm)),
        ),
        IconButton(
          tooltip: 'Remove line',
          icon: const Icon(Icons.close, size: 18, color: DsColors.faint2),
          onPressed: lines.length == 1
              ? null
              : () => setState(() {
                    lines.removeAt(i).dispose();
                  }),
        ),
      ]),
    );
  }
}
