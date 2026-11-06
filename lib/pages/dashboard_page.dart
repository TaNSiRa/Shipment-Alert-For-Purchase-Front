part of '../main.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? data;
  String? error;
  int _tick = -1;

  // Cards with their own pickers keep their own data, reloaded alone.
  int? trendYear;
  List<Map>? trend;
  int? modesYear;
  List<Map>? modesByMonth;
  bool supplierByMonth = false;
  int? supplierYear;
  int supplierMonth = DateTime.now().month;
  bool supplierByMaterial = false;
  List<Map>? suppliers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).refreshTick;
    if (tick != _tick) {
      _tick = tick;
      unawaited(load());
    }
  }

  Future<void> load() async {
    try {
      final r = await AppScope.read(context).api.getJson('/reports/dashboard');
      if (mounted) {
        setState(() {
          data = r;
          error = null;
          trendYear ??= intFrom(r['trendYear']);
          modesYear ??= intFrom(r['modesYear']);
          supplierYear ??= intFrom('${r['supplierPeriod'] ?? ''}'.split('-').first);
        });
        // A refresh keeps the year / period each card is showing.
        if (trendYear == intFrom(r['trendYear'])) {
          setState(() => trend = (r['trend'] as List).cast<Map>());
        } else {
          unawaited(loadTrend(trendYear!));
        }
        if (modesYear == intFrom(r['modesYear'])) {
          setState(() => modesByMonth = (r['modesByMonth'] as List).cast<Map>());
        } else {
          unawaited(loadModes(modesYear!));
        }
        if (!supplierByMonth && '$supplierYear' == '${r['supplierPeriod']}') {
          setState(() => suppliers = (r['bySupplier'] as List).cast<Map>());
        } else {
          unawaited(loadSuppliers());
        }
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = friendlyError(e.message));
    }
  }

  Future<void> loadTrend(int year) async {
    setState(() => trendYear = year);
    try {
      final r = await AppScope.read(context).api.getJson('/reports/dashboard/trend?year=$year');
      if (mounted && trendYear == year) setState(() => trend = (r['trend'] as List).cast<Map>());
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e.message));
    }
  }

  Future<void> loadModes(int year) async {
    setState(() => modesYear = year);
    try {
      final r = await AppScope.read(context).api.getJson('/reports/dashboard/modes?year=$year');
      if (mounted && modesYear == year) setState(() => modesByMonth = (r['months'] as List).cast<Map>());
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e.message));
    }
  }

  String get _supplierPeriod {
    final y = supplierYear ?? DateTime.now().year;
    return supplierByMonth ? '$y-${'$supplierMonth'.padLeft(2, '0')}' : '$y';
  }

  Future<void> loadSuppliers() async {
    final period = _supplierPeriod;
    try {
      final r = await AppScope.read(context).api.getJson('/reports/dashboard/suppliers?period=$period');
      if (mounted && _supplierPeriod == period) setState(() => suppliers = (r['suppliers'] as List).cast<Map>());
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e.message));
    }
  }

  /// The years one card has data for (newest first), as the server lists
  /// them: 'trend', 'modes' or 'suppliers'. Never empty.
  List<int> _years(String card) {
    final all = data?['years'];
    final list = all is Map ? (all[card] as List? ?? const []) : const [];
    final ys = list.map((e) => intFrom(e) ?? 0).where((y) => y > 0).toList();
    return ys.isEmpty ? [DateTime.now().year] : ys;
  }

  /// A compact "2026 ▾" picker for a card's title row.
  Widget _yearPicker(String card, int? value, ValueChanged<int> onPick) {
    return PopupMenuButton<int>(
      tooltip: 'Choose the year',
      onSelected: onPick,
      itemBuilder: (_) => [for (final y in _years(card)) PopupMenuItem(value: y, child: Text('$y'))],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: DsColors.subtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: DsColors.cardBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.calendar_today_outlined, size: 14, color: DsColors.navy),
          const SizedBox(width: 6),
          Text('${value ?? DateTime.now().year}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: DsColors.heading)),
          const Icon(Icons.arrow_drop_down, size: 18, color: DsColors.icon),
        ]),
      ),
    );
  }

  Widget _segment(List<String> labels, int selected, ValueChanged<int> onSelect) {
    return DsSegmented(
      selected: selected,
      length: labels.length,
      itemBuilder: (context, i, t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        child: Text(labels[i],
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color.lerp(DsColors.muted, DsColors.navyDeep, t))),
      ),
      onSelect: onSelect,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && data == null) {
      return PageBody(children: [ErrorPanel(message: error!, onRetry: load)]);
    }
    final scope = AppScope.of(context);
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1500
        ? 3
        : width >= 1150
            ? 2
            : 1;
    if (data == null) return _skeleton(scope, cols);
    final d = data!;
    final counts = Map<String, dynamic>.from(d['counts'] as Map);
    return PageBody(children: [
      DsRise(child: _hero(scope, counts)),
      const SizedBox(height: 16),
      DsRise(
          index: 2, child: _pipeline(scope, (d['byStep'] as List).cast<Map>())),
      const SizedBox(height: 16),
      DsRise(
        index: 3,
        child: _grid(cols, [
          _poList('Overdue — follow up first', Icons.warning_amber_rounded,
              DsColors.redFg, (d['overdueList'] as List).cast<Map>(),
              empty: 'Nothing overdue 🎉',
              onAll: () =>
                  scope.navigate(AppPage.pos, args: {'due': 'OVERDUE'})),
          _poList('Due soon', Icons.schedule, DsColors.amberFg,
              (d['dueSoonList'] as List).cast<Map>(),
              empty: 'Nothing due in the next days',
              onAll: () => scope.navigate(AppPage.pos, args: {'due': 'SOON'})),
          _poList('Next arrivals at the factory', Icons.warehouse_outlined,
              DsColors.tealFg, (d['arrivals'] as List).cast<Map>(),
              empty: 'No arrivals expected',
              eta: true,
              onAll: () => scope.navigate(AppPage.pos, args: {'sort': 'eta'})),
        ]),
      ),
      const SizedBox(height: 16),
      DsRise(index: 4, child: _trend(trend)),
      const SizedBox(height: 16),
      DsRise(index: 5, child: _modes(modesByMonth)),
      const SizedBox(height: 16),
      DsRise(index: 6, child: _suppliers(scope, suppliers)),
    ]);
  }

  /// The dashboard before its numbers arrive: every card in its place with its
  /// real title, and a ghost of its own content inside — tiles in the
  /// pipeline, rows in the lists, bars in the chart, a ring for the donut.
  Widget _skeleton(AppScope scope, int cols) {
    return PageBody(children: [
      _hero(scope, null),
      const SizedBox(height: 16),
      _pipeline(scope, null),
      const SizedBox(height: 16),
      _grid(cols, [
        _poList('Overdue — follow up first', Icons.warning_amber_rounded,
            DsColors.redFg, null,
            empty: '',
            onAll: () => scope.navigate(AppPage.pos, args: {'due': 'OVERDUE'})),
        _poList('Due soon', Icons.schedule, DsColors.amberFg, null,
            empty: '',
            onAll: () => scope.navigate(AppPage.pos, args: {'due': 'SOON'})),
        _poList('Next arrivals at the factory', Icons.warehouse_outlined,
            DsColors.tealFg, null,
            empty: '',
            eta: true,
            onAll: () => scope.navigate(AppPage.pos, args: {'sort': 'eta'})),
      ]),
      const SizedBox(height: 16),
      _trend(null),
      const SizedBox(height: 16),
      _modes(null),
      const SizedBox(height: 16),
      _suppliers(scope, null),
    ]);
  }

  Widget _grid(int cols, List<Widget> children) {
    if (cols == 1) {
      return Column(children: [
        for (final c in children) ...[c, const SizedBox(height: 16)],
      ]);
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, min(i + cols, children.length));
      // Every card in a row as tall as the tallest one, whatever it holds —
      // an empty list keeps its full card instead of shrinking to its title.
      rows.add(_EqualHeightRow(gap: 16, children: [
        ...slice,
        for (var k = slice.length; k < cols; k++) const SizedBox(),
      ]));
      rows.add(const SizedBox(height: 16));
    }
    return Column(children: rows);
  }

  Widget _hero(AppScope scope, Map<String, dynamic>? c) {
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final overdue = intFrom(c?['overdue']) ?? 0;
    // Ghost text on the navy: a tint of the white ink, not the page grey.
    final ghost = Colors.white.withValues(alpha: .22);
    final radius = BorderRadius.circular(Lg.on ? Lg.r(18) : 18);
    // RAP's hero: deep navy falling darker to the bottom right, with a violet
    // glow sitting in the top-right corner.
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: .07)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff232a4e), Color(0xff191e39), Color(0xff11152b)],
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x3311152b), blurRadius: 24, offset: Offset(0, 10))
        ],
      ),
      // Violet glows spread across the navy and a scatter of small purple
      // dots (the login page's sky), so the card reads as RAP's deep violet
      // rather than near-black. Painted behind the content, clipped to the card.
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(children: [
          for (final g in _heroGlows)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: g.$1,
                    radius: g.$2,
                    colors: [g.$3, g.$3.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          const Positioned.fill(child: _HeroDots()),
          Padding(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$greet, ${scope.me['displayName'] ?? ''}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (c == null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: DsSkel.line(300, height: 12, color: ghost),
                ),
                const SizedBox(height: 6),
                DsSkel.line(190, height: 10, color: ghost),
              ] else ...[
                Text(
                  overdue > 0
                      ? '${plural(intFrom(c['active']) ?? 0, 'PO')} open · $overdue need follow-up today.'
                      : '${plural(intFrom(c['active']) ?? 0, 'PO')} open · everything is on track.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: .9),
                      fontSize: 13.5),
                ),
                const SizedBox(height: 4),
                Text(
                    'Today ${fmtDate(data!['today'])} · ${scope.section['name']}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                        fontSize: 12)),
              ],
            ]),
          ),
          if (scope.canEdit) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: DsColors.navyDeep),
              onPressed: () => scope.navigate(AppPage.imports),
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Import'),
            ),
            const SizedBox(width: 10),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0x88ffffff))),
            onPressed: () => scope.navigate(AppPage.pos),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('All shipments'),
          ),
        ]),
          ),
        ]),
      ),
    );
  }

  // (centre, radius as a fraction of the card's height, colour)
  static const _heroGlows = <(Alignment, double, Color)>[
    (Alignment(.75, -1.1), 1.6, Color(0xa06a64e0)),
    (Alignment(-.95, 1.35), 1.5, Color(0x907c3aed)),
    (Alignment(-.25, -1.25), 1.1, Color(0x705b5bd6)),
    (Alignment(.2, 1.45), 1.2, Color(0x80a855f7)),
    (Alignment(1.05, .95), 1.3, Color(0x809333ea)),
    (Alignment(-.55, .1), .9, Color(0x406d28d9)),
  ];

  Widget _pipeline(AppScope scope, List<Map>? steps) {
    final total = (steps ?? const [])
        .fold<int>(0, (a, s) => a + (intFrom(s['count']) ?? 0));
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle('Shipment pipeline — where the open shipments are waiting',
            icon: Icons.route_outlined,
            trailing: TextButton(
                onPressed: () => scope.navigate(AppPage.roadmap),
                child: const Text('Open road map'))),
        const SizedBox(height: 14),
        if (steps != null)
          // The RAP request-timeline board: each step a disc floating over a
          // raised rail, its open-PO count above it. Too narrow → tile row.
          Board3dRail(
            minCellPx: 120,
            maxPerRow: 8,
            minWidth: 560,
            stages: [
              for (var i = 0; i < steps.length; i++)
                _pipeStage(
                    scope, Map<String, dynamic>.from(steps[i]), i, total),
            ],
            fallback: (_) => _pipeRow(scope, steps, total),
          )
        else
          _pipeRow(scope, null, total),
      ]),
    );
  }

  Board3dStage _pipeStage(
      AppScope scope, Map<String, dynamic> s, int i, int total) {
    final count = intFrom(s['count']) ?? 0;
    final overdue = intFrom(s['overdue']) ?? 0;
    final soon = intFrom(s['dueSoon']) ?? 0;
    return Board3dStage(
      title: '${s['shortName']}',
      icon: stepIcon(s['icon']),
      accent: overdue > 0
          ? DsColors.redFg
          : board3dPalette[i % board3dPalette.length],
      number: '${s['stepNo']}',
      top: plural(count, 'shipment'),
      pills: [
        if (overdue > 0) ('$overdue OVERDUE', DsColors.redFg),
        if (overdue == 0 && soon > 0) ('$soon DUE SOON', DsColors.amberFg),
      ],
      lines: [
        if (count > 0 && total > 0)
          '${(count * 100 / total).round()}% · ${plural(intFrom(s['poCount']) ?? 0, 'PO')}'
        else
          'nothing waiting',
      ],
      muted: count == 0,
      glow: overdue > 0,
      onTap: count == 0
          ? null
          : () => scope.navigate(AppPage.pos, args: {'step': s['stepNo']}),
    );
  }

  /// The flat tile row: the loading ghost, and narrow screens.
  Widget _pipeRow(AppScope scope, List<Map>? steps, int total) {
    final n = steps?.length ?? kStepCount;
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < n; i++) ...[
                  steps == null
                      ? _pipeStepGhost(i)
                      : _pipeStep(
                          scope, Map<String, dynamic>.from(steps[i]), total),
                  if (i < n - 1)
                    const Padding(
                      padding: EdgeInsets.only(top: 34),
                      child: Icon(Icons.chevron_right,
                          size: 18, color: DsColors.iconSoft),
                    ),
                ],
              ]),
        ),
      ),
    );
  }

  Widget _pipeStep(AppScope scope, Map<String, dynamic> s, int total) {
    final count = intFrom(s['count']) ?? 0;
    final overdue = intFrom(s['overdue']) ?? 0;
    final soon = intFrom(s['dueSoon']) ?? 0;
    final color = overdue > 0
        ? DsColors.redFg
        : count > 0
            ? DsColors.navy
            : DsColors.faint2;
    return SizedBox(
      width: 118,
      child: DsHoverLift(
        onTap: count == 0
            ? null
            : () => scope.navigate(AppPage.pos, args: {'step': s['stepNo']}),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: count > 0 ? DsColors.subtle : DsColors.subtleAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: overdue > 0 ? DsColors.redBg : DsColors.cardBorder,
                width: overdue > 0 ? 1.6 : 1),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(stepIcon(s['icon']), size: 16, color: color),
              const Spacer(),
              Text('${s['stepNo']}',
                  style: mono(
                      size: 10.5,
                      color: DsColors.faint2,
                      weight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text('$count',
                style: DsType.stat(24,
                    color: count == 0 ? DsColors.faint2 : DsColors.heading)),
            const SizedBox(height: 2),
            SizedBox(
              height: 30,
              child: Text('${s['shortName']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DsType.label),
            ),
            const SizedBox(height: 6),
            DsProgressBar(
                value: total == 0 ? 0 : count / total, color: color, height: 4),
            const SizedBox(height: 6),
            Text(
              overdue > 0
                  ? '$overdue overdue'
                  : soon > 0
                      ? '$soon due soon'
                      : count > 0
                          ? 'on track'
                          : '—',
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: overdue > 0
                      ? DsColors.redFg
                      : soon > 0
                          ? DsColors.amberFg
                          : DsColors.faint2),
            ),
          ]),
        ),
      ),
    );
  }

  /// [_pipeStep]'s tile, ghosted: icon and number, the count, the two-line
  /// name, the bar and its status line.
  Widget _pipeStepGhost(int i) {
    return Container(
      width: 118,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DsColors.subtleAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DsColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          DsSkel.icon(16),
          const Spacer(),
          DsSkel.line(8, height: 9),
        ]),
        const SizedBox(height: 10),
        DsSkel.box(DsSkel.vary(i, 30, .5), 22, radius: 6),
        const SizedBox(height: 6),
        SizedBox(
          height: 26,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DsSkel.line(DsSkel.vary(i + 2, 78), height: 9),
            const SizedBox(height: 6),
            if (i.isEven) DsSkel.line(DsSkel.vary(i + 5, 44), height: 9),
          ]),
        ),
        const SizedBox(height: 6),
        DsSkel.fill(4, radius: 2),
        const SizedBox(height: 8),
        DsSkel.line(DsSkel.vary(i + 1, 50), height: 8),
      ]),
    );
  }

  /// How many POs each dashboard list shows; "See all" opens the rest.
  static const _listLimit = 5;

  Widget _poList(String title, IconData icon, Color color, List<Map>? all,
      {required String empty, required VoidCallback onAll, bool eta = false}) {
    final scope = AppScope.of(context);
    final items = (all ?? const []).take(_listLimit).toList();
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: DsType.cardTitle)),
          TextButton(onPressed: onAll, child: const Text('See all')),
        ]),
        const SizedBox(height: 8),
        if (all == null)
          for (var i = 0; i < _listLimit; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
              child: Row(children: [
                DsSkel.circle(9),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: DsSkel.lines(
                        DsSkel.vary(i, 170), DsSkel.vary(i + 4, 120),
                        titleH: 12),
                  ),
                ),
                const SizedBox(width: 8),
                eta
                    ? DsSkel.lines(42, DsSkel.vary(i + 1, 54),
                        align: CrossAxisAlignment.end, titleH: 12)
                    : DsSkel.chip(DsSkel.vary(i + 2, 66, .3)),
              ]),
            )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Center(child: Text(empty, style: DsType.meta)),
          )
        else
          for (final raw in items)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => unawaited(scope.openPo(intFrom(raw['id'])!)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Row(children: [
                  DueDot(state: '${raw['dueState']}'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${raw['poNo']} · ${raw['supplierShort'] ?? raw['supplierName'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.rowTitle),
                          Text(
                              eta
                                  ? 'Step ${raw['currentStep']} · ${raw['currentStepShort']}'
                                  : '${raw['currentStepName']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.metaSm),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  eta
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                              Text(fmtDateShort(raw['etaDate']),
                                  style: DsType.rowTitle),
                              Text(_inDays(raw['etaDate']),
                                  style: DsType.metaSm),
                            ])
                      : DueChip(
                          po: Map<String, dynamic>.from(raw), dense: true),
                ]),
              ),
            ),
      ]),
    );
  }

  String _inDays(dynamic iso) {
    final d = parseIsoDate(iso);
    if (d == null) return '';
    final n = d.difference(DateTime.parse(todayIso())).inDays;
    return n == 0
        ? 'today'
        : n == 1
            ? 'tomorrow'
            : 'in $n days';
  }

  Widget _trend(List<Map>? trend) {
    final year = trendYear ?? DateTime.now().year;
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle('Planned vs arrived by month — $year',
            icon: Icons.bar_chart,
            trailing: _yearPicker('trend', trendYear, (y) => unawaited(loadTrend(y)))),
        const SizedBox(height: 12),
        if (trend == null)
          _trendGhost()
        else if (trend.every((t) =>
            (intFrom(t['planned']) ?? 0) == 0 &&
            (intFrom(t['plannedOnTime']) ?? 0) == 0 &&
            (intFrom(t['plannedLate']) ?? 0) == 0))
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Nothing planned or arrived in this year', style: DsType.meta))
        else
          // Per month, one set of POs: those PLANNED to reach the factory that
          // month (left, step 7's Delivery date) and how many of them have
          // arrived (right), on time or late. The empty height between the two
          // is what has not arrived yet.
          ExtrudedBarChart(
            key: ValueKey('trend-${trend.first['month']}'),
            height: 240,
            labels: [
              for (final t in trend)
                intl.DateFormat('MMM').format(DateTime.parse('${t['month']}-01'))
            ],
            tooltipTitles: [
              for (final t in trend)
                intl.DateFormat('MMM yyyy').format(DateTime.parse('${t['month']}-01'))
            ],
            currentIndex: year == DateTime.now().year ? DateTime.now().month - 1 : null,
            series: [
              BarSeries('Planned', [
                BarSegment('Planned to arrive', DsColors.navy,
                    [for (final t in trend) intFrom(t['planned']) ?? 0]),
              ], notes: [
                (
                  'Arrived',
                  [
                    for (final t in trend)
                      (intFrom(t['plannedOnTime']) ?? 0) + (intFrom(t['plannedLate']) ?? 0)
                  ]
                ),
                (
                  'Still waiting',
                  [
                    for (final t in trend)
                      max(
                          0,
                          (intFrom(t['planned']) ?? 0) -
                              (intFrom(t['plannedOnTime']) ?? 0) -
                              (intFrom(t['plannedLate']) ?? 0))
                  ]
                ),
              ]),
              BarSeries('Arrived', [
                BarSegment('Arrived on time', DsColors.greenDot,
                    [for (final t in trend) intFrom(t['plannedOnTime']) ?? 0]),
                BarSegment('Arrived late', const Color(0xffe08a80),
                    [for (final t in trend) intFrom(t['plannedLate']) ?? 0]),
              ], notes: [
                ('Planned', [for (final t in trend) intFrom(t['planned']) ?? 0]),
              ]),
            ],
          ),
      ]),
    );
  }

  /// [ExtrudedBarChart], ghosted: its legend, twelve month groups of a
  /// planned and an arrived bar on the baseline, and the month labels.
  Widget _trendGhost({bool single = false}) {
    const planned = <double>[96, 128, 84, 146, 112, 152, 120, 90, 134, 104, 142, 116];
    const arrived = [.82, .7, .9, .64, .5, .28, .6, .75, .4, .55, .3, .2];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 4, children: [
        for (final w in const <double>[104, 88, 76])
          Row(mainAxisSize: MainAxisSize.min, children: [
            DsSkel.box(10, 10, radius: 3),
            const SizedBox(width: 6),
            DsSkel.line(w, height: 9),
          ]),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: 240,
        child: Column(children: [
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var g = 0; g < planned.length; g++)
                Expanded(
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DsSkel.box(18, planned[g], radius: 4),
                        if (!single) ...[
                          const SizedBox(width: 6),
                          DsSkel.box(18, planned[g] * arrived[g], radius: 4),
                        ],
                      ]),
                ),
            ]),
          ),
          Container(height: 1, color: DsColors.line),
          const SizedBox(height: 9),
          Row(children: [
            for (var g = 0; g < planned.length; g++)
              Expanded(child: Center(child: DsSkel.line(24, height: 9))),
          ]),
        ]),
      ),
    ]);
  }

  static const _modeColors = <String, Color>{
    'SEA': DsColors.blueFg,
    'AIR': DsColors.purpleFg,
    'COURIER': DsColors.tealFg,
    'TRUCK': DsColors.amberFg,
    'UNKNOWN': DsColors.faint2,
  };

  Widget _modes(List<Map>? months) {
    final year = modesYear ?? DateTime.now().year;
    final hasUnknown = (months ?? const []).any((m) => (intFrom(m['UNKNOWN']) ?? 0) > 0);
    final empty = months != null &&
        months.every((m) => _modeColors.keys.every((k) => (intFrom(m[k]) ?? 0) == 0));
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle('Shipments by mode — $year',
            icon: Icons.directions_boat_outlined,
            trailing: _yearPicker('modes', modesYear, (y) => unawaited(loadModes(y)))),
        const SizedBox(height: 4),
        const Text('Shipments (Acknowledgment No.) arriving each month — step 7 date — by shipping mode',
            style: DsType.metaSm),
        const SizedBox(height: 10),
        if (months == null)
          _trendGhost(single: true)
        else if (empty)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No shipments arriving in this year', style: DsType.meta))
        else
          ExtrudedBarChart(
            key: ValueKey('modes-${months.first['month']}'),
            height: 240,
            labels: [
              for (final m in months)
                intl.DateFormat('MMM').format(DateTime.parse('${m['month']}-01'))
            ],
            tooltipTitles: [
              for (final m in months)
                intl.DateFormat('MMM yyyy').format(DateTime.parse('${m['month']}-01'))
            ],
            currentIndex: year == DateTime.now().year ? DateTime.now().month - 1 : null,
            series: [
              BarSeries('Shipments', [
                for (final k in const ['SEA', 'AIR', 'COURIER', 'TRUCK', 'UNKNOWN'])
                  if (k != 'UNKNOWN' || hasUnknown)
                    BarSegment(k == 'UNKNOWN' ? 'Not set' : shipModeLabel(k), _modeColors[k]!,
                        [for (final m in months) intFrom(m[k]) ?? 0]),
              ]),
            ],
          ),
      ]),
    );
  }

  Widget _suppliers(AppScope scope, List<Map>? suppliers) {
    final key = supplierByMaterial ? 'materials' : 'count';
    final list = [...(suppliers ?? const <Map>[])]
      ..sort((a, b) => (intFrom(b[key]) ?? 0).compareTo(intFrom(a[key]) ?? 0));
    final top = list.take(12).toList();
    final peak = top.fold<int>(0, (a, s) => max(a, intFrom(s[key]) ?? 0));
    final monthNames = [for (var m = 1; m <= 12; m++) intl.DateFormat('MMMM').format(DateTime(2000, m))];
    final period = supplierByMonth
        ? '${monthNames[supplierMonth - 1]} ${supplierYear ?? DateTime.now().year}'
        : '${supplierYear ?? DateTime.now().year}';
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle(
            supplierByMaterial ? 'Materials ordered by supplier — $period' : 'POs by supplier — $period',
            icon: Icons.storefront_outlined),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _segment(const ['By PO', 'By material'], supplierByMaterial ? 1 : 0,
              (i) => setState(() => supplierByMaterial = i == 1)),
          _segment(const ['Year', 'Month'], supplierByMonth ? 1 : 0, (i) {
            setState(() => supplierByMonth = i == 1);
            unawaited(loadSuppliers());
          }),
          _yearPicker('suppliers', supplierYear, (y) {
            setState(() => supplierYear = y);
            unawaited(loadSuppliers());
          }),
          if (supplierByMonth)
            PopupMenuButton<int>(
              tooltip: 'Choose the month',
              onSelected: (m) {
                setState(() => supplierMonth = m);
                unawaited(loadSuppliers());
              },
              itemBuilder: (_) => [
                for (var m = 1; m <= 12; m++) PopupMenuItem(value: m, child: Text(monthNames[m - 1]))
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: DsColors.subtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DsColors.cardBorder),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(monthNames[supplierMonth - 1],
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: DsColors.heading)),
                  const Icon(Icons.arrow_drop_down, size: 18, color: DsColors.icon),
                ]),
              ),
            ),
          Text(
              supplierByMaterial
                  ? 'Material lines on POs dated in the period (a split PO counts once)'
                  : 'POs dated in the period, open or done (cancelled left out)',
              style: DsType.metaSm),
        ]),
        const SizedBox(height: 12),
        if (suppliers == null)
          // [HBar], ghosted: name, the track with its bar, the count.
          for (var i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              child: Row(children: [
                SizedBox(
                    width: 120,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: DsSkel.line(DsSkel.vary(i, 84), height: 10))),
                Expanded(
                  child: Stack(children: [
                    Container(
                        height: 12,
                        decoration: BoxDecoration(
                            color: DsColors.track, borderRadius: BorderRadius.circular(6))),
                    FractionallySizedBox(
                        widthFactor: const [.92, .74, .58, .45, .33, .2][i],
                        child: DsSkel.fill(12, radius: 6)),
                  ]),
                ),
                const SizedBox(width: 10),
                SizedBox(
                    width: 30,
                    child: Align(
                        alignment: Alignment.centerRight, child: DsSkel.line(14, height: 10))),
              ]),
            )
        else if (top.isEmpty)
          Padding(
              padding: const EdgeInsets.all(20),
              child: Text('No POs in $period', style: DsType.meta)),
        for (final s in top)
          HBar(
            label: '${s['name']}',
            value: intFrom(s[key]) ?? 0,
            max: peak,
            color: (intFrom(s['overdue']) ?? 0) > 0
                ? DsColors.redFg.withValues(alpha: .75)
                : supplierByMaterial
                    ? DsColors.tealFg
                    : DsColors.navy,
            extra: (intFrom(s['overdue']) ?? 0) > 0
                ? Tooltip(
                    message: 'POs overdue',
                    child: DsTag('${s['overdue']}', color: DsColors.redFg, bg: DsColors.redBg))
                : null,
            onTap: () => scope.navigate(AppPage.pos, args: {'q': s['supplierCode'] ?? s['name']}),
          ),
      ]),
    );
  }
}

