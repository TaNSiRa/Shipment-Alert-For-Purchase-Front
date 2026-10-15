part of '../main.dart';

/// "Shipment progress road map": every open PO as one row, the ten steps as
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

  static const _wPo = 230.0;
  static const _wCell = 92.0;
  static const _wEta = 108.0;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final tableWidth = _wPo + _wCell * 10 + _wEta + 24;
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
                _debounce = Timer(const Duration(milliseconds: 350), load);
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
                            final w = max(box.maxWidth, tableWidth);
                            return Scrollbar(
                              thumbVisibility: true,
                              notificationPredicate: (n) =>
                                  n.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: w,
                                  child: Column(children: [
                                    _header(),
                                    const Divider(height: 1),
                                    Expanded(
                                      child: ListView.separated(
                                        itemCount: rows.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(
                                                height: 1,
                                                color: DsColors.lineSoft),
                                        itemBuilder: (_, i) =>
                                            _row(scope, rows[i]),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                          }),
          ),
        ),
      ),
    ]);
  }

  Widget _header() {
    return Container(
      color: DsColors.subtle,
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        const SizedBox(
            width: _wPo, child: Text('PURCHASE ORDER', style: DsType.eyebrow)),
        for (final s in steps)
          SizedBox(
            width: _wCell,
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

  Widget _row(AppScope scope, Map<String, dynamic> po) {
    final stepRows = (po['steps'] as List).cast<Map>();
    final current = intFrom(po['currentStep']) ?? 11;
    final today = todayIso();
    return InkWell(
      onTap: () => unawaited(scope.openPo(intFrom(po['id'])!)),
      hoverColor: const Color(0x30ffffff),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          SizedBox(
            width: _wPo,
            child: Row(children: [
              DueDot(state: '${po['dueState']}'),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
          for (var n = 1; n <= 10; n++)
            SizedBox(
              width: _wCell,
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
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
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
      child: Column(children: [
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
                  color: n == 10
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
