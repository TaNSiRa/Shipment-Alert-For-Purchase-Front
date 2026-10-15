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
    if (data == null) {
      return const PageBody(children: [DsSkeletonList(rows: 6)]);
    }
    final scope = AppScope.of(context);
    final d = data!;
    final counts = Map<String, dynamic>.from(d['counts'] as Map);
    final width = MediaQuery.of(context).size.width;
    final cols = width >= 1500
        ? 3
        : width >= 1150
            ? 2
            : 1;
    return PageBody(children: [
      DsRise(child: _hero(scope, counts)),
      const SizedBox(height: 16),
      DsRise(index: 1, child: _tiles(scope, counts)),
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

  Widget _grid(int cols, List<Widget> children) {
    if (cols == 1) {
      return Column(children: [
        for (final c in children) ...[c, const SizedBox(height: 16)],
      ]);
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += cols) {
      final slice = children.sublist(i, min(i + cols, children.length));
      // No IntrinsicHeight here: the chart cards measure themselves with a
      // LayoutBuilder, which cannot report intrinsic sizes.
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var j = 0; j < slice.length; j++) ...[
          if (j > 0) const SizedBox(width: 16),
          Expanded(child: slice[j]),
        ],
        for (var k = slice.length; k < cols; k++) ...[
          const SizedBox(width: 16),
          const Expanded(child: SizedBox())
        ],
      ]));
      rows.add(const SizedBox(height: 16));
    }
    return Column(children: rows);
  }

  Widget _hero(AppScope scope, Map<String, dynamic> c) {
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    final overdue = intFrom(c['overdue']) ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Lg.on ? Lg.r(18) : 18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff6f66ee), Color(0xff5b53e0), Color(0xff4a41c7)],
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x335b53e0), blurRadius: 24, offset: Offset(0, 10))
        ],
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
            Text(
              overdue > 0
                  ? '${plural(intFrom(c['active']) ?? 0, 'shipment')} open · $overdue need follow-up today.'
                  : '${plural(intFrom(c['active']) ?? 0, 'shipment')} open · everything is on track.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .9), fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text('Today ${fmtDate(data!['today'])} · ${scope.section['name']}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .7), fontSize: 12)),
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
    );
  }

  Widget _tiles(AppScope scope, Map<String, dynamic> c) {
    final arrived = intFrom(c['arrivedThisMonth']) ?? 0;
    final onTime = intFrom(c['arrivedOnTimeThisMonth']) ?? 0;
    return LayoutBuilder(builder: (context, box) {
      final perRow = box.maxWidth >= 1200
          ? 6
          : box.maxWidth >= 760
              ? 3
              : 2;
      final w = (box.maxWidth - 12 * (perRow - 1)) / perRow;
      return Wrap(spacing: 12, runSpacing: 12, children: [
        MetricTile(
            width: w,
            icon: Icons.warning_amber_rounded,
            label: 'Overdue',
            value: '${c['overdue']}',
            color: DsColors.redFg,
            sub: 'step past its due date',
            onTap: () => scope.navigate(AppPage.pos, args: {'due': 'OVERDUE'})),
        MetricTile(
            width: w,
            icon: Icons.today_outlined,
            label: 'Due today',
            value: '${c['dueToday']}',
            color: DsColors.amberFg,
            sub: 'finish today',
            onTap: () => scope.navigate(AppPage.pos, args: {'due': 'TODAY'})),
        MetricTile(
            width: w,
            icon: Icons.schedule,
            label: 'Due soon',
            value: '${c['dueSoon']}',
            color: DsColors.amberFg,
            sub: 'next few days',
            onTap: () => scope.navigate(AppPage.pos, args: {'due': 'SOON'})),
        MetricTile(
            width: w,
            icon: Icons.warehouse_outlined,
            label: 'Arriving this month',
            value: '${c['arrivingThisMonth']}',
            color: DsColors.tealFg,
            sub: '${c['arrivingNext7']} in the next 7 days',
            onTap: () => scope.navigate(AppPage.calendar)),
        MetricTile(
            width: w,
            icon: Icons.receipt_long_outlined,
            label: 'POs issued this month',
            value: '${c['issuedThisMonth']}',
            color: DsColors.navy,
            sub: 'by PO date',
            onTap: () => scope.navigate(AppPage.report)),
        MetricTile(
            width: w,
            icon: Icons.verified_outlined,
            label: 'Arrived this month',
            value: '$arrived',
            color: DsColors.greenFg,
            sub: arrived == 0
                ? 'none yet'
                : '${(onTime / arrived * 100).round()}% on time',
            onTap: () => scope.navigate(AppPage.report)),
      ]);
    });
  }

  Widget _pipeline(AppScope scope, List<Map> steps) {
    final total = steps.fold<int>(0, (a, s) => a + (intFrom(s['count']) ?? 0));
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle('Shipment pipeline — where the open POs are waiting',
            icon: Icons.route_outlined,
            trailing: TextButton(
                onPressed: () => scope.navigate(AppPage.roadmap),
                child: const Text('Open road map'))),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < steps.length; i++) ...[
              _pipeStep(scope, Map<String, dynamic>.from(steps[i]), total),
              if (i < steps.length - 1)
                const Padding(
                  padding: EdgeInsets.only(top: 34),
                  child: Icon(Icons.chevron_right,
                      size: 18, color: DsColors.iconSoft),
                ),
            ],
          ]),
        ),
      ]),
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

  Widget _poList(String title, IconData icon, Color color, List<Map> items,
      {required String empty, required VoidCallback onAll, bool eta = false}) {
    final scope = AppScope.of(context);
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
        if (items.isEmpty)
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

  Widget _trend(List<Map> trend) {
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const DsCardTitle('Last 6 months', icon: Icons.bar_chart),
        const SizedBox(height: 12),
        GroupedBarChart(
          labels: [
            for (final t in trend)
              intl.DateFormat('MMM').format(DateTime.parse('${t['month']}-01'))
          ],
          series: [
            (
              'POs issued',
              DsColors.navy,
              [for (final t in trend) intFrom(t['issued']) ?? 0]
            ),
            (
              'Arrived',
              DsColors.tealFg,
              [for (final t in trend) intFrom(t['arrived']) ?? 0]
            ),
            (
              'On time',
              DsColors.greenFg,
              [for (final t in trend) intFrom(t['onTime']) ?? 0]
            ),
          ],
        ),
      ]),
    );
  }

  Widget _modes(Map<String, dynamic> modes) {
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
        const SizedBox(height: 18),
        DonutChart(
          centerLabel: 'open',
          slices: [
            for (final e in modes.entries)
              (
                e.key == 'UNKNOWN' ? 'Not set' : shipModeLabel(e.key),
                colors[e.key] ?? DsColors.faint2,
                intFrom(e.value) ?? 0
              ),
          ],
        ),
      ]),
    );
  }

  Widget _suppliers(AppScope scope, List<Map> suppliers) {
    final top =
        suppliers.fold<int>(0, (a, s) => max(a, intFrom(s['count']) ?? 0));
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const DsCardTitle('Open POs by supplier',
            icon: Icons.storefront_outlined),
        const SizedBox(height: 10),
        if (suppliers.isEmpty)
          const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No open POs', style: DsType.meta)),
        for (final s in suppliers)
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
