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
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = friendlyError(e.message));
    }
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
      DsRise(
        index: 4,
        child: _grid(cols, [
          _trend((d['trend'] as List).cast<Map>()),
          _modes(Map<String, dynamic>.from(d['modes'] as Map)),
          _suppliers(scope, (d['bySupplier'] as List).cast<Map>()),
        ]),
      ),
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
      _grid(cols, [_trend(null), _modes(null), _suppliers(scope, null)]),
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const RadialGradient(
            center: Alignment(.75, -1.1),
            radius: .9,
            colors: [Color(0x996a64e0), Color(0x00494aa8)],
          ),
        ),
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
                      ? '${plural(intFrom(c['active']) ?? 0, 'shipment')} open · $overdue need follow-up today.'
                      : '${plural(intFrom(c['active']) ?? 0, 'shipment')} open · everything is on track.',
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
              onPressed: () async {
                if (await showPoImportDialog(context)) unawaited(load());
              },
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Import Excel'),
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
    );
  }

  Widget _pipeline(AppScope scope, List<Map>? steps) {
    final total = (steps ?? const [])
        .fold<int>(0, (a, s) => a + (intFrom(s['count']) ?? 0));
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle('Shipment pipeline — where the open POs are waiting',
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
      top: plural(count, 'PO'),
      pills: [
        if (overdue > 0) ('$overdue OVERDUE', DsColors.redFg),
        if (overdue == 0 && soon > 0) ('$soon DUE SOON', DsColors.amberFg),
      ],
      lines: [
        if (count > 0 && total > 0)
          '${(count * 100 / total).round()}% of open POs'
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
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const DsCardTitle('Last 6 months — planned vs arrived',
            icon: Icons.bar_chart),
        const SizedBox(height: 12),
        if (trend == null)
          _trendGhost()
        else
          // Per month, one set of POs: those PLANNED to reach the factory that
          // month (left, the target from the PO date) and how many of them have
          // arrived (right), on time or late. The empty height between the two
          // is what has not arrived yet.
          ExtrudedBarChart(
            labels: [
              for (final t in trend)
                intl.DateFormat('MMM')
                    .format(DateTime.parse('${t['month']}-01'))
            ],
            tooltipTitles: [
              for (final t in trend)
                intl.DateFormat('MMM yyyy')
                    .format(DateTime.parse('${t['month']}-01'))
            ],
            currentIndex: trend.isEmpty ? null : trend.length - 1,
            series: [
              BarSeries('Planned', [
                BarSegment('Planned to arrive', DsColors.navy,
                    [for (final t in trend) intFrom(t['planned']) ?? 0]),
              ], notes: [
                (
                  'Arrived',
                  [
                    for (final t in trend)
                      (intFrom(t['plannedOnTime']) ?? 0) +
                          (intFrom(t['plannedLate']) ?? 0)
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
                (
                  'Planned',
                  [for (final t in trend) intFrom(t['planned']) ?? 0]
                ),
              ]),
            ],
          ),
      ]),
    );
  }

  /// [ExtrudedBarChart], ghosted: its legend, six month groups of a planned
  /// and an arrived bar on the baseline, and the month labels.
  Widget _trendGhost() {
    const planned = <double>[96, 128, 84, 146, 112, 152];
    const arrived = [.82, .7, .9, .64, .5, .28];
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
        height: 210,
        child: Column(children: [
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var g = 0; g < planned.length; g++)
                Expanded(
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DsSkel.box(20, planned[g], radius: 4),
                        const SizedBox(width: 6),
                        DsSkel.box(20, planned[g] * arrived[g], radius: 4),
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

  Widget _modes(Map<String, dynamic>? modes) {
    const colors = {
      'SEA': DsColors.blueFg,
      'AIR': DsColors.purpleFg,
      'TRUCK': DsColors.amberFg,
      'COURIER': DsColors.tealFg
    };
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const DsCardTitle('Open shipments by mode',
            icon: Icons.directions_boat_outlined),
        const SizedBox(height: 8),
        if (modes == null)
          SizedBox(height: 236, width: double.infinity, child: _donutGhost())
        else if (modes.values.every((v) => (intFrom(v) ?? 0) <= 0))
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No open shipments', style: DsType.meta))
        else
          SizedBox(
            height: 236,
            width: double.infinity,
            child: RaisedDonut(
              caption: 'open',
              slices: [
                for (final e in modes.entries)
                  DonutSlice(
                    e.key == 'UNKNOWN' ? 'Not set' : shipModeLabel(e.key),
                    intFrom(e.value) ?? 0,
                    colors[e.key] ?? DsColors.faint2,
                  ),
              ],
            ),
          ),
      ]),
    );
  }

  /// [RaisedDonut], ghosted: the tilted ring, its total in the hole and a
  /// label on either side where the leader lines end.
  Widget _donutGhost() {
    Widget label(CrossAxisAlignment align, double w) =>
        DsSkel.lines(w, w * .55, align: align);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              label(CrossAxisAlignment.end, 54),
              const SizedBox(height: 40),
              label(CrossAxisAlignment.end, 42),
            ]),
        const SizedBox(width: 18),
        Stack(alignment: Alignment.center, children: [
          Container(
            width: 210,
            height: 124,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.elliptical(105, 62)),
              border: Border.all(color: DsColors.line, width: 24),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            DsSkel.box(34, 18, radius: 5),
            const SizedBox(height: 5),
            DsSkel.line(28, height: 8),
          ]),
        ]),
        const SizedBox(width: 18),
        Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(CrossAxisAlignment.start, 48),
              const SizedBox(height: 40),
              label(CrossAxisAlignment.start, 58),
            ]),
      ]),
    );
  }

  Widget _suppliers(AppScope scope, List<Map>? suppliers) {
    final top = (suppliers ?? const [])
        .fold<int>(0, (a, s) => max(a, intFrom(s['count']) ?? 0));
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const DsCardTitle('Open POs by supplier',
            icon: Icons.storefront_outlined),
        const SizedBox(height: 10),
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
                            color: DsColors.track,
                            borderRadius: BorderRadius.circular(6))),
                    FractionallySizedBox(
                        widthFactor: const [.92, .74, .58, .45, .33, .2][i],
                        child: DsSkel.fill(12, radius: 6)),
                  ]),
                ),
                const SizedBox(width: 10),
                SizedBox(
                    width: 30,
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: DsSkel.line(14, height: 10))),
              ]),
            )
        else if (suppliers.isEmpty)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No open POs', style: DsType.meta)),
        for (final s in suppliers ?? const <Map>[])
          HBar(
            label: '${s['name']}',
            value: intFrom(s['count']) ?? 0,
            max: top,
            color: (intFrom(s['overdue']) ?? 0) > 0
                ? DsColors.redFg.withValues(alpha: .75)
                : DsColors.navy,
            extra: (intFrom(s['overdue']) ?? 0) > 0
                ? Tooltip(
                    message: 'overdue',
                    child: DsTag('${s['overdue']}',
                        color: DsColors.redFg, bg: DsColors.redBg))
                : null,
            onTap: () => scope.navigate(AppPage.pos,
                args: {'q': s['supplierCode'] ?? s['name']}),
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