/// A row of equal-width children that are all as tall as the tallest.
///
/// IntrinsicHeight cannot do this here: the chart cards measure themselves
/// with a LayoutBuilder, which cannot report an intrinsic size. This lays each
/// child out once to find the tallest, then again at exactly that height.
class _EqualHeightRow extends MultiChildRenderObjectWidget {
  const _EqualHeightRow({required this.gap, required super.children});
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderEqualHeightRow(gap);

  @override
  void updateRenderObject(
      BuildContext context, _RenderEqualHeightRow renderObject) {
    renderObject.gap = gap;
  }
}

class _EqualHeightParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEqualHeightRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EqualHeightParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EqualHeightParentData> {
  _RenderEqualHeightRow(this._gap);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EqualHeightParentData)
      child.parentData = _EqualHeightParentData();
  }

  @override
  void performLayout() {
    final n = childCount;
    if (n == 0) {
      size = constraints.smallest;
      return;
    }
    final width = (constraints.maxWidth - _gap * (n - 1)) / n;
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints(minWidth: width, maxWidth: width),
          parentUsesSize: true);
      height = max(height, child.size.height);
      child = childAfter(child);
    }
    var x = 0.0;
    child = firstChild;
    while (child != null) {
      child.layout(BoxConstraints.tightFor(width: width, height: height));
      (child.parentData! as _EqualHeightParentData).offset = Offset(x, 0);
      x += width + _gap;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(constraints.maxWidth, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// The hero card's small purple dots, drifting. Each dot wanders slowly
/// around its home position on its own small loop and twinkles on its own
/// beat, so the field never moves in step. One controller, one repaint of a
/// layer of its own (RepaintBoundary) — the card's text is never redrawn for
/// it. Still when the system asks for reduced motion.
class _HeroDots extends StatefulWidget {
  const _HeroDots();

  @override
  State<_HeroDots> createState() => _HeroDotsState();
}

class _HeroDotsState extends State<_HeroDots> with SingleTickerProviderStateMixin {
  // One full loop; every dot's speed is a whole multiple of it, so the end of
  // the loop lands exactly where it began and the repeat has no visible jump.
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _HeroDotsPainter(_clock)),
    );
  }
}

