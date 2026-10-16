part of '../main.dart';

class WorkflowPage extends StatefulWidget {
  const WorkflowPage({super.key});
  @override
  State<WorkflowPage> createState() => _WorkflowPageState();
}

class _WorkflowPageState extends State<WorkflowPage> {
  List<Map<String, dynamic>> steps = [];
  Map<String, dynamic> settings = {};
  List<Map<String, dynamic>> defaults = [];
  bool loading = true;
  String? error;
  bool editing = false;
  List<Map<String, dynamic>> draft = [];
  int exampleLead = 76;
  bool saving = false;
  int _tick = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tick = AppScope.of(context).refreshTick;
    if (tick != _tick && !editing) {
      _tick = tick;
      unawaited(load());
    }
  }

  Future<void> load() async {
    try {
      final r = await AppScope.read(context).api.getJson('/workflow');
      if (!mounted) return;
      setState(() {
        steps = (r['steps'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        defaults = (r['defaults'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        settings = Map<String, dynamic>.from(r['settings'] as Map);
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

  // Same rule as the server (services/workflowService.js computeSchedule), so
  // the example and the editor preview match what POs will get.
  Map<int, DateTime> _schedule(
      List<Map<String, dynamic>> s, DateTime n1, int lead) {
    final byNo = {for (final x in s) intFrom(x['stepNo'])!: x};
    final arrival =
        s.firstWhere((x) => x['isArrival'] == true, orElse: () => s[8]);
    final flex = s.where((x) => x['isFlex'] == true).toList();
    int? flexDays;
    if (flex.isNotEmpty) {
      flexDays = intFrom(flex.first['offsetDays']);
      if (settings['useMaterialLeadTime'] == true && lead > 0) {
        final chain = <Map<String, dynamic>>[];
        Map<String, dynamic>? cur = arrival;
        var guard = 0;
        while (cur != null && intFrom(cur['stepNo']) != 1 && guard < 12) {
          chain.add(cur);
          cur = byNo[intFrom(cur['anchorStepNo'])];
          guard++;
        }
        if (chain.any((c) => c['stepNo'] == flex.first['stepNo'])) {
          final others = chain
              .where((c) => c['stepNo'] != flex.first['stepNo'])
              .fold<int>(
                  0,
                  (a, c) =>
                      a +
                      (c['offsetMode'] == 'DAYS'
                          ? (intFrom(c['offsetDays']) ?? 0)
                          : 0));
          flexDays = max(intFrom(settings['minFlexDays']) ?? 0, lead - others);
        }
      }
    }
    final due = <int, DateTime>{1: n1};
    final sorted = [...s]..sort((a, b) =>
        (intFrom(a['stepNo']) ?? 0).compareTo(intFrom(b['stepNo']) ?? 0));
    for (final x in sorted) {
      final n = intFrom(x['stepNo'])!;
      if (n == 1) continue;
      final base = due[intFrom(x['anchorStepNo'])] ?? n1;
      if (x['offsetMode'] == 'END_OF_MONTH') {
        due[n] = DateTime(base.year, base.month + 1, 0);
      } else {
        final days = x['isFlex'] == true && flexDays != null
            ? flexDays
            : (intFrom(x['offsetDays']) ?? 0);
        due[n] = settings['dayMode'] == 'WORKING'
            ? _addWorking(base, days)
            : base.add(Duration(days: days));
      }
    }
    return due;
  }

  DateTime _addWorking(DateTime d, int days) {
    var cur = d;
    var left = days;
    while (left > 0) {
      cur = cur.add(const Duration(days: 1));
      if (cur.weekday <= 5) left--;
    }
    return cur;
  }

  String _rule(Map<String, dynamic> s, List<Map<String, dynamic>> all) {
    final n = intFrom(s['stepNo']);
    if (n == 1) return 'N1 — the PO date';
    final anchor = all.firstWhere((x) => x['stepNo'] == s['anchorStepNo'],
        orElse: () => {});
    final anchorName = anchor['milestone'] ?? 'step ${s['anchorStepNo']}';
    if (s['offsetMode'] == 'END_OF_MONTH') {
      return 'End of the month of $anchorName';
    }
    final days = intFrom(s['offsetDays']) ?? 0;
    final unit = settings['dayMode'] == 'WORKING' ? 'working days' : 'days';
    if (s['isFlex'] == true && settings['useMaterialLeadTime'] == true) {
      return '$anchorName + material lead time (default +$days)';
    }
    return days == 0 ? 'Same day as $anchorName' : '$anchorName + $days $unit';
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (loading) return _skeleton();
    if (error != null) {
      return PageBody(children: [ErrorPanel(message: error!, onRetry: load)]);
    }
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: _intro),
            if (scope.isSectionAdmin && !editing)
              DsPrimaryButton(
                label: 'Edit steps',
                icon: Icons.edit_outlined,
                height: 38,
                onPressed: () => setState(() {
                  editing = true;
                  draft =
                      steps.map((s) => Map<String, dynamic>.from(s)).toList();
                }),
              ),
          ]),
          const SizedBox(height: 18),
          _flow(editing ? draft : steps),
        ]),
      ),
      const SizedBox(height: 16),
      if (editing) _editor() else _example(),
    ]);
  }

  static const _intro =
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('How a purchase shipment flows',
        style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: DsColors.heading)),
    SizedBox(height: 4),
    Text(
        'Nine steps from issuing the PO to the goods arriving at the factory. People enter only the PO date (N1) — '
        'every later step is just ticked when it happens, and the next due date is worked out from that real date.',
        style: DsType.meta),
  ]);

  /// Both cards in place while the steps load: the flow's step tiles and the
  /// worked example's rows, ghosted, under their real titles.
  Widget _skeleton() {
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _intro,
          const SizedBox(height: 18),
          Wrap(runSpacing: 14, children: [
            for (var i = 0; i < kStepCount; i++)
              Row(mainAxisSize: MainAxisSize.min, children: [
                _stepGhost(i),
                if (i < kStepCount - 1)
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.arrow_forward,
                          size: 16, color: DsColors.iconSoft)),
              ]),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: DsCardTitle('Worked example — a PO issued today',
                    icon: Icons.calculate_outlined)),
            DsSkel.box(300, 30, radius: 10),
          ]),
          const SizedBox(height: 10),
          DsSkel.line(520, height: 10),
          const SizedBox(height: 18),
          for (var i = 0; i < kStepCount; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                SizedBox(
                    width: 36,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: DsSkel.circle(24))),
                Expanded(
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: DsSkel.line(DsSkel.vary(i, 170), height: 11))),
                SizedBox(
                    width: 260,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: DsSkel.line(DsSkel.vary(i + 3, 180)))),
                SizedBox(
                    width: 130,
                    child: Align(
                        alignment: Alignment.centerRight,
                        child: DsSkel.line(84, height: 11))),
              ]),
            ),
        ]),
      ),
    ]);
  }

  /// One tile of [_flow], ghosted.
  Widget _stepGhost(int i) {
    return Container(
      width: 196,
      height: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DsColors.subtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DsColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          DsSkel.circle(26),
          const SizedBox(width: 8),
          DsSkel.icon(17),
          const Spacer(),
          DsSkel.tag(28),
        ]),
        const SizedBox(height: 12),
        DsSkel.line(DsSkel.vary(i, 150), height: 12),
        const SizedBox(height: 7),
        if (i.isOdd) DsSkel.line(DsSkel.vary(i + 4, 86), height: 12),
        const Spacer(),
        DsSkel.line(DsSkel.vary(i + 2, 140), height: 10),
        const SizedBox(height: 6),
        DsSkel.line(DsSkel.vary(i + 7, 90), height: 8),
      ]),
    );
  }

  /// The nine steps on the RAP request-timeline board: a disc per step over a
  /// raised rail, its milestone floating above and its due-date rule below.
  /// Too narrow for the board → the flat tiles of [_flowTiles].
  Widget _flow(List<Map<String, dynamic>> s) {
    return Board3dRail(
      minCellPx: 140,
      maxPerRow: 5,
      minWidth: 520,
      stages: [
        for (var i = 0; i < s.length; i++)
          Board3dStage(
            title: '${s[i]['name']}',
            icon: stepIcon(s[i]['icon']),
            accent: s[i]['isArrival'] == true
                ? DsColors.tealFg
                : board3dPalette[i % board3dPalette.length],
            number: '${s[i]['stepNo']}',
            top: '${s[i]['milestone'] ?? ''}'.isEmpty
                ? null
                : '${s[i]['milestone']}',
            pills: [
              if (s[i]['isArrival'] == true) ('ARRIVAL = ETA', DsColors.tealFg),
              if (s[i]['isFlex'] == true)
                ('ABSORBS LEAD TIME', DsColors.navy),
            ],
            lines: [_rule(s[i], s)],
            glow: s[i]['isArrival'] == true,
          ),
      ],
      fallback: (_) => _flowTiles(s),
    );
  }

  Widget _flowTiles(List<Map<String, dynamic>> s) {
    return Wrap(spacing: 0, runSpacing: 14, children: [
      for (var i = 0; i < s.length; i++)
        Row(mainAxisSize: MainAxisSize.min, children: [
          DsRise(
            index: i,
            child: Container(
              width: 196,
              height: 150,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: s[i]['isArrival'] == true
                    ? DsColors.tealBg
                    : DsColors.subtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: s[i]['isFlex'] == true
                        ? DsColors.navyBorder
                        : DsColors.cardBorder,
                    width: s[i]['isFlex'] == true ? 1.6 : 1),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      _StepBadge(
                          no: intFrom(s[i]['stepNo'])!,
                          color: s[i]['isArrival'] == true
                              ? DsColors.tealFg
                              : DsColors.navy,
                          size: 26),
                      const SizedBox(width: 8),
                      Icon(stepIcon(s[i]['icon']),
                          size: 17, color: DsColors.icon),
                      const Spacer(),
                      if ('${s[i]['milestone'] ?? ''}'.isNotEmpty)
                        DsTag('${s[i]['milestone']}'),
                    ]),
                    const SizedBox(height: 8),
                    Text('${s[i]['name']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: DsType.panelTitle),
                    const Spacer(),
                    Text(_rule(s[i], s),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: DsColors.navyDeep)),
                    if (s[i]['isFlex'] == true ||
                        s[i]['isArrival'] == true) ...[
                      const SizedBox(height: 4),
                      Text(
                          s[i]['isArrival'] == true
                              ? 'Arrival = ETA'
                              : 'Absorbs the lead time',
                          style: DsType.metaSm),
                    ],
                  ]),
            ),
          ),
          if (i < s.length - 1)
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward,
                    size: 16, color: DsColors.iconSoft)),
        ]),
    ]);
  }

  Widget _example() {
    final n1 = DateTime.parse(todayIso());
    final due = _schedule(steps, n1, exampleLead);
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: DsCardTitle('Worked example — a PO issued today',
                  icon: Icons.calculate_outlined)),
          const Text('Material lead time  ', style: DsType.meta),
          DsSegmented(
            selected: const [30, 60, 76, 120, 150].indexOf(exampleLead),
            length: 5,
            itemBuilder: (context, i, t) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text('${const [30, 60, 76, 120, 150][i]} d',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(DsColors.muted, DsColors.navyDeep, t))),
            ),
            onSelect: (i) =>
                setState(() => exampleLead = const [30, 60, 76, 120, 150][i]),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          settings['useMaterialLeadTime'] == true
              ? 'The material master lead time stretches the "${steps.firstWhere((s) => s['isFlex'] == true, orElse: () => {
                        'shortName': '-'
                      })['shortName']}" step so that '
                  'the goods arrive on PO date + lead time. Days are ${settings['dayMode'] == 'WORKING' ? 'working days (Mon–Fri)' : 'calendar days'}.'
              : 'Fixed lead times (material lead time is not used). Days are ${settings['dayMode'] == 'WORKING' ? 'working days' : 'calendar days'}.',
          style: DsType.meta,
        ),
        const SizedBox(height: 14),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                  width: 36,
                  child: _StepBadge(
                      no: intFrom(s['stepNo'])!,
                      color: DsColors.navy,
                      size: 24,
                      filled: false)),
              Expanded(child: Text('${s['name']}', style: DsType.rowTitle)),
              SizedBox(
                  width: 260, child: Text(_rule(s, steps), style: DsType.meta)),
              SizedBox(
                width: 130,
                child: Text(fmtDate(isoDate(due[intFrom(s['stepNo'])]!)),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: s['isArrival'] == true
                            ? DsColors.tealFg
                            : DsColors.heading)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _editor() {
    final arrivalNo = draft.firstWhere((s) => s['isArrival'] == true,
        orElse: () => {})['stepNo'];
    final flexNo = draft.firstWhere((s) => s['isFlex'] == true,
        orElse: () => {})['stepNo'];
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const DsCardTitle('Edit steps', icon: Icons.tune),
        const SizedBox(height: 6),
        const InfoStrip(
          icon: Icons.warning_amber_rounded,
          color: DsColors.amberFg,
          text:
              'Saving re-plans the due dates of every open PO in this section. Steps already done keep their dates.',
        ),
        const SizedBox(height: 14),
        MinWidthScroll(
            minWidth: 1180,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: const [
                SizedBox(width: 36),
                Expanded(flex: 4, child: Text('NAME', style: DsType.eyebrow)),
                SizedBox(width: 10),
                Expanded(
                    flex: 2, child: Text('SHORT NAME', style: DsType.eyebrow)),
                SizedBox(width: 10),
                SizedBox(
                    width: 150,
                    child: Text('COUNTS FROM', style: DsType.eyebrow)),
                SizedBox(width: 10),
                SizedBox(
                    width: 160, child: Text('RULE', style: DsType.eyebrow)),
                SizedBox(width: 10),
                SizedBox(width: 80, child: Text('DAYS', style: DsType.eyebrow)),
                SizedBox(width: 10),
                SizedBox(
                    width: 70, child: Text('LEAD TIME', style: DsType.eyebrow)),
                SizedBox(width: 60, child: Text('ETA', style: DsType.eyebrow)),
                Expanded(
                    flex: 2,
                    child: Text('REFERENCE FIELD', style: DsType.eyebrow)),
              ]),
              const SizedBox(height: 6),
              for (final s in draft) _editRow(s, arrivalNo, flexNo),
            ])),
        const SizedBox(height: 14),
        Row(children: [
          TextButton.icon(
            onPressed: () => setState(() => draft =
                defaults.map((d) => Map<String, dynamic>.from(d)).toList()),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset to the PUR Process sheet defaults'),
          ),
          const Spacer(),
          DsOutlineButton(
              label: 'Cancel',
              height: 40,
              onPressed: saving ? null : () => setState(() => editing = false)),
          const SizedBox(width: 10),
          DsPrimaryButton(
              label: saving ? 'Saving…' : 'Save & re-plan',
              icon: Icons.save_outlined,
              height: 40,
              onPressed: saving ? null : _save),
        ]),
      ]),
    );
  }

  Widget _editRow(Map<String, dynamic> s, dynamic arrivalNo, dynamic flexNo) {
    final n = intFrom(s['stepNo'])!;
    final first = n == 1;
    InputDecoration dec() => dsInput().copyWith(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 36,
            child: _StepBadge(no: n, color: DsColors.navy, size: 24)),
        Expanded(
          flex: 4,
          child: TextFormField(
            initialValue: '${s['name']}',
            decoration: dec(),
            style: const TextStyle(fontSize: 12.5),
            onChanged: (v) => s['name'] = v,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: '${s['shortName']}',
            decoration: dec(),
            style: const TextStyle(fontSize: 12.5),
            onChanged: (v) => s['shortName'] = v,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 150,
          child: first
              ? const Text('— (PO date)', style: DsType.meta)
              : DropdownButtonFormField<int>(
                  initialValue: intFrom(s['anchorStepNo']),
                  isExpanded: true,
                  decoration: dec(),
                  style:
                      const TextStyle(fontSize: 12.5, color: DsColors.heading),
                  items: [
                    for (var a = 1; a < n; a++)
                      DropdownMenuItem(
                          value: a,
                          child: Text('$a. ${draft[a - 1]['shortName']}',
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => s['anchorStepNo'] = v),
                ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 160,
          child: first
              ? const SizedBox()
              : DropdownButtonFormField<String>(
                  initialValue: '${s['offsetMode']}',
                  isExpanded: true,
                  decoration: dec(),
                  style:
                      const TextStyle(fontSize: 12.5, color: DsColors.heading),
                  items: const [
                    DropdownMenuItem(value: 'DAYS', child: Text('+ days')),
                    DropdownMenuItem(
                        value: 'END_OF_MONTH',
                        child: Text('End of that month')),
                  ],
                  onChanged: (v) => setState(() {
                    s['offsetMode'] = v;
                    if (v == 'END_OF_MONTH') s['isFlex'] = false;
                  }),
                ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: first || s['offsetMode'] == 'END_OF_MONTH'
              ? const SizedBox()
              : TextFormField(
                  initialValue: '${s['offsetDays']}',
                  decoration: dec(),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3)
                  ],
                  style: const TextStyle(fontSize: 12.5),
                  onChanged: (v) => s['offsetDays'] = int.tryParse(v) ?? 0,
                ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 70,
          child: first || s['offsetMode'] == 'END_OF_MONTH'
              ? const SizedBox()
              : Tooltip(
                  message: 'This step absorbs the material lead time',
                  child: IconButton(
                    icon: Icon(
                        intFrom(flexNo) == n
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: intFrom(flexNo) == n
                            ? DsColors.navy
                            : DsColors.iconSoft),
                    onPressed: () => setState(() {
                      final turnOn = intFrom(flexNo) != n;
                      for (final x in draft) {
                        x['isFlex'] = turnOn && intFrom(x['stepNo']) == n;
                      }
                    }),
                  ),
                ),
        ),
        SizedBox(
          width: 60,
          child: first
              ? const SizedBox()
              : Tooltip(
                  message: 'Goods at the factory (ETA)',
                  child: IconButton(
                    icon: Icon(
                        intFrom(arrivalNo) == n
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: intFrom(arrivalNo) == n
                            ? DsColors.tealFg
                            : DsColors.iconSoft),
                    onPressed: () => setState(() {
                      for (final x in draft) {
                        x['isArrival'] = intFrom(x['stepNo']) == n;
                      }
                    }),
                  ),
                ),
        ),
        Expanded(
          flex: 2,
          child: first
              ? const SizedBox()
              : TextFormField(
                  initialValue: '${s['referenceLabel'] ?? ''}',
                  decoration: dec().copyWith(hintText: 'none'),
                  style: const TextStyle(fontSize: 12.5),
                  onChanged: (v) => s['referenceLabel'] = v,
                ),
        ),
      ]),
    );
  }

  Future<void> _save() async {
    final ok = await confirmAction(context,
        title: 'Save the workflow?',
        message:
            'Every open PO in this section will be re-planned with the new rules.',
        confirmLabel: 'Save & re-plan',
        icon: Icons.account_tree_outlined);
    if (!ok || !mounted) return;
    setState(() => saving = true);
    final api = AppScope.read(context).api;
    final body = {
      'steps': [
        for (final s in draft)
          {
            'stepNo': intFrom(s['stepNo']),
            'name': '${s['name']}'.trim(),
            'shortName': '${s['shortName']}'.trim(),
            'description': s['description'],
            'anchorStepNo':
                intFrom(s['stepNo']) == 1 ? null : intFrom(s['anchorStepNo']),
            'offsetDays': intFrom(s['offsetDays']) ?? 0,
            'offsetMode': s['offsetMode'] ?? 'DAYS',
            'isFlex': s['isFlex'] == true,
            'isArrival': s['isArrival'] == true,
            'referenceLabel': '${s['referenceLabel'] ?? ''}'.trim().isEmpty
                ? null
                : '${s['referenceLabel']}'.trim(),
          },
      ],
    };
    final r = await guard(context, () => api.putJson('/workflow', body));
    if (!mounted) return;
    setState(() => saving = false);
    if (r != null) {
      AppToast.success(context,
          'Workflow saved · ${r['recalculated']} open PO(s) re-planned');
      setState(() => editing = false);
      unawaited(load());
    }
  }
}
