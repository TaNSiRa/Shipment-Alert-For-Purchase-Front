part of '../main.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> events = [];
  /// Company holidays in the month: ISO date → name ('' when the holiday
  /// database has the date only).
  Map<String, String> holidays = {};
  bool loading = true;
  String? error;
  String? selectedDay;
  final Set<String> kinds = {'due', 'overdue', 'done', 'eta'};
  int _tick = -1;

  /// Weekends and company holidays: the same grey as RAP's weekly plan and
  /// personal calendar — opaque under liquid glass, a chip tint on the flat theme.
  static Color get _offDayBg => Lg.on ? const Color(0xffc7cddf) : DsColors.chip;

  static const _kindStyle = {
    'overdue': (
      DsColors.redFg,
      DsColors.redBg,
      'Overdue',
      Icons.warning_amber_rounded
    ),
    'due': (DsColors.navy, Color(0x225b53e0), 'Due', Icons.schedule),
    'done': (
      DsColors.greenFg,
      DsColors.greenBg,
      'Done',
      Icons.check_circle_outline
    ),
    'eta': (
      DsColors.tealFg,
      DsColors.tealBg,
      'ETA at factory',
      Icons.warehouse_outlined
    ),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).refreshTick;
    if (tick != _tick) {
      _tick = tick;
      unawaited(load());
    }
  }

  String get _monthKey =>
      '${month.year}-${month.month.toString().padLeft(2, '0')}';

  Future<void> load() async {
    try {
      final r = await AppScope.read(context)
          .api
          .getJson('/pos/calendar?month=$_monthKey');
      if (!mounted) return;
      setState(() {
        events = (r['events'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        holidays = {
          for (final h in (r['holidays'] as List? ?? const []))
            '${h['date']}': '${h['name'] ?? ''}'
        };
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

  void _shift(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
      loading = true;
      selectedDay = null;
    });
    unawaited(load());
  }

  @override
  Widget build(BuildContext context) {
    final visible = events.where((e) => kinds.contains(e['kind'])).toList();
    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final e in visible) {
      byDay.putIfAbsent('${e['date']}', () => []).add(e);
    }
    final wide = MediaQuery.of(context).size.width >= 1250;
    final calendar = DsCard(
      child: Column(children: [
        Row(children: [
          DsIconButton(
              icon: Icons.chevron_left,
              tooltip: 'Previous month',
              onTap: () => _shift(-1)),
          SizedBox(
            width: 170,
            child: Text(intl.DateFormat('MMMM yyyy').format(month),
                textAlign: TextAlign.center, style: DsType.pageTitle),
          ),
          DsIconButton(
              icon: Icons.chevron_right,
              tooltip: 'Next month',
              onTap: () => _shift(1)),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () {
              final now = DateTime.now();
              month = DateTime(now.year, now.month);
              selectedDay = todayIso();
              setState(() => loading = true);
              unawaited(load());
            },
            child: const Text('Today'),
          ),
          const Spacer(),
          Wrap(spacing: 6, children: [
            for (final k in _kindStyle.entries)
              FilterChip(
                label: Text(k.value.$3),
                avatar: Icon(k.value.$4, size: 15, color: k.value.$1),
                selected: kinds.contains(k.key),
                showCheckmark: false,
                selectedColor: k.value.$2,
                labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: k.value.$1),
                onSelected: (v) =>
                    setState(() => v ? kinds.add(k.key) : kinds.remove(k.key)),
              ),
          ]),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final d in const [
            'Sun',
            'Mon',
            'Tue',
            'Wed',
            'Thu',
            'Fri',
            'Sat'
          ])
            Expanded(
                child: Center(
                    child: Text(d.toUpperCase(), style: DsType.eyebrow))),
        ]),
        const SizedBox(height: 6),
        if (loading)
          const LinearProgressIndicator(minHeight: 2)
        else
          const SizedBox(height: 2),
        _grid(byDay),
      ]),
    );
    final panel = _dayPanel(byDay);
    return PageBody(children: [
      if (error != null) ErrorPanel(message: error!, onRetry: load),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: calendar),
          const SizedBox(width: 16),
          SizedBox(width: 340, child: panel),
        ])
      else ...[
        calendar,
        const SizedBox(height: 16),
        panel,
      ],
    ]);
  }

  Widget _grid(Map<String, List<Map<String, dynamic>>> byDay) {
    final first = DateTime(month.year, month.month, 1);
    final leading = first.weekday % 7; // Sunday first
    final days = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((leading + days) / 7).ceil() * 7;
    final today = todayIso();
    return Column(children: [
      for (var r = 0; r < cells / 7; r++)
        Row(children: [
          for (var c = 0; c < 7; c++)
            Expanded(
                child: _dayCell(r * 7 + c - leading + 1, days, byDay, today,
                    c == 0 || c == 6)),
        ]),
    ]);
  }

  Widget _dayCell(
      int day,
      int days,
      Map<String, List<Map<String, dynamic>>> byDay,
      String today,
      bool weekend) {
    if (day < 1 || day > days) return const SizedBox(height: 104);
    final iso = isoDate(DateTime(month.year, month.month, day));
    final holiday = holidays[iso];
    final offDay = weekend || holiday != null;
    final list = byDay[iso] ?? const [];
    final isToday = iso == today;
    final isSelected = iso == selectedDay;
    final counts = <String, int>{};
    for (final e in list) {
      counts['${e['kind']}'] = (counts['${e['kind']}'] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.all(3),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => selectedDay = iso),
        child: Container(
          height: 98,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isSelected
                ? DsColors.navySoft.withValues(alpha: .4)
                : offDay
                    ? _offDayBg
                    : DsColors.subtle,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isSelected
                    ? DsColors.navy
                    : isToday
                        ? DsColors.navyBorder
                        : DsColors.lineSoft,
                width: isSelected ? 1.6 : 1),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: isToday
                    ? BoxDecoration(
                        color: DsColors.navy,
                        borderRadius: BorderRadius.circular(8))
                    : null,
                child: Text('$day',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? Colors.white
                            : offDay
                                ? DsColors.faint2
                                : DsColors.heading)),
              ),
              // As in RAP: a weekday holiday says so beside the number.
              if (holiday != null && !weekend) ...[
                const SizedBox(width: 5),
                Expanded(
                  child: Tooltip(
                    message: holiday.isEmpty ? 'Holiday' : holiday,
                    child: Text(holiday.isEmpty ? 'Holiday' : holiday,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: DsColors.faint)),
                  ),
                ),
              ] else
                const Spacer(),
              if (list.length > 3)
                Text('+${list.length - 3}', style: DsType.metaSm),
            ]),
            const SizedBox(height: 4),
            for (final e in list.take(3))
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: _kindStyle[e['kind']]!.$2,
                    borderRadius: BorderRadius.circular(5)),
                child: Text('${e['poNo']} · ${e['stepShort']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _kindStyle[e['kind']]!.$1)),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _dayPanel(Map<String, List<Map<String, dynamic>>> byDay) {
    final scope = AppScope.of(context);
    final day = selectedDay;
    final list =
        day == null ? const <Map<String, dynamic>>[] : (byDay[day] ?? const []);
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle(day == null ? 'Pick a day' : fmtDate(day),
            icon: Icons.event_note_outlined),
        if (day != null && holidays[day] != null) ...[
          const SizedBox(height: 6),
          DsTag(holidays[day]!.isEmpty
              ? 'Company holiday'
              : 'Holiday · ${holidays[day]}'),
        ],
        const SizedBox(height: 10),
        if (day == null)
          const Text(
              'Click a day in the calendar to see what is due, what was done and what arrives.',
              style: DsType.meta)
        else if (list.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Nothing on this day', style: DsType.meta))
        else
          for (final e in list)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => unawaited(scope.openPo(intFrom(e['poId'])!)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                child: Row(children: [
                  Icon(_kindStyle[e['kind']]!.$4,
                      size: 18, color: _kindStyle[e['kind']]!.$1),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PO ${e['poNo']} · ${e['supplier'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.rowTitle),
                          Text(
                              '${_kindStyle[e['kind']]!.$3} · ${e['stepNo']}. ${e['stepName']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.metaSm),
                        ]),
                  ),
                ]),
              ),
            ),
        const Divider(height: 24),
        Text('This month', style: DsType.panelTitle),
        const SizedBox(height: 8),
        for (final k in _kindStyle.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              DsDot(k.value.$1),
              const SizedBox(width: 8),
              Expanded(child: Text(k.value.$3, style: DsType.meta)),
              Text('${events.where((e) => e['kind'] == k.key).length}',
                  style: mono(size: 12, weight: FontWeight.w700)),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: _offDayBg,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: DsColors.cardBorder),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
                child: Text('Weekend / holiday', style: DsType.meta)),
            Tooltip(
              message: 'Company holidays this month',
              child: Text(
                  '${holidays.keys.where((d) => DateTime.parse(d).weekday < 6).length}',
                  style: mono(size: 12, weight: FontWeight.w700)),
            ),
          ]),
        ),
      ]),
    );
  }
}
