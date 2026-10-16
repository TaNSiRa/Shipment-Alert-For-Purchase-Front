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

  /// Description the master filled in, so picking another material (or
  /// supplier) replaces it but never overwrites what the user typed.
  String? autoText;

  /// Forget the master material; keeps the user's own description.
  void clearMaterial() {
    if (materialId != null) code.clear();
    if (autoText != null && text.text == autoText) text.clear();
    materialId = null;
    leadTime = null;
    autoText = null;
  }

  bool get isBlank =>
      materialId == null &&
      code.text.trim().isEmpty &&
      text.text.trim().isEmpty;

  double? get qtyValue => double.tryParse(qty.text.replaceAll(',', ''));
  double? get priceValue => double.tryParse(price.text.replaceAll(',', ''));
  double? get amount {
    final q = qtyValue, p = priceValue;
    return q == null || p == null ? null : q * p;
  }

  void dispose() {
    for (final c in [code, text, qty, unit, price]) {
      c.dispose();
    }
  }
}

/// Ship modes offered on the form, "Not set" first.
const _shipModes = <String?>[null, 'SEA', 'AIR', 'TRUCK', 'COURIER'];

/// Items-table column widths. Material and description share what is left.
const _colNo = 34.0;
const _colQty = 92.0;
const _colUnit = 72.0;
const _colPrice = 112.0;
const _colAmount = 112.0;
const _colLead = 52.0;
const _colRemove = 36.0;
const _tableMinWidth = 800.0;

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
  bool loadingMaterials = false;
  final List<_Line> lines = [_Line()];
  bool busy = false;

  // Field-level errors sit under the field they are about; [error] is for
  // what the server says.
  String? poNoError;
  String? supplierError;
  String? linesError;
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
    setState(() => loadingMaterials = true);
    try {
      final r =
          await widget.api.getJson('/masters/lookup?supplierId=$supplierId');
      setState(() => materials = (r['materials'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    } catch (_) {
    } finally {
      if (mounted) setState(() => loadingMaterials = false);
    }
  }

  Map<String, dynamic>? get _supplier {
    for (final s in suppliers) {
      if (intFrom(s['id']) == supplierId) return s;
    }
    return null;
  }

  /// Lead time the PO will get and where it comes from: the longest material
  /// lead time on the lines.
  (int, String)? get _lead {
    final days = lines.map((l) => l.leadTime).whereType<int>().toList();
    if (days.isEmpty) return null;
    return (days.reduce(max), 'longest material lead time');
  }

  double? get _total {
    final amounts = lines.map((l) => l.amount).whereType<double>().toList();
    return amounts.isEmpty ? null : amounts.reduce((a, b) => a + b);
  }

  String get _currencyCode => currency.text.trim().toUpperCase();

  Future<void> save() async {
    final no = poNo.text.trim();
    String? noErr;
    if (no.isEmpty) {
      noErr = 'Enter the PO number';
    } else if (!RegExp(r'^[A-Za-z0-9._/-]+$').hasMatch(no)) {
      noErr = 'Only letters, digits and . _ / -';
    }
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.isBlank) continue;
      items.add({
        'itemNo': '${(i + 1) * 10}',
        if (l.materialId != null) 'materialId': l.materialId,
        if (l.code.text.trim().isNotEmpty) 'materialCode': l.code.text.trim(),
        if (l.text.text.trim().isNotEmpty) 'shortText': l.text.text.trim(),
        if (l.qtyValue != null) 'orderQty': l.qtyValue,
        if (l.unit.text.trim().isNotEmpty) 'orderUnit': l.unit.text.trim(),
        if (l.priceValue != null) 'netPrice': l.priceValue,
        if (_currencyCode.isNotEmpty) 'currency': _currencyCode,
      });
    }
    setState(() {
      poNoError = noErr;
      supplierError = supplierId == null ? 'Choose the supplier' : null;
      linesError = items.isEmpty
          ? 'Add at least one item — a material code or a description'
          : null;
      error = null;
    });
    if (poNoError != null || supplierError != null || linesError != null) {
      return;
    }
    setState(() => busy = true);
    try {
      final r = await widget.api.postJson('/pos', {
        'poNo': no,
        'supplierId': supplierId,
        'documentDate': isoDate(docDate),
        if (mode != null) 'shipMode': mode,
        if (remark.text.trim().isNotEmpty) 'remark': remark.text.trim(),
        'items': items,
      });
      if (mounted) {
        AppToast.success(context, 'PO $no added');
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
    return AppDialog(
      title: 'New purchase order',
      subtitle: 'Manual entry for a PO that is not in an SAP file',
      icon: Icons.post_add_outlined,
      width: 980,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _section(
          step: 1,
          title: 'PO details',
          child: _details(),
        ),
        const SizedBox(height: 14),
        _section(
          step: 2,
          title: 'Items',
          badge: '${lines.where((l) => !l.isBlank).length}',
          trailing: _itemsHint(),
          child: _items(),
        ),
        const SizedBox(height: 14),
        _summary(),
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
            label: busy ? 'Saving…' : 'Create PO',
            icon: Icons.check,
            height: 40,
            onPressed: busy ? null : save),
      ],
    );
  }

  // ── Building blocks ─────────────────────────────────────────────────────

  /// A numbered group on the form, so the order to fill it in is obvious.
  Widget _section({
    required int step,
    required String title,
    String? badge,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DsColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: DsColors.navySoft, shape: BoxShape.circle),
            child: Text('$step',
                style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: DsColors.navyDeep)),
          ),
          const SizedBox(width: 9),
          Text(title,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: DsColors.heading)),
          if (badge != null) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                  color: DsColors.track,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(badge,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DsColors.muted)),
            ),
          ],
          const SizedBox(width: 12),
          if (trailing != null) Expanded(child: trailing) else const Spacer(),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  /// Label above an input, a red mark when it is required and an optional
  /// line of help underneath.
  Widget _field(String label, Widget child,
      {bool required = false, String? help}) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: label),
              if (required)
                const TextSpan(
                    text: ' *', style: TextStyle(color: DsColors.redFg)),
            ]),
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: DsColors.text)),
          ),
          child,
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 2),
              child: Text(help,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsType.metaSm),
            ),
        ]);
  }

  // ── 1. PO details ───────────────────────────────────────────────────────

  Widget _details() {
    final s = _supplier;
    final supplierHelp = s == null
        ? null
        : [
            '${s['supplierCode']}',
            if (!loadingMaterials) plural(materials.length, 'material'),
          ].join(' · ');

    final poField = _field(
      'PO number',
      required: true,
      TextField(
        controller: poNo,
        autofocus: true,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._/-]'))
        ],
        onChanged: (_) {
          if (poNoError != null) setState(() => poNoError = null);
        },
        style: mono(size: 14, color: DsColors.heading),
        decoration: dsInput(
            hint: 'e.g. 1910000451', icon: Icons.tag, errorText: poNoError),
      ),
    );

    final supplierField = _field(
      'Supplier',
      required: true,
      help: supplierError == null ? supplierHelp : null,
      SearchableDropdownField<int>(
        value: supplierId,
        dialogTitle: 'Choose supplier',
        searchHint: 'Search supplier name or code',
        decoration: dsInput(
            hint: 'Search the Supplier Master',
            icon: Icons.storefront_outlined,
            errorText: supplierError),
        items: [
          for (final s in suppliers)
            SearchableDropdownItem<int>(
              value: intFrom(s['id']),
              label: '${s['name']}',
              subtitle:
                  '${s['supplierCode']}${s['shortName'] == null ? '' : ' · ${s['shortName']}'}',
            ),
        ],
        onChanged: (v) {
          if (v == supplierId) return;
          setState(() {
            supplierId = v;
            supplierError = null;
            materials = [];
            // Each supplier has its own materials (and lead times).
            for (final l in lines) {
              l.clearMaterial();
            }
          });
          unawaited(_loadMaterials());
        },
      ),
    );

    final dateField = _field(
      'PO date',
      required: true,
      help: 'Document date (N1)',
      Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () async {
            final picked = await showDatePicker(
                context: context,
                initialDate: docDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now());
            if (picked != null) setState(() => docDate = picked);
          },
          child: InputDecorator(
              decoration: dsInput(
                  icon: Icons.event_outlined,
                  suffix: const Icon(Icons.arrow_drop_down,
                      color: DsColors.iconSoft)),
              child: Text(fmtDate(isoDate(docDate)),
                  style: const TextStyle(
                      fontSize: 14, color: DsColors.heading))),
        ),
      ),
    );

    final modeField = _field('Shipping mode', _modePicker());

    final currencyField = _field(
      'Currency',
      TextField(
        controller: currency,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
          LengthLimitingTextInputFormatter(3),
          TextInputFormatter.withFunction((_, v) =>
              v.copyWith(text: v.text.toUpperCase())),
        ],
        onChanged: (_) => setState(() {}),
        style: mono(size: 14, color: DsColors.heading),
        decoration: dsInput(hint: 'JPY'),
      ),
    );

    final remarkField = _field(
      'Remark',
      TextField(
          controller: remark,
          decoration: dsInput(hint: 'Optional note for this PO')),
    );

    return LayoutBuilder(builder: (context, c) {
      const gap = SizedBox(width: 14, height: 14);
      if (c.maxWidth < 680) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              poField, gap, supplierField, gap, dateField, gap, //
              modeField, gap, currencyField, gap, remarkField,
            ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: poField),
          gap,
          Expanded(flex: 8, child: supplierField),
          gap,
          Expanded(flex: 4, child: dateField),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          modeField,
          gap,
          SizedBox(width: 96, child: currencyField),
          gap,
          Expanded(child: remarkField),
        ]),
      ]);
    });
  }

  /// Five options — a row of buttons reads faster than a search dialog.
  Widget _modePicker() {
    final picker = DsSegmented(
      selected: _shipModes.indexOf(mode),
      length: _shipModes.length,
      itemBuilder: (context, i, t) {
        final m = _shipModes[i];
        final color = Color.lerp(DsColors.muted, DsColors.navyDeep, t);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (m != null) ...[
              Icon(shipModeIcon(m), size: 16, color: color),
              const SizedBox(width: 5),
            ],
            Text(m == null ? 'Not set' : shipModeLabel(m),
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
          ]),
        );
      },
      onSelect: (i) => setState(() => mode = _shipModes[i]),
    );
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal, child: picker);
  }

  // ── 2. Items ────────────────────────────────────────────────────────────

  Widget _itemsHint() {
    final (IconData icon, String text) = supplierId == null
        ? (Icons.info_outline, 'Choose a supplier to pick from its materials')
        : loadingMaterials
            ? (Icons.hourglass_empty, 'Loading materials…')
            : materials.isEmpty
                ? (
                    Icons.edit_note,
                    'No materials in the master for this supplier — type the code by hand'
                  )
                : (
                    Icons.inventory_2_outlined,
                    'Pick from ${plural(materials.length, 'material')} of this supplier'
                  );
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      Icon(icon, size: 14, color: DsColors.iconSoft),
      const SizedBox(width: 5),
      Flexible(
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: DsType.metaSm),
      ),
    ]);
  }

  Widget _items() {
    final total = _total;
    final table = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _itemsHeader(),
          const SizedBox(height: 6),
          for (var i = 0; i < lines.length; i++) _lineRow(i),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(
        builder: (context, c) => c.maxWidth >= _tableMinWidth
            ? table
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: _tableMinWidth, child: table)),
      ),
      if (linesError != null)
        Padding(
          padding: const EdgeInsets.only(left: _colNo, bottom: 4),
          child: Text(linesError!,
              style: const TextStyle(fontSize: 12, color: DsColors.redFg)),
        ),
      const Divider(height: 14, color: DsColors.line),
      Row(children: [
        TextButton.icon(
          onPressed: lines.length >= 200
              ? null
              : () => setState(() => lines.add(_Line())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add item'),
        ),
        const Spacer(),
        const Text('Total', style: DsType.label),
        const SizedBox(width: 12),
        Text(total == null ? '—' : fmtMoney(total),
            style: mono(size: 15, weight: FontWeight.w700, color: DsColors.heading)),
        if (_currencyCode.isNotEmpty) ...[
          const SizedBox(width: 5),
          Text(_currencyCode, style: DsType.label),
        ],
        const SizedBox(width: _colLead + _colRemove),
      ]),
    ]);
  }

  Widget _itemsHeader() {
    Widget h(String text, {double? width, int? flex, bool right = false}) {
      final label = Text(text.toUpperCase(),
          textAlign: right ? TextAlign.right : TextAlign.left,
          style: DsType.eyebrow);
      final cell = Padding(
          padding: EdgeInsets.only(left: right ? 0 : 4, right: right ? 4 : 0),
          child: label);
      return flex != null
          ? Expanded(flex: flex, child: cell)
          : SizedBox(width: width, child: cell);
    }

    const gap = SizedBox(width: 8);
    return Row(children: [
      h('#', width: _colNo),
      h('Material', flex: 3),
      gap,
      h('Description', flex: 3),
      gap,
      h('Qty', width: _colQty, right: true),
      gap,
      h('Unit', width: _colUnit),
      gap,
      h('Net price', width: _colPrice, right: true),
      h('Amount', width: _colAmount, right: true),
      h('Lead', width: _colLead, right: true),
      const SizedBox(width: _colRemove),
    ]);
  }

  Widget _lineRow(int i) {
    final l = lines[i];
    final amount = l.amount;
    final numberFormatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
    ];
    void touched(String _) => setState(() {
          if (linesError != null && !l.isBlank) linesError = null;
        });
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(
            width: _colNo,
            child: Text('${(i + 1) * 10}',
                style: mono(size: 11.5, color: DsColors.faint2))),
        Expanded(
          flex: 3,
          child: materials.isEmpty
              ? TextField(
                  controller: l.code,
                  onChanged: touched,
                  style: mono(size: 13, color: DsColors.heading),
                  decoration: dsInput(hint: 'Material code'))
              : SearchableDropdownField<int>(
                  value: l.materialId,
                  dialogTitle: 'Choose material',
                  searchHint: 'Search code, vendor material or description',
                  decoration: dsInput(hint: 'Choose material'),
                  items: [
                    for (final m in materials)
                      SearchableDropdownItem<int>(
                        value: intFrom(m['id']),
                        // Code only: the description lands in the next
                        // column, so repeating it here just gets cut off.
                        label: '${m['materialCode'] ?? '(no code)'}',
                        subtitle: [
                          m['description'],
                          m['vendorMaterial'],
                          m['materialType'],
                          if (m['leadTimeDays'] != null)
                            '${m['leadTimeDays']} days',
                        ]
                            .where((v) => v != null && '$v'.isNotEmpty)
                            .join(' · '),
                      ),
                  ],
                  onChanged: (v) {
                    final m = materials.firstWhere((x) => intFrom(x['id']) == v,
                        orElse: () => {});
                    setState(() {
                      l.materialId = v;
                      l.leadTime = intFrom(m['leadTimeDays']);
                      l.code.text = '${m['materialCode'] ?? ''}';
                      if (l.text.text.isEmpty || l.text.text == l.autoText) {
                        l.text.text = '${m['description'] ?? ''}';
                        l.autoText = l.text.text;
                      }
                      linesError = null;
                    });
                  },
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
            flex: 3,
            child: TextField(
                controller: l.text,
                onChanged: touched,
                decoration: dsInput(hint: 'Description'))),
        const SizedBox(width: 8),
        SizedBox(
          width: _colQty,
          child: TextField(
            controller: l.qty,
            onChanged: touched,
            textAlign: TextAlign.right,
            style: mono(size: 13, color: DsColors.heading),
            decoration: dsInput(hint: '0'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: numberFormatters,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
            width: _colUnit,
            child: TextField(
                controller: l.unit,
                decoration: dsInput(hint: 'PC'))),
        const SizedBox(width: 8),
        SizedBox(
          width: _colPrice,
          child: TextField(
            controller: l.price,
            onChanged: touched,
            textAlign: TextAlign.right,
            style: mono(size: 13, color: DsColors.heading),
            decoration: dsInput(hint: '0.00'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: numberFormatters,
          ),
        ),
        SizedBox(
          width: _colAmount,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(amount == null ? '—' : fmtMoney(amount),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(
                    size: 13,
                    weight: FontWeight.w600,
                    color: amount == null ? DsColors.faint2 : DsColors.heading)),
          ),
        ),
        SizedBox(
          width: _colLead,
          child: Align(
            alignment: Alignment.centerRight,
            child: l.leadTime == null
                ? const Text('—', style: DsType.metaSm)
                : Tooltip(
                    message: 'Material lead time',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                          color: DsColors.tealBg,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text('${l.leadTime} d',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: DsColors.tealFg)),
                    ),
                  ),
          ),
        ),
        SizedBox(
          width: _colRemove,
          child: IconButton(
            tooltip: 'Remove item',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 17, color: DsColors.faint2),
            onPressed: lines.length == 1
                ? null
                : () => setState(() {
                      lines.removeAt(i).dispose();
                    }),
          ),
        ),
      ]),
    );
  }

  // ── Summary ─────────────────────────────────────────────────────────────

  /// What the PO will be tracked against once it is saved.
  Widget _summary() {
    final lead = _lead;
    Widget stat(IconData icon, String label, String value, [String? note]) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 17, color: DsColors.navyDeep),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: DsType.metaSm),
          const SizedBox(height: 1),
          Text.rich(TextSpan(children: [
            TextSpan(text: value),
            if (note != null)
              TextSpan(
                  text: '  $note',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: DsColors.muted2)),
          ]),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: DsColors.heading)),
        ]),
      ]);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: DsColors.navy.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DsColors.navy.withValues(alpha: .18)),
      ),
      child: lead == null
          ? Row(children: [
              const Icon(Icons.timelapse, size: 17, color: DsColors.navy),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                    'Lead time: the section default will be used — no material or supplier lead time yet.',
                    style: DsType.body.copyWith(fontSize: 12.5)),
              ),
            ])
          : Wrap(
              spacing: 18,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                stat(Icons.timelapse, 'Lead time', '${lead.$1} days',
                    '(${lead.$2})'),
                const Icon(Icons.arrow_forward,
                    size: 18, color: DsColors.iconSoft),
                stat(
                    Icons.factory_outlined,
                    'Expected at the factory around',
                    fmtDate(isoDate(docDate.add(Duration(days: lead.$1))))),
              ],
            ),
    );
  }
}
