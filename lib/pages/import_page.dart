part of '../main.dart';

/// The three SAP files that drive a PO, on a page of their own — each upload
/// can touch many POs at once, so it is reviewed in full before it is saved:
///   1. DATA EXPORT BY SAP  — creates the POs (Issue PO) + each PO's Delivery
///                           date (POs on the same date = one shipment)
///   2. OCR ACK            — closes "OCR Acknowledgement" and groups the POs
///                           into shipments (Acknowledgment No.)
///   3. OCR SI             — closes "OCR Shipping Instruction", brings ETD / ETA
/// The server tells which file it got; the page follows it.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.args});
  final Map<String, dynamic>? args;
  @override
  State<ImportPage> createState() => _ImportPageState();
}

const _importKinds = ['PO', 'ACK', 'SI'];

/// Dashed rounded-rectangle outline for the file drop zone.
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter(
      {required this.color, this.radius = 16, this.strokeWidth = 1.6});
  final Color color;
  final double radius, strokeWidth;
  static const dash = 8.0, gap = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            inset, inset, size.width - strokeWidth, size.height - strokeWidth),
        Radius.circular(radius - inset));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (final metric in (Path()..addRRect(rrect)).computeMetrics()) {
      for (double d = 0; d < metric.length; d += dash + gap) {
        canvas.drawPath(
            metric.extractPath(d, (d + dash).clamp(0, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}

class _ImportPageState extends State<ImportPage> {
  int mode = 0;
  PickedFile? file;
  Map<String, dynamic>? result;
  bool busy = false;
  String? error;
  Map<String, dynamic>? done;
  final Set<String> expanded = {};

  // DATA EXPORT — Delivery date per PO (poNo -> date). POs that arrive
  // together share a date; each can differ.
  final Map<String, DateTime> deliveries = {};
  DateTime? _lastDelivery;
  final Set<String> chosen = {};
  final Map<String, String?> modes = {};

  // OCR
  DateTime actualDate = DateTime.now();
  final Set<String> chosenKeys = {};

  List<Map<String, dynamic>> history = [];
  int _tick = -1;

  @override
  void initState() {
    super.initState();
    final k = _importKinds.indexOf('${widget.args?['kind'] ?? ''}');
    if (k >= 0) mode = k;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).refreshTick;
    if (tick != _tick) {
      _tick = tick;
      unawaited(loadHistory());
    }
  }

  String get kind => '${result?['kind'] ?? _importKinds[mode]}';

  Future<void> loadHistory() async {
    try {
      final r = await AppScope.read(context)
          .api
          .getJson('/pos/import/batches?pageSize=8');
      if (mounted) {
        setState(() => history = (r['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());
      }
    } catch (_) {
      // The history is a convenience; the page works without it.
    }
  }

  void reset() => setState(() {
        file = null;
        result = null;
        done = null;
        error = null;
        busy = false;
        chosen.clear();
        chosenKeys.clear();
        modes.clear();
        deliveries.clear();
        expanded.clear();
      });

  Future<void> pick() async {
    final picked = await pickExcelFile();
    if (picked == null) return;
    setState(() {
      file = picked;
      result = null;
      done = null;
      error = null;
      chosen.clear();
      chosenKeys.clear();
      modes.clear();
      deliveries.clear();
      expanded.clear();
    });
    await runPreview(selectDefaults: true);
  }

  Future<void> runPreview({bool selectDefaults = false}) async {
    if (file == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r =
          await AppScope.read(context).api.postJson('/pos/import/preview', {
        'fileName': file!.name,
        'data': file!.base64,
        'actualDate': isoDate(actualDate),
      });
      if (!mounted) return;
      setState(() {
        result = r;
        busy = false;
        final k = _importKinds.indexOf('${r['kind']}');
        if (k >= 0) mode = k;
        if (r['kind'] == 'PO') {
          if (selectDefaults) {
            chosen.addAll((r['pos'] as List)
                .where((p) => p['status'] == 'NEW')
                .map((p) => '${p['poNo']}'));
          }
        } else {
          final selectable = (r['rows'] as List)
              .where((x) => x['selectable'] == true)
              .map((x) => '${x['key']}')
              .toSet();
          if (selectDefaults) {
            chosenKeys.addAll(selectable);
          } else {
            chosenKeys.removeWhere((k) => !selectable.contains(k));
          }
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = friendlyError(e.message);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'Could not send the file to the server';
        });
      }
    }
  }

  Future<void> commit() async {
    if (file == null || result == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final body = <String, dynamic>{
        'kind': kind,
        'fileName': file!.name,
        'data': file!.base64,
      };
      if (kind == 'PO') {
        body['poNos'] = chosen.toList();
        body['modes'] = _modePayload();
        body['deliveryDates'] = {
          for (final p in _chosenNew)
            if (deliveries['${p['poNo']}'] != null)
              '${p['poNo']}': isoDate(deliveries['${p['poNo']}']!),
        };
      } else {
        body['keys'] = chosenKeys.toList();
        body['actualDate'] = isoDate(actualDate);
      }
      final r =
          await AppScope.read(context).api.postJson('/pos/import/commit', body);
      if (!mounted) return;
      setState(() {
        busy = false;
        done = r;
      });
      unawaited(loadHistory());
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = friendlyError(e.message);
        });
      }
    }
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (scope.canEdit && done == null && result != null) return _previewPage();
    return PageBody(children: [
      DsRise(child: _kindCards()),
      const SizedBox(height: 16),
      DsRise(
        index: 1,
        child: DsCard(
          padding: const EdgeInsets.all(18),
          child: !scope.canEdit
              ? const InfoStrip(
                  text:
                      'You can view the import history, but uploading needs edit rights in this section.',
                  icon: Icons.lock_outline)
              : done != null
                  ? _done()
                  : result == null
                      ? _start()
                      : const SizedBox.shrink(),
        ),
      ),
      const SizedBox(height: 16),
      DsRise(index: 2, child: _history()),
    ]);
  }

  /// The preview as page slivers, so the table's header row stays pinned
  /// under the top bar while the whole page scrolls through the POs. The
  /// white pieces line up into one card.
  Widget _previewPage() {
    final parts = kind == 'PO' ? _poParts() : _ocrParts();
    const side = 22.0;
    const pad = 18.0;
    const radius = Radius.circular(20);
    Widget piece(Widget child, {bool first = false, bool last = false}) =>
        Container(
          padding:
              EdgeInsets.fromLTRB(pad, first ? pad : 0, pad, last ? pad : 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
                top: first ? radius : Radius.zero,
                bottom: last ? radius : Radius.zero),
          ),
          child: child,
        );
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(side, 18, side, 0),
        sliver: SliverToBoxAdapter(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _kindCards(),
            const SizedBox(height: 16),
            piece(
                Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: parts.top),
                first: true),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: side),
        sliver: SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedHeader(
            height: 72,
            builder: (pinned) => Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: pinned
                    ? const [
                        BoxShadow(
                            color: Color(0x1a1e1b4b),
                            blurRadius: 10,
                            offset: Offset(0, 4))
                      ]
                    : null,
              ),
              padding: const EdgeInsets.fromLTRB(pad, 4, pad, 4),
              alignment: Alignment.center,
              child: parts.header,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: side),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => piece(parts.rows[i]),
            childCount: parts.rows.length,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(side, 0, side, 28),
        sliver: SliverToBoxAdapter(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            piece(
                Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: parts.bottom),
                last: true),
            const SizedBox(height: 16),
            _history(),
          ]),
        ),
      ),
    ]);
  }

  Widget _kindCards() {
    const cards = [
      (
        '1',
        'DATA EXPORT BY SAP',
        'Creates the POs (step 1 · Issue PO). Choose each PO\'s Delivery date — it is when "Factory good received" is due.',
        Icons.table_view_outlined
      ),
      (
        '2',
        'OCR ACK',
        'Moves the POs past "OCR Acknowledgement from SAP". The Acknowledgment No. groups them into one shipment; quantities are checked.',
        Icons.document_scanner_outlined
      ),
      (
        '3',
        'OCR SI',
        'Moves the POs past "OCR Shipping Instruction from SAP" and stores the shipment\'s ETD and ETA.',
        Icons.directions_boat_outlined
      ),
    ];
    final wide = MediaQuery.of(context).size.width > 900;
    final tiles = [
      for (var i = 0; i < cards.length; i++)
        DsHoverLift(
          onTap: busy || (result != null && done == null)
              ? null
              : () => setState(() {
                    mode = i;
                    if (done != null) reset();
                  }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: mode == i
                  ? DsColors.navySoft.withValues(alpha: .18)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: mode == i ? DsColors.navy : DsColors.cardBorder,
                  width: mode == i ? 1.6 : 1),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mode == i ? DsColors.navy : DsColors.chip,
                  shape: BoxShape.circle,
                ),
                child: Text(cards[i].$1,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: mode == i ? Colors.white : DsColors.muted)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(cards[i].$4, size: 17, color: DsColors.navy),
                        const SizedBox(width: 6),
                        Flexible(
                            child: Text(cards[i].$2, style: DsType.cardTitle)),
                      ]),
                      const SizedBox(height: 5),
                      Text(cards[i].$3, style: DsType.metaSm),
                    ]),
              ),
            ]),
          ),
        ),
    ];
    if (!wide) {
      return Column(children: [
        for (final t in tiles) ...[t, const SizedBox(height: 10)]
      ]);
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < tiles.length; i++) ...[
          Expanded(child: tiles[i]),
          if (i < tiles.length - 1) const SizedBox(width: 12),
        ]
      ]),
    );
  }

  Widget _start() {
    final label = ['DATA EXPORT BY SAP', 'OCR ACK', 'OCR SI'][mode];
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: busy ? null : pick,
                child: CustomPaint(
                  foregroundPainter: _DashedRRectPainter(
                      color: DsColors.navy.withValues(alpha: .55),
                      radius: 16,
                      strokeWidth: 1.6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 38, horizontal: 20),
                    decoration: BoxDecoration(
                      color: DsColors.navySoft.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(children: [
                      if (busy)
                        const SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(strokeWidth: 3))
                      else
                        const Icon(Icons.cloud_upload_outlined,
                            size: 44, color: DsColors.navy),
                      const SizedBox(height: 12),
                      Text(
                          busy
                              ? 'Reading ${file?.name ?? 'file'}…'
                              : 'Click to choose the $label file (.xlsx)',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: DsColors.heading)),
                      const SizedBox(height: 6),
                      const Text(
                          'Nothing is saved until you review every PO it touches and press the button. '
                          'The type of file is recognised automatically.',
                          textAlign: TextAlign.center,
                          style: DsType.meta),
                    ]),
                  ),
                ),
              )),
          if (error != null) ...[
            const SizedBox(height: 12),
            InfoStrip(
                text: error!, icon: Icons.error_outline, color: DsColors.redFg),
          ],
          if (mode == 0) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _template,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Not using SAP? Download the template')),
            ),
          ],
        ]);
  }

  Future<void> _template() async {
    try {
      final bytes =
          await AppScope.read(context).api.getBytes('/pos/import/template');
      saveBytes(bytes, 'po-import-template.xlsx');
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not download the template');
    }
  }

  /// One summary chip; nothing at all when the count is zero (the file's
  /// size chip excepted), so only what needs a look is on screen.
  Widget _stat(String label, dynamic value, Color color,
      {bool always = false}) {
    final n = intFrom(value) ?? 0;
    if (n == 0 && !always) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$n', style: DsType.stat(16, color: color)),
        const SizedBox(width: 7),
        Text(label,
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  /// Chips with something to say: a zero-count chip is left out entirely
  /// (an empty box would still take its spacing in the Wrap).
  List<Widget> _visible(List<Widget> chips) =>
      chips.where((w) => w is! SizedBox).toList();

  Widget _fileLine(String extra) => Row(children: [
        const Icon(Icons.description_outlined, size: 18, color: DsColors.icon),
        const SizedBox(width: 6),
        Expanded(
          child: Text('${file?.name} · $extra',
              style: DsType.meta, overflow: TextOverflow.ellipsis),
        ),
        TextButton.icon(
            onPressed: busy ? null : pick,
            icon: const Icon(Icons.folder_open, size: 17),
            label: const Text('Choose another file')),
        TextButton(onPressed: busy ? null : reset, child: const Text('Cancel')),
      ]);

  /// The toolbar's fields and buttons share one height and one frame, so
  /// they always sit on the same line.
  static const double _toolbarH = 44;

  BoxDecoration _toolbarBox({bool error = false}) => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: error ? DsColors.redFg : DsColors.inputBorder,
            width: error ? 1.4 : 1),
      );

  Widget _datePickerField({
    required String label,
    required DateTime? value,
    required ValueChanged<DateTime> onPicked,
    required DateTime first,
    required DateTime last,
    String? help,
    bool required = false,
  }) {
    final missing = required && value == null;
    return SizedBox(
      width: 340,
      child: DsLabeledField(
        label: label,
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: busy
                  ? null
                  : () async {
                      final now = DateTime.now();
                      var initial = value ?? now;
                      if (initial.isBefore(first)) initial = first;
                      if (initial.isAfter(last)) initial = last;
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: first,
                        lastDate: last,
                        helpText: help,
                      );
                      if (picked != null) onPicked(picked);
                    },
              child: Container(
                height: _toolbarH,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: _toolbarBox(error: missing),
                child: Row(children: [
                  Icon(Icons.event_outlined,
                      size: 18,
                      color: missing ? DsColors.redFg : DsColors.icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        value == null
                            ? (missing
                                ? 'Choose a date (required)'
                                : 'Choose a date')
                            : fmtDate(isoDate(value)),
                        style: TextStyle(
                            fontSize: 13.5,
                            color: value == null
                                ? (missing ? DsColors.redFg : DsColors.faint2)
                                : DsColors.heading,
                            fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.arrow_drop_down,
                      size: 20, color: DsColors.icon),
                ]),
              ),
            )),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DATA EXPORT BY SAP
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> get _pos => ((result?['pos'] as List?) ?? const [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();

  bool _selectable(Map<String, dynamic> p) =>
      p['status'] == 'NEW' || p['status'] == 'CHANGED';

  /// Mode of the PO before anything is picked here: the file's for a new PO,
  /// the system's for one already in it.
  String? _baseMode(Map<String, dynamic> p) => p['status'] == 'NEW'
      ? p['shipMode'] as String?
      : (p['existingShipMode'] ?? p['shipMode']) as String?;

  String? _modeOf(Map<String, dynamic> p) =>
      modes.containsKey('${p['poNo']}') ? modes['${p['poNo']}'] : _baseMode(p);

  /// Every PO that is (or will be) in the system — cancelled ones too, the
  /// mode is only a label. Not a row with errors that will not be imported.
  bool _modeEditable(Map<String, dynamic> p) =>
      p['status'] == 'NEW' ||
      p['status'] == 'CHANGED' ||
      p['existingId'] != null;

  Map<String, String> _modePayload() {
    final out = <String, String>{};
    for (final p in _pos) {
      final no = '${p['poNo']}';
      if (!modes.containsKey(no) || !_modeEditable(p)) continue;
      if (p['status'] != 'NEW' && modes[no] == _baseMode(p)) continue;
      out[no] = modes[no] ?? '';
    }
    return out;
  }

  /// POs already in the system whose Mode is the only thing being changed.
  int get _modeOnlyUpdates => _pos
      .where((p) =>
          p['status'] != 'NEW' &&
          p['status'] != 'CHANGED' &&
          p['existingId'] != null &&
          modes.containsKey('${p['poNo']}') &&
          modes['${p['poNo']}'] != _baseMode(p))
      .length;

  List<Map<String, dynamic>> get _chosenNew => _pos
      .where((p) => p['status'] == 'NEW' && chosen.contains('${p['poNo']}'))
      .toList();

  int get _newChosen => _chosenNew.length;

  /// Chosen new POs still without a Delivery date.
  List<String> get _missingDelivery => [
        for (final p in _chosenNew)
          if (deliveries['${p['poNo']}'] == null) '${p['poNo']}'
      ];

  /// The PO's Delivery date is before its PO date.
  bool _badDelivery(Map<String, dynamic> p) {
    final d = deliveries['${p['poNo']}'];
    return p['status'] == 'NEW' &&
        d != null &&
        p['documentDate'] != null &&
        isoDate(d).compareTo('${p['documentDate']}') < 0;
  }

  int get _badChosen => _chosenNew.where(_badDelivery).length;

  String _poCommitLabel() {
    final creates = _newChosen;
    final updates = _pos
        .where(
            (p) => p['status'] == 'CHANGED' && chosen.contains('${p['poNo']}'))
        .length;
    final modeOnly = _modeOnlyUpdates;
    final parts = [
      if (creates > 0) 'Import ${plural(creates, 'PO')}',
      if (updates > 0) 'Update ${plural(updates, 'PO')}',
      if (modeOnly > 0) 'Set mode on ${plural(modeOnly, 'PO')}',
    ];
    return parts.isEmpty ? 'Import' : parts.join(' · ');
  }

  bool get _poCanCommit {
    if (busy) return false;
    if (chosen.isEmpty && _modeOnlyUpdates == 0) return false;
    if (_missingDelivery.isNotEmpty || _badChosen > 0) return false;
    return true;
  }

  Widget _modePicker(Map<String, dynamic> p) {
    final current = _modeOf(p);
    final changed =
        modes.containsKey('${p['poNo']}') && current != _baseMode(p);
    if (!_modeEditable(p)) {
      return Tooltip(
          message:
              'This PO has errors and will not be imported — fix the file first',
          child: ShipModeTag(mode: current));
    }
    return PopupMenuButton<String>(
      tooltip: 'Change the shipping mode',
      onSelected: (v) =>
          setState(() => modes['${p['poNo']}'] = v.isEmpty ? null : v),
      itemBuilder: (_) => [
        for (final m in const ['SEA', 'AIR', 'TRUCK', 'COURIER', ''])
          PopupMenuItem(
              value: m,
              child: Row(children: [
                Icon(m.isEmpty ? Icons.remove : shipModeIcon(m),
                    size: 16, color: DsColors.tealFg),
                const SizedBox(width: 8),
                Text(m.isEmpty ? 'Not set' : shipModeLabel(m)),
              ])),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: changed ? DsColors.blueBg : DsColors.subtle,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: changed
                  ? DsColors.blueFg.withValues(alpha: .4)
                  : DsColors.cardBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: ShipModeTag(mode: current)),
          const Icon(Icons.arrow_drop_down, size: 16, color: DsColors.icon),
        ]),
      ),
    );
  }

  /// The PO date is the earliest day the calendar offers: a Delivery date
  /// cannot be before it. For several POs, the latest of their PO dates.
  DateTime _earliestDelivery(Iterable<Map<String, dynamic>> pos) {
    var first = DateTime(2020);
    for (final p in pos) {
      final d = parseIsoDate(p['documentDate']);
      if (d != null && d.isAfter(first)) first = d;
    }
    return DateTime(first.year, first.month, first.day);
  }

  Future<DateTime?> _pickDelivery(
      {required DateTime first,
      DateTime? current,
      dynamic estimate,
      String? help}) {
    var last = DateTime.now().add(const Duration(days: 365 * 3));
    if (last.isBefore(first)) last = first;
    var initial =
        current ?? _lastDelivery ?? parseIsoDate(estimate) ?? DateTime.now();
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: help,
    );
  }

  /// One date for every selected new PO — the POs of one shipment.
  Widget _bulkDeliveryButton() {
    final targets = _chosenNew;
    final enabled = !busy && targets.isNotEmpty;
    return Tooltip(
      message: targets.isEmpty
          ? 'Select the new POs first'
          : 'Same Delivery date on the ${plural(targets.length, 'selected new PO')} (one shipment)',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: !enabled
              ? null
              : () async {
                  final picked = await _pickDelivery(
                      first: _earliestDelivery(targets),
                      estimate: targets.first['estimatedArrival'],
                      help:
                          'Delivery date of ${plural(targets.length, 'selected PO')}');
                  if (picked == null || !mounted) return;
                  setState(() {
                    _lastDelivery = picked;
                    for (final p in targets) {
                      deliveries['${p['poNo']}'] = picked;
                    }
                  });
                },
          child: Container(
            height: _toolbarH,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: _toolbarBox(),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.event_outlined,
                  size: 17, color: enabled ? DsColors.navy : DsColors.faint2),
              const SizedBox(width: 7),
              Text(
                  targets.isEmpty
                      ? 'Set date for selected POs'
                      : 'Set date for ${plural(targets.length, 'selected PO')}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: enabled ? DsColors.text : DsColors.faint2)),
              const Icon(Icons.arrow_drop_down, size: 18, color: DsColors.icon),
            ]),
          ),
        ),
      ),
    );
  }

  /// The row's own Delivery date. Only a new PO takes one from the import;
  /// a PO already in the system keeps its date (change it on the PO).
  Widget _deliveryCell(Map<String, dynamic> p) {
    final no = '${p['poNo']}';
    if (p['status'] != 'NEW') {
      return const Tooltip(
          message:
              'Not set by this import — change the Delivery date on the PO itself',
          child: Text('—', style: DsType.meta));
    }
    final d = deliveries[no];
    final missing = d == null && chosen.contains(no);
    final bad = _badDelivery(p);
    final fg = bad || missing
        ? DsColors.redFg
        : d == null
            ? DsColors.faint2
            : DsColors.heading;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: busy
            ? null
            : () async {
                final picked = await _pickDelivery(
                    first: _earliestDelivery([p]),
                    current: d,
                    estimate: p['estimatedArrival'],
                    help: 'Delivery date of PO $no');
                if (picked == null || !mounted) return;
                setState(() {
                  _lastDelivery = picked;
                  deliveries[no] = picked;
                  chosen.add(no);
                });
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: bad || missing
                ? DsColors.redBg
                : d == null
                    ? Colors.white
                    : DsColors.subtle,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
                color: bad || missing
                    ? DsColors.redFg.withValues(alpha: .45)
                    : DsColors.cardBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.event_outlined, size: 14, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(d == null ? 'Choose' : fmtDate(isoDate(d)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
            ),
          ]),
        ),
      ),
    );
  }

  /// "30 Jun 2026 · 3 POs" for each Delivery date of the selected new POs —
  /// one date is one shipment.
  Widget _deliveryGroups() {
    final groups = <String, int>{};
    for (final p in _chosenNew) {
      final d = deliveries['${p['poNo']}'];
      if (d != null) groups.update(isoDate(d), (n) => n + 1, ifAbsent: () => 1);
    }
    if (groups.isEmpty) return const SizedBox.shrink();
    final keys = groups.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
                keys.length == 1
                    ? 'One Delivery date:'
                    : '${keys.length} Delivery dates:',
                style: DsType.metaSm),
            for (final k in keys)
              DsTag('${fmtDate(k)} · ${plural(groups[k]!, 'PO')}',
                  color: DsColors.navy, bg: DsColors.subtle),
          ]),
    );
  }

  Widget _bulkModeButton() {
    return PopupMenuButton<String>(
      tooltip: 'Set the same mode on every PO of the file',
      onSelected: (v) => setState(() {
        for (final p in _pos.where(_modeEditable)) {
          modes['${p['poNo']}'] = v.isEmpty ? null : v;
        }
      }),
      itemBuilder: (_) => [
        for (final m in const ['SEA', 'AIR', 'TRUCK', 'COURIER', ''])
          PopupMenuItem(
              value: m,
              child: Row(children: [
                Icon(m.isEmpty ? Icons.remove : shipModeIcon(m),
                    size: 16, color: DsColors.tealFg),
                const SizedBox(width: 8),
                Text(m.isEmpty
                    ? 'Not set — all POs'
                    : '${shipModeLabel(m)} — all POs'),
              ])),
      ],
      child: Container(
        height: _toolbarH,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _toolbarBox(),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.directions_boat_outlined, size: 17, color: DsColors.navy),
          SizedBox(width: 7),
          Text('Set mode for all POs',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: DsColors.text)),
          Icon(Icons.arrow_drop_down, size: 18, color: DsColors.icon),
        ]),
      ),
    );
  }

  _PreviewParts _poParts() {
    final s = Map<String, dynamic>.from(result!['summary'] as Map);
    final pos = _pos;
    final selectablePos = pos.where(_selectable).toList();
    final allChosen = selectablePos.isNotEmpty &&
        selectablePos.every((p) => chosen.contains('${p['poNo']}'));
    final orphans = (s['orphanRows'] as List?) ?? const [];
    return _PreviewParts(
        top: [
          _fileLine(
              'DATA EXPORT BY SAP · sheet "${s['sheetName']}" · ${plural(intFrom(s['lines']) ?? 0, 'line')}'),
          const SizedBox(height: 10),
          Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _visible([
                _stat('POs in file', s['pos'], DsColors.navy, always: true),
                _stat('Ready to import', s['ready'], DsColors.greenFg),
                _stat('With warnings', s['withWarnings'], DsColors.amberFg),
                _stat('Changed in file', s['changed'], DsColors.blueFg),
                _stat('Already in system', s['existing'], DsColors.muted),
                _stat('Errors', s['errors'], DsColors.redFg),
                _stat('New suppliers', s['newSuppliers'], DsColors.blueFg),
                _stat('Materials not in master', s['unmatchedMaterials'],
                    DsColors.amberFg),
              ])),
          if (orphans.isNotEmpty) ...[
            const SizedBox(height: 10),
            InfoStrip(
              icon: Icons.warning_amber_rounded,
              color: DsColors.amberFg,
              text:
                  '${orphans.length} row(s) have no PO number and were ignored (rows ${orphans.take(8).join(', ')}).',
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                DsLabeledField(
                    label: 'Delivery date (step 7 · Factory good received)',
                    child: _bulkDeliveryButton()),
                DsLabeledField(
                    label: 'Shipping mode', child: _bulkModeButton()),
              ]),
          _deliveryGroups(),
          if (_missingDelivery.isNotEmpty) ...[
            const SizedBox(height: 8),
            InfoStrip(
                icon: Icons.event_busy_outlined,
                color: DsColors.redFg,
                text:
                    '${plural(_missingDelivery.length, 'selected PO')} still without a Delivery date (${_missingDelivery.take(5).join(', ')}${_missingDelivery.length > 5 ? '…' : ''}). '
                    'Choose it in the Delivery date column, or set one date for all selected POs. '
                    'It is the due date of "Factory good received" and can be changed on each PO later.'),
          ],
          if (_badChosen > 0) ...[
            const SizedBox(height: 8),
            InfoStrip(
                icon: Icons.error_outline,
                color: DsColors.redFg,
                text:
                    '${plural(_badChosen, 'selected PO')}: the Delivery date is before the PO date.'),
          ],
          if (error != null) ...[
            const SizedBox(height: 10),
            InfoStrip(
                text: error!, icon: Icons.error_outline, color: DsColors.redFg),
          ],
          const SizedBox(height: 12),
        ],
        header: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
              color: DsColors.subtle, borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            SizedBox(
              width: 40,
              child: Checkbox(
                value: allChosen,
                onChanged: selectablePos.isEmpty
                    ? null
                    : (v) => setState(() => v == true
                        ? chosen
                            .addAll(selectablePos.map((p) => '${p['poNo']}'))
                        : chosen.clear()),
              ),
            ),
            for (final h in const [
              ('PO No.', 120.0),
              ('Status', 130.0),
              ('Supplier', null),
              ('PO date', 100.0),
              ('Lines', 50.0),
              ('Mode', 120.0),
              ('Delivery date', 130.0),
              ('First due', 100.0),
              ('Est. by system', 110.0),
              ('', 40.0)
            ])
              h.$2 == null
                  ? Expanded(
                      child: Text(h.$1.toUpperCase(), style: DsType.eyebrow))
                  : SizedBox(
                      width: h.$2,
                      child: h.$1 == 'Est. by system'
                          ? Tooltip(
                              message:
                                  'Worked out by the system from the workflow lead times '
                                  '(N1+10 → N2+20 → N3+15 → N4+5 → +2). '
                                  'Step 7 itself is due on the PO\'s Delivery date.',
                              child: Text(h.$1.toUpperCase(),
                                  style: DsType.eyebrow))
                          : Text(h.$1.toUpperCase(), style: DsType.eyebrow)),
          ]),
        ),
        rows: [for (final p in pos) _poRow(p)],
        bottom: [
          const SizedBox(height: 14),
          Row(children: [
            const Spacer(),
            DsPrimaryButton(
              label: busy ? 'Saving…' : _poCommitLabel(),
              icon: Icons.cloud_upload_outlined,
              height: 42,
              onPressed: _poCanCommit ? commit : null,
            ),
          ]),
        ]);
  }

  Widget _poRow(Map<String, dynamic> p) {
    final no = '${p['poNo']}';
    final status = '${p['status']}';
    final warnings = (p['warnings'] as List).cast<dynamic>();
    final errors = (p['errors'] as List).cast<dynamic>();
    final open = expanded.contains(no);
    final (fg, bg, label) = switch (status) {
      'NEW' => warnings.isEmpty
          ? (DsColors.greenFg, DsColors.greenBg, 'Ready')
          : (DsColors.amberFg, DsColors.amberBg, 'Ready · check'),
      'CHANGED' => (DsColors.blueFg, DsColors.blueBg, 'Changed · update?'),
      'EXISTS' => (DsColors.muted, DsColors.chip, 'Already added'),
      _ => (DsColors.redFg, DsColors.redBg, 'Error'),
    };
    final badDelivery = _badDelivery(p);
    final estimate = p['estimatedArrival'] ?? p['etaDate'];
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
      child: Column(children: [
        Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  setState(() => open ? expanded.remove(no) : expanded.add(no)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  SizedBox(
                    width: 40,
                    child: _selectable(p)
                        ? Checkbox(
                            value: chosen.contains(no),
                            onChanged: (v) => setState(() =>
                                v == true ? chosen.add(no) : chosen.remove(no)),
                          )
                        : null,
                  ),
                  SizedBox(
                      width: 120,
                      child: Text(no,
                          style: mono(size: 12.5, weight: FontWeight.w700))),
                  SizedBox(
                      width: 130,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: DsTag(label, color: fg, bg: bg))),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${p['supplierShort'] ?? p['supplierName'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.rowTitle),
                          Text(
                              '${p['supplierCode'] ?? ''}${p['supplierStatus'] == 'NEW' ? ' · new supplier' : ''}',
                              style: DsType.metaSm),
                        ]),
                  ),
                  SizedBox(
                      width: 100,
                      child:
                          Text(fmtDate(p['documentDate']), style: DsType.meta)),
                  SizedBox(
                      width: 50,
                      child: Text('${p['itemCount']}', style: mono(size: 12))),
                  SizedBox(
                      width: 120,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: _modePicker(p))),
                  SizedBox(
                      width: 130,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: _deliveryCell(p))),
                  SizedBox(
                      width: 100,
                      child:
                          Text(fmtDate(p['nextDueDate']), style: DsType.meta)),
                  SizedBox(
                    width: 110,
                    child: Text(estimate == null ? '—' : fmtDate(estimate),
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: DsColors.navyDeep)),
                  ),
                  SizedBox(
                      width: 40,
                      child: Icon(open ? Icons.expand_less : Icons.expand_more,
                          size: 20, color: DsColors.icon)),
                ]),
              ),
            )),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 12, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (badDelivery)
                    const Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: InfoStrip(
                            text:
                                'The Delivery date is before this PO\'s date.',
                            icon: Icons.error_outline,
                            color: DsColors.redFg)),
                  for (final e in errors)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InfoStrip(
                            text: '$e',
                            icon: Icons.error_outline,
                            color: DsColors.redFg)),
                  for (final w in warnings)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InfoStrip(
                            text: '$w',
                            icon: Icons.warning_amber_rounded,
                            color: DsColors.amberFg)),
                  if (p['changes'] is Map) _changes(p['changes'] as Map),
                  for (final it in (p['items'] as List).cast<Map>())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(
                            width: 44,
                            child: Text('${it['itemNo'] ?? ''}',
                                style: DsType.metaSm)),
                        SizedBox(
                            width: 90,
                            child: Text('${it['materialCode'] ?? '-'}',
                                style: mono(size: 11.5))),
                        Expanded(
                            child: Text('${it['shortText'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DsType.meta)),
                        Expanded(
                            child: Text('${it['vendorMaterial'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DsType.metaSm)),
                        SizedBox(
                            width: 90,
                            child: Text(
                                '${fmtNum(it['orderQty'])} ${it['orderUnit'] ?? ''}',
                                style: DsType.meta)),
                        SizedBox(
                          width: 110,
                          child: it['match'] == 'NONE'
                              ? const DsTag('not in master',
                                  color: DsColors.amberFg, bg: DsColors.amberBg)
                              : Text(
                                  it['match'] == 'CODE_ONLY'
                                      ? 'other supplier\'s master'
                                      : '',
                                  style: DsType.metaSm),
                        ),
                      ]),
                    ),
                ]),
          ),
      ]),
    );
  }

  Widget _changes(Map changes) {
    String v(dynamic x) => x == null || '$x'.isEmpty ? '-' : '$x';
    final po = (changes['po'] as List? ?? const []).cast<Map>();
    final lines = (changes['lines'] as List? ?? const [])
        .cast<Map>()
        .where((l) => l['kind'] != 'MISSING')
        .toList();
    if (po.isEmpty && lines.isEmpty) return const SizedBox.shrink();
    Widget row(String what, String detail) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 150,
                child: Text(what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsType.metaSm)),
            Expanded(child: Text(detail, style: DsType.meta)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DsColors.blueBg.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DsColors.blueFg.withValues(alpha: .2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Different from the system (system → file)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DsColors.blueFg)),
        const SizedBox(height: 6),
        for (final c in po)
          row('${c['label']}', '${v(c['from'])} → ${v(c['to'])}'),
        for (final l in lines)
          row(
            'Line ${l['itemNo'] ?? '-'}${l['materialCode'] == null ? '' : ' · ${l['materialCode']}'}',
            l['kind'] == 'ADDED'
                ? 'New line — will be added'
                : (l['columns'] as List)
                    .cast<Map>()
                    .map((c) =>
                        '${c['header']}: ${v(c['from'])} → ${v(c['to'])}')
                    .join(' · '),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // OCR ACK / OCR SI
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> get _rows =>
      ((result?['rows'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  _PreviewParts _ocrParts() {
    final s = Map<String, dynamic>.from(result!['summary'] as Map);
    final ack = kind == 'ACK';
    final rows = _rows;
    final selectable = rows.where((r) => r['selectable'] == true).toList();
    final allChosen = selectable.isNotEmpty &&
        selectable.every((r) => chosenKeys.contains('${r['key']}'));
    final shipments = ((result!['shipments'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final orphans = (s['orphanRows'] as List?) ?? const [];
    final ready = chosenKeys.length;
    return _PreviewParts(
        top: [
          _fileLine(
              '${s['kindLabel']} · sheet "${s['sheetName']}" · ${plural(intFrom(s['lines']) ?? 0, 'line')}'),
          if (_importKinds[mode] != kind) ...[
            const SizedBox(height: 6),
            InfoStrip(
                icon: Icons.auto_awesome_outlined,
                text: 'This file was recognised as ${s['kindLabel']}.'),
          ],
          const SizedBox(height: 10),
          Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _visible([
                _stat(ack ? 'Shipments (ACK No.)' : 'S/I No.', s['shipments'],
                    DsColors.navy,
                    always: true),
                _stat('POs in file', s['pos'], DsColors.navy, always: true),
                _stat('Ready to move', s['ready'], DsColors.greenFg),
                _stat('New split shipments', s['split'], DsColors.purpleFg),
                _stat('Link ACK No. only', s['link'], DsColors.blueFg),
                _stat('Quantity differences', s['qtyDiffs'], DsColors.amberFg),
                _stat('Already done', s['already'], DsColors.muted),
                _stat('Waiting for OCR ACK', s['notReady'], DsColors.amberFg),
                _stat('Not in system', s['notFound'], DsColors.redFg),
                _stat('Errors', s['errors'], DsColors.redFg),
              ])),
          if (orphans.isNotEmpty) ...[
            const SizedBox(height: 10),
            InfoStrip(
              icon: Icons.warning_amber_rounded,
              color: DsColors.amberFg,
              text:
                  '${orphans.length} row(s) have no PO No. or document No. and were ignored (rows ${orphans.take(8).join(', ')}).',
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
              spacing: 14,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                _datePickerField(
                  label: ack
                      ? 'ACK date (step 2 done on)'
                      : 'S/I date (step 3 done on)',
                  value: actualDate,
                  first: DateTime(2020),
                  last: DateTime.now(),
                  help: ack
                      ? 'When was the ACK received?'
                      : 'When was the S/I received?',
                  onPicked: (d) {
                    setState(() => actualDate = d);
                    unawaited(runPreview());
                  },
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4)),
                  ),
              ]),
          if (error != null) ...[
            const SizedBox(height: 10),
            InfoStrip(
                text: error!, icon: Icons.error_outline, color: DsColors.redFg),
          ],
          const SizedBox(height: 12),
        ],
        header: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
              color: DsColors.subtle, borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            SizedBox(
              width: 40,
              child: Checkbox(
                value: allChosen,
                onChanged: selectable.isEmpty
                    ? null
                    : (v) => setState(() => v == true
                        ? chosenKeys
                            .addAll(selectable.map((r) => '${r['key']}'))
                        : chosenKeys.clear()),
              ),
            ),
            for (final h in [
              ('PO No.', 150.0),
              ('Status', 150.0),
              ('Supplier', null),
              ('Now at', 110.0),
              (ack ? 'ETD (ACK)' : 'ACK No.', 140.0),
              ('Lines', 60.0),
              ('Quantities', 130.0),
              ('', 40.0)
            ])
              h.$2 == null
                  ? Expanded(
                      child: Text(h.$1.toUpperCase(), style: DsType.eyebrow))
                  : SizedBox(
                      width: h.$2,
                      child: Text(h.$1.toUpperCase(), style: DsType.eyebrow)),
          ]),
        ),
        rows: [
          for (final sh in shipments) ...[
            _shipmentHeader(sh, ack),
            for (final r in rows.where((r) => r['docNo'] == sh['docNo']))
              _ocrRow(r, ack),
          ],
        ],
        bottom: [
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(
                  ack
                      ? 'The ticked POs get step 2 done on ${fmtDate(isoDate(actualDate))} with their Acknowledgment No.'
                      : 'The ticked POs get step 3 done on ${fmtDate(isoDate(actualDate))}, with the S/I No., ETD and ETA.',
                  style: DsType.metaSm),
            ),
            DsPrimaryButton(
              label: busy
                  ? 'Saving…'
                  : ready == 0
                      ? 'Update'
                      : 'Update ${plural(ready, 'PO')}',
              icon: Icons.check_circle_outline,
              height: 42,
              onPressed: busy || ready == 0 ? null : commit,
            ),
          ]),
        ]);
  }

  Widget _shipmentHeader(Map<String, dynamic> sh, bool ack) {
    final dates = ack
        ? (sh['etdText'] == null ? '' : 'ETD ${sh['etdText']}')
        : [
            if (sh['etd'] != null) 'ETD ${fmtDate(sh['etd'])}',
            if (sh['eta'] != null) 'ETA ${fmtDate(sh['eta'])}',
          ].join('  ·  ');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: DsColors.navySoft.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(children: [
        Icon(
            ack
                ? Icons.local_shipping_outlined
                : Icons.directions_boat_outlined,
            size: 17,
            color: DsColors.navy),
        const SizedBox(width: 8),
        Text(ack ? 'Shipment · ACK ${sh['docNo']}' : 'S/I ${sh['docNo']}',
            style: mono(
                size: 13, weight: FontWeight.w800, color: DsColors.navyDeep)),
        const SizedBox(width: 10),
        Text(
            '${plural(intFrom(sh['pos']) ?? 0, 'PO')} · ${intFrom(sh['ready']) ?? 0} ready',
            style: DsType.metaSm),
        const Spacer(),
        if (dates.isNotEmpty)
          Text(dates,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: DsColors.navyDeep)),
      ]),
    );
  }

  Widget _ocrRow(Map<String, dynamic> r, bool ack) {
    final key = '${r['key']}';
    final open = expanded.contains(key);
    final warnings = (r['warnings'] as List).cast<dynamic>();
    final errors = (r['errors'] as List).cast<dynamic>();
    final lines = (r['lines'] as List).cast<Map>();
    final (fg, bg, label) = switch ('${r['status']}') {
      'READY' => warnings.isEmpty
          ? (DsColors.greenFg, DsColors.greenBg, 'Ready · move')
          : (DsColors.amberFg, DsColors.amberBg, 'Ready · check'),
      'SPLIT' => (DsColors.purpleFg, DsColors.purpleBg, 'New split shipment'),
      'LINK' => (DsColors.blueFg, DsColors.blueBg, 'Link ACK No.'),
      'ALREADY' => (DsColors.muted, DsColors.chip, 'Already done'),
      'NOT_READY' => (DsColors.amberFg, DsColors.amberBg, 'Waiting for ACK'),
      'NOT_FOUND' => (DsColors.redFg, DsColors.redBg, 'Not in system'),
      _ => (DsColors.redFg, DsColors.redBg, 'Error'),
    };
    final diffs = lines
        .where((l) => ['PARTIAL', 'OVER', 'NOT_ON_PO'].contains(l['state']))
        .length;
    final step = intFrom(r['currentStep']);
    final stepName = step == null
        ? '—'
        : step > kStepCount
            ? 'Done'
            : 'Step $step · ${WorkflowCache.stepOf(step)?['shortName'] ?? ''}';
    final selectable = r['selectable'] == true;
    final splitNo = intFrom(r['splitNo']) ?? 0;
    return Container(
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
      child: Column(children: [
        Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(
                  () => open ? expanded.remove(key) : expanded.add(key)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  SizedBox(
                    width: 40,
                    child: selectable
                        ? Checkbox(
                            value: chosenKeys.contains(key),
                            // An OCR ACK PO split over several
                            // Acknowledgment Nos. is updated all together:
                            // its rows are ticked and unticked as one.
                            onChanged: (v) => setState(() {
                              final keys = ack
                                  ? _rows
                                      .where((x) =>
                                          x['selectable'] == true &&
                                          '${x['poNo']}' == '${r['poNo']}')
                                      .map((x) => '${x['key']}')
                                      .toList()
                                  : [key];
                              v == true
                                  ? chosenKeys.addAll(keys)
                                  : chosenKeys.removeAll(keys);
                            }),
                          )
                        : null,
                  ),
                  SizedBox(
                    width: 150,
                    child: Row(children: [
                      Text('${r['poNo']}',
                          style: mono(size: 12.5, weight: FontWeight.w700)),
                      if (splitNo > 0) ...[
                        const SizedBox(width: 6),
                        Tooltip(
                            message: 'Part shipment #$splitNo of this PO',
                            child: Text('#$splitNo',
                                style: mono(
                                    size: 11,
                                    color: DsColors.purpleFg,
                                    weight: FontWeight.w700))),
                      ],
                    ]),
                  ),
                  SizedBox(
                      width: 150,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: DsTag(label, color: fg, bg: bg))),
                  Expanded(
                      child: Text('${r['supplierName'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.rowTitle)),
                  SizedBox(
                      width: 110,
                      child: Text(stepName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.metaSm)),
                  SizedBox(
                      width: 140,
                      child: Text(
                          ack
                              ? '${r['etdText'] ?? '-'}'
                              : '${r['ackNo'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ack ? DsType.metaSm : mono(size: 11.5))),
                  SizedBox(
                      width: 60,
                      child: Text('${lines.length}', style: mono(size: 12))),
                  SizedBox(
                    width: 130,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: diffs == 0
                          ? (lines.isEmpty || r['status'] == 'NOT_FOUND'
                              ? const Text('—', style: DsType.meta)
                              : const DsTag('match',
                                  color: DsColors.greenFg,
                                  bg: DsColors.greenBg))
                          : DsTag(plural(diffs, 'difference'),
                              color: DsColors.amberFg, bg: DsColors.amberBg),
                    ),
                  ),
                  SizedBox(
                      width: 40,
                      child: Icon(open ? Icons.expand_less : Icons.expand_more,
                          size: 20, color: DsColors.icon)),
                ]),
              ),
            )),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 0, 12, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (r['status'] == 'SPLIT')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: InfoStrip(
                          icon: Icons.call_split,
                          color: DsColors.purpleFg,
                          text:
                              'PO ${r['poNo']} already has its own Acknowledgment No. A copy of the PO (same header, plan and Delivery date) is made for ACK ${r['docNo']}, holding only the lines below, and moved past the ACK step.'),
                    ),
                  for (final e in errors)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InfoStrip(
                            text: '$e',
                            icon: Icons.error_outline,
                            color: DsColors.redFg)),
                  for (final w in warnings)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: InfoStrip(
                            text: '$w',
                            icon: Icons.warning_amber_rounded,
                            color: DsColors.amberFg)),
                  Row(children: [
                    for (final h in [
                      ('Item', 54.0),
                      ('Material', 100.0),
                      ('Description', null),
                      (ack ? 'ACK qty' : 'S/I qty', 90.0),
                      (ack ? 'Order qty' : 'Expected', 90.0),
                      ('', 120.0)
                    ])
                      h.$2 == null
                          ? Expanded(
                              child: Text(h.$1.toUpperCase(),
                                  style: DsType.eyebrow))
                          : SizedBox(
                              width: h.$2,
                              child: Text(h.$1.toUpperCase(),
                                  style: DsType.eyebrow)),
                  ]),
                  const SizedBox(height: 4),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        SizedBox(
                            width: 54,
                            child: Text('${l['poItem'] ?? '-'}',
                                style: DsType.metaSm)),
                        SizedBox(
                            width: 100,
                            child: Text('${l['materialCode'] ?? '-'}',
                                style: mono(size: 11.5))),
                        Expanded(
                            child: Text('${l['description'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: DsType.meta)),
                        SizedBox(
                            width: 90,
                            child: Text(
                                '${fmtNum(l['qty'])} ${l['unit'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: DsColors.heading))),
                        SizedBox(
                            width: 90,
                            child: Text(
                                ack
                                    ? (l['orderQty'] == null
                                        ? '-'
                                        : '${fmtNum(l['orderQty'])}${(l['ackedBefore'] ?? 0) != 0 ? ' (−${fmtNum(l['ackedBefore'])})' : ''}')
                                    : (l['expectedQty'] == null
                                        ? '-'
                                        : fmtNum(l['expectedQty'])),
                                style: DsType.meta)),
                        SizedBox(
                          width: 120,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: switch ('${l['state']}') {
                              'OK' => const DsTag('match',
                                  color: DsColors.greenFg,
                                  bg: DsColors.greenBg),
                              'PARTIAL' => const DsTag('partial',
                                  color: DsColors.amberFg,
                                  bg: DsColors.amberBg),
                              'OVER' => const DsTag('more than open',
                                  color: DsColors.redFg, bg: DsColors.redBg),
                              'NOT_ON_PO' => const DsTag('not on PO',
                                  color: DsColors.redFg, bg: DsColors.redBg),
                              'NO_QTY' => const DsTag('no qty',
                                  color: DsColors.amberFg,
                                  bg: DsColors.amberBg),
                              _ => const SizedBox.shrink(),
                            },
                          ),
                        ),
                      ]),
                    ),
                ]),
          ),
      ]),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _done() {
    final d = done!;
    final k = '${d['kind'] ?? kind}';
    final lines = <String>[];
    String title;
    if (k == 'PO') {
      final created = (d['created'] as List? ?? const []).length;
      final updated = (d['updated'] as List? ?? const []).length;
      title = [
        if (created > 0 || updated == 0) '${plural(created, 'PO')} imported',
        if (updated > 0) '${plural(updated, 'PO')} updated',
      ].join(' · ');
      if ((intFrom(d['suppliersAdded']) ?? 0) > 0) {
        lines.add(
            '${plural(intFrom(d['suppliersAdded'])!, 'new supplier')} added to the master');
      }
      if (created > 0) lines.add('Each new PO now waits for its OCR ACK file.');
    } else {
      final moved = (d['moved'] as List? ?? const []).length;
      final created = (d['created'] as List? ?? const []).length;
      final linked = (d['linked'] as List? ?? const []).length;
      title =
          '${plural(moved + created, 'PO')} moved past ${k == 'ACK' ? 'OCR ACK' : 'OCR S/I'}';
      if (created > 0)
        lines.add('${plural(created, 'split shipment')} created');
      if (linked > 0)
        lines.add('Acknowledgment No. linked on ${plural(linked, 'PO')}');
      lines.add(k == 'ACK'
          ? 'They now wait for the OCR SI file.'
          : 'ETD and ETA are on each PO.');
    }
    if ((intFrom(d['skipped']) ?? 0) > 0) lines.add('${d['skipped']} skipped');
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 10),
      Container(
        width: 70,
        height: 70,
        decoration: const BoxDecoration(
            color: DsColors.greenBg, shape: BoxShape.circle),
        child:
            const Icon(Icons.check_rounded, size: 40, color: DsColors.greenFg),
      ),
      const SizedBox(height: 14),
      Text(title, style: DsType.pageTitle),
      const SizedBox(height: 6),
      Text(lines.join(' · '), textAlign: TextAlign.center, style: DsType.meta),
      const SizedBox(height: 16),
      Wrap(spacing: 10, children: [
        DsOutlineButton(
            label: 'Open Shipments',
            icon: Icons.inventory_2_outlined,
            height: 40,
            onPressed: () => AppScope.read(context).navigate(AppPage.pos)),
        DsPrimaryButton(
            label: 'Import another file',
            icon: Icons.upload_file,
            height: 40,
            onPressed: reset),
      ]),
      const SizedBox(height: 10),
    ]);
  }

  Widget _history() {
    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const DsCardTitle('Recent uploads', icon: Icons.history),
        const SizedBox(height: 10),
        if (history.isEmpty)
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No uploads yet', style: DsType.meta))
        else
          for (final b in history)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
              child: Row(children: [
                SizedBox(
                  width: 120,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DsTag(
                        switch ('${b['kind']}') {
                          'ACK' => 'OCR ACK',
                          'SI' => 'OCR SI',
                          _ => 'DATA EXPORT',
                        },
                        color: DsColors.navy,
                        bg: DsColors.navySoft),
                  ),
                ),
                Expanded(
                    child: Text('${b['fileName'] ?? '-'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsType.rowTitle)),
                SizedBox(
                    width: 220,
                    child: Text(
                        '${b['kind'] == 'PO' || b['kind'] == null ? '${b['created']} new' : [
                            if ((intFrom(b['updated']) ?? 0) > 0 ||
                                (intFrom(b['created']) ?? 0) == 0)
                              '${b['updated']} moved',
                            if ((intFrom(b['created']) ?? 0) > 0)
                              '${b['created']} split'
                          ].join(' · ')}'
                        '${(intFrom(b['kind'] == 'PO' ? b['updated'] : 0) ?? 0) > 0 ? ' · ${b['updated']} updated' : ''}',
                        style: DsType.meta)),
                SizedBox(
                    width: 170,
                    child: Text(
                        '${b['uploadedBy'] ?? '-'} · ${fmtDateTime(b['createdAt'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DsType.metaSm)),
                SizedBox(
                  width: 36,
                  child: b['hasFile'] == true
                      ? IconButton(
                          tooltip: 'Download the file',
                          icon: const Icon(Icons.download,
                              size: 18, color: DsColors.icon),
                          onPressed: () async {
                            try {
                              final bytes = await AppScope.read(context)
                                  .api
                                  .getBytes(
                                      '/pos/import/batches/${b['id']}/file');
                              saveBytes(
                                  bytes, '${b['fileName'] ?? 'import.xlsx'}');
                            } catch (_) {
                              if (mounted)
                                AppToast.error(
                                    context, 'Could not download the file');
                            }
                          },
                        )
                      : null,
                ),
              ]),
            ),
      ]),
    );
  }
}

/// The parts of a preview: what sits above the table, the table's header row
/// (pinned while scrolling), its rows, and what follows it.
class _PreviewParts {
  const _PreviewParts(
      {required this.top,
      required this.header,
      required this.rows,
      required this.bottom});
  final List<Widget> top;
  final Widget header;
  final List<Widget> rows;
  final List<Widget> bottom;
}

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader({required this.height, required this.builder});
  final double height;
  final Widget Function(bool pinned) builder;

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox(
          height: height, child: builder(overlapsContent || shrinkOffset > 0));

  @override
  bool shouldRebuild(covariant _PinnedHeader old) => true;
}
