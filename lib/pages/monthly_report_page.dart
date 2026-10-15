part of '../main.dart';

class MonthlyReportPage extends StatefulWidget {
  const MonthlyReportPage({super.key});
  @override
  State<MonthlyReportPage> createState() => _MonthlyReportPageState();
}

class _MonthlyReportPageState extends State<MonthlyReportPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;
  int _tick = -1;

  String get _key => '${month.year}-${month.month.toString().padLeft(2, '0')}';

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
      final r = await AppScope.read(context)
          .api
          .getJson('/reports/monthly?month=$_key');
      if (mounted) {
        setState(() {
          data = r;
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

  void _shift(int delta) {
    final next = DateTime(month.year, month.month + delta);
    if (next.isAfter(DateTime(DateTime.now().year, DateTime.now().month))) {
      return;
    }
    setState(() {
      month = next;
      loading = true;
    });
    unawaited(load());
  }

  Future<void> _emailMe() async {
    final api = AppScope.read(context).api;
    final r = await guard(
        context,
        () => api.postJson('/settings/mail/send-now',
            {'kind': 'monthly', 'toSelf': true, 'month': _key}));
    if (r != null && mounted) {
      final status = '${r['status']}';
      if (status == 'sent') {
        AppToast.success(context, 'Report sent to your email');
      } else if (status == 'pending_config') {
        AppToast.info(context,
            'Saved to the mail log — SMTP is not set up on the server yet');
      } else {
        AppToast.error(
            context, 'Could not send ($status) — see Settings › Mail log');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final isCurrent = _key == todayIso().substring(0, 7);
    return PageBody(children: [
      Row(children: [
        DsIconButton(
            icon: Icons.chevron_left,
            tooltip: 'Previous month',
            onTap: () => _shift(-1)),
        SizedBox(
            width: 180,
            child: Text(fmtMonth(_key),
                textAlign: TextAlign.center, style: DsType.pageTitle)),
        DsIconButton(
            icon: Icons.chevron_right,
            tooltip: 'Next month',
            onTap: isCurrent ? null : () => _shift(1)),
        if (isCurrent) ...[
          const SizedBox(width: 8),
          const DsTag('Month to date')
        ],
        const Spacer(),
        if (scope.isSectionAdmin) ...[
          DsOutlineButton(
              label: 'Email it to me',
              icon: Icons.forward_to_inbox_outlined,
              height: 38,
              onPressed: _emailMe),
          const SizedBox(width: 8),
        ],
        DsPrimaryButton(
          label: 'Export Excel',
          icon: Icons.download_outlined,
          height: 38,
          onPressed: () => unawaited(downloadFromApi(
              context,
              '/reports/monthly/export?month=$_key',
              'monthly-report-${scope.sectionCode}-$_key.xlsx')),
        ),
      ]),
      const SizedBox(height: 16),
      if (error != null) ErrorPanel(message: error!, onRetry: load),
      if (loading && data == null) const DsSkeletonList(rows: 6),
      if (data != null) ..._content(scope, data!),
    ]);
  }

  List<Widget> _content(AppScope scope, Map<String, dynamic> d) {
    final issued = Map<String, dynamic>.from(d['issued'] as Map);
    final arrived = Map<String, dynamic>.from(d['arrived'] as Map);
    final steps = (d['stepPerformance'] as List).cast<Map>();
    final suppliers = (d['supplierPerformance'] as List).cast<Map>();
    final arrivals = (d['arrivals'] as List).cast<Map>();
    final open = (d['openOverdue'] as List).cast<Map>();
    final values = (issued['valueByCurrency'] as List).cast<Map>();
    return [
      LayoutBuilder(builder: (context, box) {
        final perRow = box.maxWidth >= 1200
            ? 5
            : box.maxWidth >= 760
                ? 3
                : 2;
        final w = (box.maxWidth - 12 * (perRow - 1)) / perRow;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          MetricTile(
              width: w,
              icon: Icons.receipt_long_outlined,
              label: 'POs issued',
              value: '${issued['count']}',
              color: DsColors.navy,
              sub: values.isEmpty
                  ? '${issued['cancelled']} cancelled'
                  : values
                      .map((v) => '${fmtNum(v['value'])} ${v['currency']}')
                      .join(' · ')),
          MetricTile(
              width: w,
              icon: Icons.warehouse_outlined,
              label: 'Arrived at factory',
              value: '${arrived['count']}',
              color: DsColors.tealFg,
              sub: 'avg lead time ${arrived['avgActualLeadTime'] ?? '-'} d'),
          MetricTile(
              width: w,
              icon: Icons.verified_outlined,
              label: 'On-time arrivals',
              value: arrived['onTimeRate'] == null
                  ? '-'
                  : '${arrived['onTimeRate']}%',
              color: DsColors.greenFg,
              sub: '${arrived['onTime']} on time · ${arrived['late']} late'),
          MetricTile(
              width: w,
              icon: Icons.timelapse,
              label: 'Average delay',
              value: '${arrived['avgDelayDays']} d',
              color: DsColors.amberFg,
              sub: 'vs. original plan'),
          MetricTile(
              width: w,
              icon: Icons.warning_amber_rounded,
              label: 'Open & overdue',
              value: '${d['openOverdueCount']}',
              color: DsColors.redFg,
              sub: 'of ${d['openCount']} open at month end'),
        ]);
      }),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Step performance — steps completed in ${fmtMonth(_key)}',
              icon: Icons.account_tree_outlined),
          const SizedBox(height: 12),
          for (final s in steps) _stepBar(Map<String, dynamic>.from(s)),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('Supplier performance (arrivals this month)',
              icon: Icons.storefront_outlined),
          const SizedBox(height: 10),
          if (suppliers.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No arrivals this month', style: DsType.meta))
          else
            _table(
              const [
                'Supplier',
                'Arrived',
                'On time',
                'On-time %',
                'Avg delay',
                'Lead time actual / master'
              ],
              const [null, 80.0, 80.0, 90.0, 90.0, 180.0],
              [
                for (final s in suppliers)
                  [
                    '${s['name'] ?? s['supplierCode']}',
                    '${s['arrived']}',
                    '${s['onTime']}',
                    s['onTimeRate'] == null ? '-' : '${s['onTimeRate']}%',
                    '${s['avgDelayDays']} d',
                    '${s['avgActualLeadTime'] ?? '-'} / ${s['avgMasterLeadTime'] ?? '-'} d',
                  ],
              ],
            ),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Arrivals (${arrivals.length})',
              icon: Icons.local_shipping_outlined),
          const SizedBox(height: 10),
          if (arrivals.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No shipment reached the factory this month',
                    style: DsType.meta))
          else
            _table(
              const [
                'PO No.',
                'Supplier',
                'PO date',
                'Planned',
                'Arrived',
                'Delay',
                'Lead time',
                'S/I ref.'
              ],
              const [110.0, null, 100.0, 100.0, 100.0, 70.0, 90.0, 110.0],
              [
                for (final a in arrivals)
                  [
                    '${a['poNo']}',
                    '${a['supplierName'] ?? '-'}',
                    fmtDate(a['documentDate']),
                    fmtDate(a['plannedArrival']),
                    fmtDate(a['actualArrival']),
                    (intFrom(a['delayDays']) ?? 0) > 0
                        ? '+${a['delayDays']} d'
                        : 'on time',
                    '${a['actualLeadTime'] ?? '-'} d',
                    '${a['shipmentRef'] ?? '-'}',
                  ],
              ],
              onTap: (i) =>
                  unawaited(scope.openPo(intFrom(arrivals[i]['poId'])!)),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Still open and overdue (${d['openOverdueCount']})',
              icon: Icons.warning_amber_rounded),
          const SizedBox(height: 10),
          if (open.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nothing overdue 🎉', style: DsType.meta))
          else
            _table(
              const ['PO No.', 'Supplier', 'Waiting for', 'Due', 'Late', 'ETA'],
              const [110.0, null, null, 100.0, 80.0, 100.0],
              [
                for (final p in open)
                  [
                    '${p['poNo']}',
                    '${p['supplierShort'] ?? p['supplierName'] ?? '-'}',
                    '${p['currentStepName'] ?? '-'}',
                    fmtDate(p['nextDueDate']),
                    '${p['overdueDays']} d',
                    fmtDate(p['etaDate']),
                  ],
              ],
              onTap: (i) => unawaited(scope.openPo(intFrom(open[i]['id'])!)),
            ),
        ]),
      ),
    ];
  }

  Widget _stepBar(Map<String, dynamic> s) {
    final done = intFrom(s['done']) ?? 0;
    final onTime = intFrom(s['onTime']) ?? 0;
    final late = intFrom(s['late']) ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(
            width: 30,
            child: Text('${s['stepNo']}',
                style: mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: DsColors.faint2))),
        SizedBox(
            width: 300,
            child: Text('${s['name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsType.meta)),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: done == 0
                  ? Container(color: DsColors.track)
                  : Row(children: [
                      if (onTime > 0)
                        Expanded(
                            flex: onTime,
                            child: Container(
                                color: DsColors.greenFg.withValues(alpha: .8))),
                      if (late > 0)
                        Expanded(
                            flex: late,
                            child: Container(
                                color:
                                    DsColors.amberFg.withValues(alpha: .85))),
                    ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 220,
          child: Text(
            done == 0
                ? 'none done'
                : '$done done · $onTime on time · $late late${late > 0 ? ' (avg ${s['avgLateDays']} d)' : ''}',
            style: DsType.metaSm,
          ),
        ),
      ]),
    );
  }

  Widget _table(
      List<String> headers, List<double?> widths, List<List<String>> rows,
      {void Function(int i)? onTap}) {
    Widget cell(String t, double? w, {bool head = false}) {
      final text = Text(head ? t.toUpperCase() : t,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: head
              ? DsType.eyebrow
              : const TextStyle(fontSize: 12.5, color: DsColors.text));
      return w == null
          ? Expanded(child: text)
          : SizedBox(width: w, child: text);
    }

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: DsColors.subtle, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          for (var i = 0; i < headers.length; i++)
            cell(headers[i], widths[i], head: true)
        ]),
      ),
      for (var r = 0; r < rows.length; r++)
        InkWell(
          onTap: onTap == null ? null : () => onTap(r),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
            child: Row(children: [
              for (var i = 0; i < headers.length; i++)
                cell(rows[r][i], widths[i])
            ]),
          ),
        ),
    ]);
  }
}