class _HeroDotsPainter extends CustomPainter {
  _HeroDotsPainter(this.clock) : super(repaint: clock);
  final Animation<double> clock;

  // x, y (0..1 of the card), radius, brightness, then the motion: loop size
  // in px, loops per minute on x and on y, phase, twinkle speed.
  static final List<List<double>> _dots = () {
    final r = Random(7);
    return [
      for (var i = 0; i < 46; i++)
        [
          r.nextDouble(),
          r.nextDouble(),
          1.0 + r.nextDouble() * 2.2,
          .25 + r.nextDouble() * .5,
          6 + r.nextDouble() * 14,
          (1 + r.nextInt(3)).toDouble(),
          (1 + r.nextInt(3)).toDouble(),
          r.nextDouble() * 2 * pi,
          (2 + r.nextInt(5)).toDouble(),
        ],
    ];
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value * 2 * pi;
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final core = Paint();
    for (final d in _dots) {
      final c = Offset(
        d[0] * size.width + d[4] * sin(t * d[5] + d[7]),
        d[1] * size.height + d[4] * .6 * cos(t * d[6] + d[7]),
      );
      // Twinkle between 45 % and 100 % of the dot's own brightness.
      final a = d[3] * (.725 + .275 * sin(t * d[8] + d[7] * 2));
      glow.color = const Color(0xffa78bfa).withValues(alpha: a * .35);
      core.color = const Color(0xffc4b5fd).withValues(alpha: a);
      canvas.drawCircle(c, d[2] * 2.6, glow);
      canvas.drawCircle(c, d[2], core);
    }
  }

  @override
  bool shouldRepaint(covariant _HeroDotsPainter oldDelegate) => oldDelegate.clock != clock;
}
