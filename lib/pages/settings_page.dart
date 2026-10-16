part of '../main.dart';

enum _SettingsTab {
  mail,
  scheduling,
  imports,
  outbox,
  activity,
  holidays,
  security,
  system
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsTab tab = _SettingsTab.mail;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (!scope.isSectionAdmin) {
      return const PageBody(children: [
        InfoStrip(
            icon: Icons.lock_outline,
            text: 'Only section admins can open Settings.')
      ]);
    }
    final sectionItems = [
      (_SettingsTab.mail, Icons.mail_outline, 'Email alerts'),
      (_SettingsTab.scheduling, Icons.timelapse, 'Due soon alert'),
    ];
    final systemItems = [
      (_SettingsTab.imports, Icons.upload_file, 'Import history'),
      (_SettingsTab.outbox, Icons.outbox_outlined, 'Mail log'),
      (_SettingsTab.activity, Icons.history, 'Activity log'),
      (_SettingsTab.holidays, Icons.beach_access_outlined, 'Holidays'),
      (_SettingsTab.security, Icons.shield_outlined, 'Login security'),
      (_SettingsTab.system, Icons.dns_outlined, 'System status & log'),
    ];
    Widget item((_SettingsTab, IconData, String) e) {
      final selected = tab == e.$1;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: selected ? DsColors.navySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => tab = e.$1),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Icon(e.$2,
                    size: 18,
                    color: selected ? DsColors.navyDeep : DsColors.icon),
                const SizedBox(width: 10),
                Text(e.$3,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? DsColors.navyDeep : DsColors.text2)),
              ]),
            ),
          ),
        ),
      );
    }

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 0, 18),
        child: SizedBox(
          width: 220,
          child: DsCard(
            padding: const EdgeInsets.all(12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: DsSectionLabel('Alerts'),
                  ),
                  for (final e in sectionItems) item(e),
                  if (scope.isAdmin) ...[
                    const Padding(
                        padding: EdgeInsets.fromLTRB(8, 16, 8, 8),
                        child: DsSectionLabel('System (admin)')),
                    for (final e in systemItems) item(e),
                  ],
                ]),
          ),
        ),
      ),
      Expanded(
        child: KeyedSubtree(
          key: ValueKey(tab),
          child: switch (tab) {
            _SettingsTab.mail => const _MailSettings(),
            _SettingsTab.scheduling => const _SchedulingSettings(),
            _SettingsTab.imports => const _ImportHistory(),
            _SettingsTab.outbox => const _MailLog(),
            _SettingsTab.activity => const _ActivityLog(system: false),
            _SettingsTab.holidays => const _HolidaysAdmin(),
            _SettingsTab.security => const _LoginSecurity(),
            _SettingsTab.system => const _SystemStatus(),
          },
        ),
      ),
    ]);
  }
}

/// Loads /settings once and offers save() for a subset of keys.
mixin _SettingsData<T extends StatefulWidget> on State<T> {
  Map<String, dynamic> values = {};
  bool loading = true;
  bool saving = false;

  Future<void> loadSettings() async {
    final r = await guard(
        context, () => AppScope.read(context).api.getJson('/settings'));
    if (r != null && mounted) {
      setState(() {
        values = Map<String, dynamic>.from(r['data'] as Map);
        loading = false;
      });
      onLoaded();
    }
  }

  void onLoaded() {}

  Future<bool> saveSettings(Map<String, dynamic> changes) async {
    setState(() => saving = true);
    final r = await guard(
        context,
        () => AppScope.read(context)
            .api
            .putJson('/settings', {'values': changes}));
    if (!mounted) return false;
    setState(() => saving = false);
    if (r == null) return false;
    setState(() => values = Map<String, dynamic>.from(r['data'] as Map));
    final re = intFrom(r['recalculated']) ?? 0;
    AppToast.success(context,
        re > 0 ? 'Saved · $re open PO(s) re-planned' : 'Settings saved');
    return true;
  }
}

class _MailSettings extends StatefulWidget {
  const _MailSettings();
  @override
  State<_MailSettings> createState() => _MailSettingsState();
}

class _MailSettingsState extends State<_MailSettings> with _SettingsData {
  Map<String, dynamic>? status;
  List<Map<String, dynamic>>? members;
  final Set<int> _toggling = {};
  final extra = TextEditingController();
  TimeOfDay time = const TimeOfDay(hour: 8, minute: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(loadSettings());
      unawaited(_status());
      unawaited(_members());
    });
  }

  Future<void> _members() async {
    final r = await guard(context,
        () => AppScope.read(context).api.getJson('/settings/mail/members'));
    if (r != null && mounted) {
      setState(() => members = (r['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    }
  }

  // The same switch as "Daily shipment email" in that person's Profile.
  Future<void> _setReceives(Map<String, dynamic> m, bool on) async {
    final scope = AppScope.read(context);
    final id = intFrom(m['id'])!;
    setState(() {
      _toggling.add(id);
      m['receiveDailyMail'] = on;
    });
    final r = await guard(
        context,
        () => scope.api
            .patchJson('/settings/mail/members/$id', {'receiveDailyMail': on}));
    if (!mounted) return;
    setState(() {
      _toggling.remove(id);
      if (r == null) m['receiveDailyMail'] = !on;
    });
    if (r != null) {
      if (id == intFrom(scope.me['id'])) {
        scope.onMeChanged({'receiveDailyMail': on});
      }
      unawaited(_status());
    }
  }

  @override
  void onLoaded() {
    extra.text = '${values['mail.extraRecipients'] ?? ''}';
    final parts = '${values['mail.dailyTime'] ?? '08:30'}'.split(':');
    time = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 8,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '30') ?? 30);
  }

  Future<void> _status() async {
    final r = await guard(context,
        () => AppScope.read(context).api.getJson('/settings/mail/status'));
    if (r != null && mounted) setState(() => status = r);
  }

  String get _time =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _sendNow(String kind, bool toSelf) async {
    final api = AppScope.read(context).api;
    if (!toSelf &&
        !await confirmAction(context,
            title:
                'Send the ${kind == 'daily' ? 'daily report' : 'monthly report'} to everyone now?',
            message:
                'It goes to the ${status?['recipients']?.length ?? 0} recipient(s) listed below.',
            confirmLabel: 'Send')) {
      return;
    }
    if (!mounted) return;
    final r = await guard(
        context,
        () => api.postJson(
            '/settings/mail/send-now', {'kind': kind, 'toSelf': toSelf}));
    if (r == null || !mounted) return;
    final s = '${r['status']}';
    if (s == 'sent') {
      AppToast.success(context,
          'Sent to ${toSelf ? 'you' : '${r['recipients']} recipient(s)'}');
    } else if (s == 'pending_config') {
      AppToast.info(context,
          'Recorded in the mail log, but SMTP is not configured on the server (backend/.env)');
    } else if (s == 'disabled') {
      AppToast.info(
          context, 'Email is switched off for this section — turn it on first');
    } else {
      AppToast.error(context, 'Not sent ($s) — see the Mail log');
    }
    unawaited(_status());
  }

  Future<void> _preview(String kind) async {
    final api = AppScope.read(context).api;
    final r = await guard(
        context, () => api.getJson('/settings/mail/preview?kind=$kind'));
    if (r == null) return;
    final blob = html.Blob(['${r['html']}'], 'text/html');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const PageBody(children: [
        _CardGhost('Daily shipment email', Icons.mail_outline,
            lines: 2, switches: 2, fields: [170, null], save: true),
        SizedBox(height: 16),
        _CardGhost('Recipients', Icons.groups_outlined, lines: 1, tags: 4),
        SizedBox(height: 16),
        _CardGhost('Try it', Icons.science_outlined, buttons: 5),
      ]);
    }
    final configured = status?['configured'] == true;
    final recipients =
        (status?['recipients'] as List? ?? const []).cast<dynamic>();
    final memberEmails = {
      for (final m in members ?? const <Map<String, dynamic>>[])
        '${m['email']}'.trim().toLowerCase()
    };
    final extraOnly = [
      for (final r in recipients)
        if (!memberEmails.contains('$r'.toLowerCase())) '$r'
    ];
    final runs = (status?['lastRuns'] as List? ?? const []).cast<Map>();
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('Daily shipment email', icon: Icons.mail_outline),
          const SizedBox(height: 4),
          const Text(
              'Every working day (Mon–Fri, not on company holidays) the system emails a summary: overdue, due soon, '
              'arriving this week, and every open PO by step. On the last working day of the month it also sends the monthly report.',
              style: DsType.meta),
          const SizedBox(height: 12),
          if (status != null && !configured)
            const InfoStrip(
              icon: Icons.warning_amber_rounded,
              color: DsColors.amberFg,
              text:
                  'SMTP is not configured on the server yet (SMTP_HOST / SMTP_FROM in backend/.env). '
                  'Mails are kept in the Mail log until it is.',
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: values['mail.enabled'] == true,
            title: const Text('Send emails for this section',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Off = nothing is emailed (still recorded in the Mail log).',
                style: DsType.metaSm),
            onChanged: saving
                ? null
                : (v) => unawaited(
                    saveSettings({'mail.enabled': v}).then((_) => _status())),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: values['mail.monthlyEnabled'] == true,
            title: const Text('Send the monthly report on the last working day',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            onChanged: saving
                ? null
                : (v) => unawaited(saveSettings({'mail.monthlyEnabled': v})),
          ),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            SizedBox(
              width: 170,
              child: DsLabeledField(
                label: 'Send at (Thai time)',
                child: InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                        context: context, initialTime: time);
                    if (picked != null) {
                      setState(() => time = picked);
                      unawaited(saveSettings({'mail.dailyTime': _time}));
                    }
                  },
                  child: InputDecorator(
                      decoration: dsInput(icon: Icons.schedule),
                      child: Text(_time)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DsLabeledField(
                label:
                    'Extra recipients (comma separated)',
                child: TextField(
                    controller: extra,
                    decoration: dsInput(
                        hint:
                            'arunrat@thaiparker.co.th, natthakorn@thaiparker.co.th')),
              ),
            ),
            const SizedBox(width: 10),
            DsPrimaryButton(
              label: 'Save',
              icon: Icons.save_outlined,
              height: 42,
              onPressed: saving
                  ? null
                  : () => unawaited(
                      saveSettings({'mail.extraRecipients': extra.text})
                          .then((_) => _status())),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Recipients (${recipients.length})',
              icon: Icons.groups_outlined),
          const SizedBox(height: 6),
          const Text(
              'Switch the daily email on or off for anyone in the section — the same switch each person has in Profile › Email reminders.',
              style: DsType.meta),
          const SizedBox(height: 8),
          if (members == null)
            DsSkeletonRows(
              rows: 4,
              rowHeight: 52,
              padding: EdgeInsets.zero,
              columns: [
                DsSkelCol((i) => DsSkel.lines(
                    DsSkel.vary(i, 160), DsSkel.vary(i + 3, 220))),
                DsSkelCol((i) => DsSkel.tag(DsSkel.vary(i + 1, 70, .3)),
                    width: 130),
                DsSkelCol((_) => DsSkel.chip(40, height: 22),
                    width: 60, align: Alignment.centerRight),
              ],
            )
          else if (members!.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Nobody in this section yet', style: DsType.meta))
          else
            for (final m in members!)
              Container(
                height: 52,
                decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: DsColors.lineSoft))),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m['displayName'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.rowTitle),
                          Text(
                              m['hasEmail'] == true
                                  ? '${m['email']}'
                                  : 'No email address',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.metaSm),
                        ]),
                  ),
                  SizedBox(
                      width: 130,
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: DsTag('${m['roleName'] ?? m['roleCode']}'))),
                  Switch(
                    value: m['receiveDailyMail'] == true,
                    onChanged: m['hasEmail'] != true ||
                            _toggling.contains(intFrom(m['id']))
                        ? null
                        : (v) => unawaited(_setReceives(m, v)),
                  ),
                ]),
              ),
          const SizedBox(height: 12),
          const DsSectionLabel('Extra recipients'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in extraOnly) DsTag(r),
            if (extraOnly.isEmpty)
              const Text('None — add addresses in the card above',
                  style: DsType.meta),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('Try it', icon: Icons.science_outlined),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            DsOutlineButton(
                label: 'Preview daily email',
                icon: Icons.visibility_outlined,
                height: 38,
                onPressed: () => _preview('daily')),
            DsOutlineButton(
                label: 'Preview monthly email',
                icon: Icons.visibility_outlined,
                height: 38,
                onPressed: () => _preview('monthly')),
            DsOutlineButton(
              label: 'Send a test email to me',
              icon: Icons.send_outlined,
              height: 38,
              onPressed: () async {
                final r = await guard(
                    context,
                    () => AppScope.read(context)
                        .api
                        .postJson('/settings/mail/test', {}));
                if (r != null && context.mounted) {
                  AppToast.info(
                      context,
                      r['status'] == 'sent'
                          ? 'Test email sent to ${r['to']}'
                          : 'Not sent: ${r['status']}');
                }
              },
            ),
            DsOutlineButton(
                label: 'Send today\'s report to me',
                icon: Icons.forward_to_inbox,
                height: 38,
                onPressed: () => _sendNow('daily', true)),
            DsPrimaryButton(
                label: 'Send today\'s report to everyone',
                icon: Icons.campaign_outlined,
                height: 38,
                onPressed: () => _sendNow('daily', false)),
          ]),
          if (runs.isNotEmpty) ...[
            const SizedBox(height: 16),
            const DsSectionLabel('Recent automatic runs'),
            const SizedBox(height: 6),
            for (final r in runs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(
                      width: 90,
                      child: Text('${r['runType']}',
                          style: mono(size: 11.5, weight: FontWeight.w700))),
                  SizedBox(
                      width: 110,
                      child: Text(fmtDate(r['runDate']), style: DsType.meta)),
                  SizedBox(width: 120, child: DsTag('${r['status']}')),
                  Expanded(
                      child:
                          Text('${r['detail'] ?? ''}', style: DsType.metaSm)),
                ]),
              ),
          ],
        ]),
      ),
    ]);
  }
}

class _SchedulingSettings extends StatefulWidget {
  const _SchedulingSettings();
  @override
  State<_SchedulingSettings> createState() => _SchedulingSettingsState();
}

class _SchedulingSettingsState extends State<_SchedulingSettings>
    with _SettingsData {
  final dueSoon = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(loadSettings()));
  }

  @override
  void dispose() {
    dueSoon.dispose();
    super.dispose();
  }

  @override
  void onLoaded() {
    dueSoon.text = '${values['alert.dueSoonDays']}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const PageBody(children: [
        _CardGhost('"Due soon" alert', Icons.timelapse,
            lines: 1, fields: [220], save: true),
      ]);
    }
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('"Due soon" alert', icon: Icons.timelapse),
          const SizedBox(height: 4),
          const Text(
              'A step turns "due soon" this many days before its due date — on the dashboard, in the PO list and in the daily email.',
              style: DsType.meta),
          const SizedBox(height: 12),
          Wrap(
              spacing: 14,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 220,
                  child: DsLabeledField(
                    label: 'Days ahead',
                    child: TextField(
                      controller: dueSoon,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3)
                      ],
                      decoration: dsInput(hint: '3'),
                    ),
                  ),
                ),
                DsPrimaryButton(
                  label: 'Save',
                  icon: Icons.save_outlined,
                  height: 42,
                  onPressed: saving
                      ? null
                      : () => unawaited(saveSettings({
                            'alert.dueSoonDays':
                                int.tryParse(dueSoon.text) ?? 0,
                          })),
                ),
              ]),
        ]),
      ),
    ]);
  }
}

typedef _PageFetch = Future<(List<Map<String, dynamic>>, int)?> Function(
    int page, int pageSize);

/// Rows fetched from the server a page at a time. With [fill] the list takes
/// the height it is given and a page is however many [rowHeight] rows fit, so
/// the card ends at the bottom of the screen and you turn pages instead of
/// scrolling; otherwise a page is [pageSize] rows.
class _PagedRows extends StatefulWidget {
  const _PagedRows({
    super.key,
    required this.fetch,
    required this.rowBuilder,
    required this.rowHeight,
    required this.skeleton,
    this.fill = false,
    this.pageSize = 15,
    this.empty = 'Nothing yet',
    this.reloadKey,
    this.onTotal,
  });

  final _PageFetch fetch;
  final Widget Function(Map<String, dynamic> row) rowBuilder;
  final double rowHeight;
  final List<DsSkelCol> skeleton;
  final bool fill;
  final int pageSize;
  final String empty;

  /// Change it (a new search, a filter) to go back to page 1 and reload.
  final Object? reloadKey;
  final ValueChanged<int>? onTotal;

  @override
  State<_PagedRows> createState() => _PagedRowsState();
}

class _PagedRowsState extends State<_PagedRows> {
  // PaginationBar's own height, kept free even when it hides itself, so the
  // page size does not change as the bar comes and goes.
  static const _barHeight = 57.0;

  List<Map<String, dynamic>>? rows;
  int total = 0;
  int page = 1;

  /// Null until a [fill] list knows its height.
  int? size;
  int _seq = 0;
  Timer? _refit;

  @override
  void initState() {
    super.initState();
    if (!widget.fill) {
      size = widget.pageSize;
      WidgetsBinding.instance.addPostFrameCallback((_) => reload());
    }
  }

  @override
  void didUpdateWidget(_PagedRows old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) {
      page = 1;
      reload();
    }
  }

  @override
  void dispose() {
    _refit?.cancel();
    super.dispose();
  }

  /// Fetches the current page again.
  void reload() => unawaited(_load());

  Future<void> _load() async {
    final n = size;
    if (n == null) return;
    final seq = ++_seq;
    final r = await widget.fetch(page, n);
    if (!mounted || seq != _seq || r == null) return;
    final pages = max(1, (r.$2 / n).ceil());
    if (page > pages) {
      // Rows went away (or the page grew) — show the last page instead.
      page = pages;
      return _load();
    }
    setState(() {
      rows = r.$1;
      total = r.$2;
    });
    widget.onTotal?.call(r.$2);
  }

  void _fit(double height) {
    final n = max(1, (height / widget.rowHeight + 0.001).floor());
    if (n == size) return;
    final first = (page - 1) * (size ?? n);
    final firstFit = size == null;
    size = n;
    page = first ~/ n + 1;
    _refit?.cancel();
    // The first fit loads straight away; a window being resized waits until
    // it settles.
    _refit = Timer(firstFit ? Duration.zero : const Duration(milliseconds: 200),
        () {
      if (mounted) reload();
    });
  }

  Widget _list(int visible) {
    if (rows == null) {
      return DsSkeletonRows(
          rows: visible,
          rowHeight: widget.rowHeight,
          padding: EdgeInsets.zero,
          columns: widget.skeleton);
    }
    if (rows!.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(widget.empty, style: DsType.meta));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final r in rows!)
        SizedBox(height: widget.rowHeight, child: widget.rowBuilder(r)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final bar = PaginationBar(
      page: page - 1,
      totalItems: total,
      pageSize: size ?? widget.pageSize,
      onChanged: (p) {
        page = p + 1;
        reload();
      },
    );
    if (!widget.fill) {
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [_list(widget.pageSize), bar]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: LayoutBuilder(builder: (context, box) {
          _fit(box.maxHeight);
          return ClipRect(
            child: Align(alignment: Alignment.topCenter, child: _list(size!)),
          );
        }),
      ),
      SizedBox(height: _barHeight, child: bar),
    ]);
  }
}

/// A settings tab that is one card as tall as the screen — the logs.
class _FillCard extends StatelessWidget {
  const _FillCard({required this.children});

  /// The card's content; one of them should be an [Expanded] list.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      child: DsCard(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> r) =>
    (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

class _ImportHistory extends StatelessWidget {
  const _ImportHistory();

  @override
  Widget build(BuildContext context) {
    return _FillCard(children: [
      const DsCardTitle('Excel uploads', icon: Icons.upload_file),
      const SizedBox(height: 4),
      const Text(
          'Every uploaded file is kept exactly as it was, and every column of every PO line is stored with the PO.',
          style: DsType.meta),
      const SizedBox(height: 12),
      Expanded(
        child: _PagedRows(
          fill: true,
          rowHeight: 56,
          empty: 'No upload yet',
          fetch: (page, size) async {
            final r = await guard(
                context,
                () => AppScope.read(context).api.getJson(
                    '/pos/import/batches${qs({'page': page, 'pageSize': size})}'));
            return r == null ? null : (_rowsOf(r), intFrom(r['total']) ?? 0);
          },
          skeleton: [
            DsSkelCol((_) => DsSkel.icon(22), width: 34),
            DsSkelCol((i) =>
                DsSkel.lines(DsSkel.vary(i, 210), DsSkel.vary(i + 3, 300))),
            DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 1, 220, .2)),
                width: 260),
            DsSkelCol((_) => DsSkel.icon(18),
                width: 36, align: Alignment.center),
          ],
          rowBuilder: (b) => Container(
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
            child: Row(children: [
              const Icon(Icons.description_outlined, color: DsColors.greenFg),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${b['fileName']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.rowTitle),
                      Text(
                          '${fmtDateTime(b['createdAt'])} · ${b['uploadedBy'] ?? '-'} · sheet "${b['sheetName'] ?? '-'}"',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsType.metaSm),
                    ]),
              ),
              SizedBox(
                  width: 260,
                  child: Text(
                      '${b['totalRows']} lines · ${b['created']} POs created · ${b['skipped']} skipped',
                      style: DsType.meta)),
              SizedBox(
                width: 36,
                child: b['hasFile'] == true
                    ? DsIconButton(
                        icon: Icons.download_outlined,
                        tooltip: 'Download the original file',
                        onTap: () => unawaited(downloadFromApi(
                            context,
                            '/pos/import/batches/${b['id']}/file',
                            '${b['fileName']}')),
                      )
                    : null,
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _MailLog extends StatefulWidget {
  const _MailLog();
  @override
  State<_MailLog> createState() => _MailLogState();
}

class _MailLogState extends State<_MailLog> {
  final _rows = GlobalKey<_PagedRowsState>();

  Future<void> open(int id) async {
    final r = await guard(context,
        () => AppScope.read(context).api.getJson('/settings/outbox/$id'));
    if (r == null) return;
    final url = html.Url.createObjectUrlFromBlob(
        html.Blob(['${r['html']}'], 'text/html'));
    html.window.open(url, '_blank');
  }

  @override
  Widget build(BuildContext context) {
    (Color, Color) colors(String s) => switch (s) {
          'sent' => (DsColors.greenFg, DsColors.greenBg),
          'failed' => (DsColors.redFg, DsColors.redBg),
          'pending_config' || 'queued' => (DsColors.amberFg, DsColors.amberBg),
          _ => (DsColors.muted, DsColors.chip),
        };
    return _FillCard(children: [
      DsCardTitle('Mail log',
          icon: Icons.outbox_outlined,
          trailing: DsIconButton(
              icon: Icons.refresh,
              tooltip: 'Reload',
              onTap: () => _rows.currentState?.reload())),
      const SizedBox(height: 10),
      Expanded(
        child: _PagedRows(
          key: _rows,
          fill: true,
          rowHeight: 54,
          empty: 'No mail yet',
          fetch: (page, size) async {
            final r = await guard(
                context,
                () => AppScope.read(context).api.getJson(
                    '/settings/outbox${qs({'page': page, 'pageSize': size})}'));
            return r == null ? null : (_rowsOf(r), intFrom(r['total']) ?? 0);
          },
          skeleton: [
            DsSkelCol((_) => DsSkel.line(100, height: 9), width: 130),
            DsSkelCol((i) => DsSkel.line(DsSkel.vary(i, 84, .3)), width: 130),
            DsSkelCol((i) =>
                DsSkel.lines(DsSkel.vary(i + 2, 300), DsSkel.vary(i + 5, 180))),
            DsSkelCol((i) => DsSkel.tag(DsSkel.vary(i + 1, 42, .3)),
                width: 60, align: Alignment.centerRight),
          ],
          rowBuilder: (m) {
            final error = m['error'];
            return InkWell(
              onTap: () => open(intFrom(m['id'])!),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: DsColors.lineSoft))),
                child: Row(children: [
                  SizedBox(
                      width: 130,
                      child: Text(fmtDateTime(m['createdAt']),
                          style: DsType.metaSm)),
                  SizedBox(
                      width: 130,
                      child: Text('${m['type']}',
                          style: mono(size: 11, weight: FontWeight.w600))),
                  Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m['subject']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.rowTitle),
                          // A failed mail shows why instead of whom; the
                          // tooltip has both.
                          Tooltip(
                            message: error == null
                                ? '${m['to'] ?? '-'}'
                                : '${m['to'] ?? '-'}\n$error',
                            child: Text(
                                error == null
                                    ? '${m['to'] ?? '-'}'
                                    : '$error',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: error == null
                                    ? DsType.metaSm
                                    : const TextStyle(
                                        fontSize: 11, color: DsColors.redFg)),
                          ),
                        ]),
                  ),
                  DsTag('${m['status']}',
                      color: colors('${m['status']}').$1,
                      bg: colors('${m['status']}').$2),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _ActivityLog extends StatefulWidget {
  const _ActivityLog({required this.system});

  /// The whole-system log under System status: 15 a page inside that page.
  /// Otherwise this section's log, as tall as the screen.
  final bool system;
  @override
  State<_ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends State<_ActivityLog> {
  int total = 0;
  bool securityOnly = false;
  String q = '';
  final search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<(List<Map<String, dynamic>>, int)?> _fetch(int page, int size) async {
    final base = widget.system ? '/admin/audit' : '/settings/audit';
    final r = await guard(
        context,
        () => AppScope.read(context).api.getJson('$base${qs({
                  'q': q,
                  'page': page,
                  'pageSize': size,
                  if (widget.system && securityOnly) 'security': 'true',
                })}'));
    return r == null ? null : (_rowsOf(r), intFrom(r['total']) ?? 0);
  }

  Widget _row(Map<String, dynamic> a) => Container(
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
        child: Row(children: [
          SizedBox(
              width: 130,
              child: Text(fmtDateTime(a['at']), style: DsType.metaSm)),
          SizedBox(
              width: 140,
              child: Text('${a['actorName'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsType.rowTitle)),
          SizedBox(
            width: 170,
            child: Text('${a['action']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: '${a['action']}'.contains('FAIL') ||
                            '${a['action']}'.contains('LOCK')
                        ? DsColors.redFg
                        : DsColors.navyDeep)),
          ),
          SizedBox(
              width: 160,
              child: Text('${a['entityType']} ${a['entityId'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DsType.meta)),
          Expanded(
              child: Text('${a['detail'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: DsType.metaSm)),
          SizedBox(
              width: 120,
              child: Text('${a['ip'] ?? ''}',
                  textAlign: TextAlign.right, style: DsType.metaSm)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final rows = _PagedRows(
      fill: !widget.system,
      pageSize: 15,
      rowHeight: 44,
      empty: 'No activity found',
      reloadKey: (q, securityOnly),
      onTotal: (n) {
        if (n != total) setState(() => total = n);
      },
      fetch: _fetch,
      rowBuilder: _row,
      skeleton: [
        DsSkelCol((_) => DsSkel.line(100, height: 9), width: 130),
        DsSkelCol((i) => DsSkel.line(DsSkel.vary(i, 92), height: 11),
            width: 140),
        DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 3, 120)), width: 170),
        DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 1, 96)), width: 160),
        DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 4, 320), height: 9)),
        DsSkelCol((_) => DsSkel.line(78, height: 9),
            width: 120, align: Alignment.centerRight),
      ],
    );
    final head = [
      DsCardTitle(
          widget.system
              ? 'Whole-system activity log'
              : 'Activity log — this section',
          icon: Icons.history),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: search,
            decoration: dsInput(
                hint: 'Search action, user, ID, IP…', icon: Icons.search),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () {
                if (mounted) setState(() => q = search.text.trim());
              });
            },
          ),
        ),
        if (widget.system) ...[
          const SizedBox(width: 10),
          FilterChip(
            label: const Text('Security events only'),
            selected: securityOnly,
            onSelected: (v) => setState(() => securityOnly = v),
          ),
        ],
        const Spacer(),
        Text(plural(total, 'entry', 'entries'), style: DsType.meta),
      ]),
      const SizedBox(height: 10),
    ];
    if (!widget.system) {
      return _FillCard(children: [...head, Expanded(child: rows)]);
    }
    return DsCard(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [...head, rows]),
    );
  }
}

class _HolidaysAdmin extends StatefulWidget {
  const _HolidaysAdmin();
  @override
  State<_HolidaysAdmin> createState() => _HolidaysAdminState();
}

class _HolidaysAdminState extends State<_HolidaysAdmin> {
  int year = DateTime.now().year;
  List<Map<String, dynamic>>? rows;
  bool externalConfigured = true;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final seq = ++_seq;
    final r = await guard(context,
        () => AppScope.read(context).api.getJson('/admin/holidays?year=$year'));
    if (r != null && mounted && seq == _seq) {
      setState(() {
        rows = _rowsOf(r);
        externalConfigured = r['externalConfigured'] != false;
      });
    }
  }

  void _goYear(int y) {
    setState(() {
      year = y;
      rows = null;
    });
    unawaited(load());
  }

  Future<void> add() async {
    final api = AppScope.read(context).api;
    final now = DateTime.now();
    DateTime date = DateTime(year, now.month, min(now.day, 28));
    final name = TextEditingController();
    String? error;
    bool busy = false;
    final added = await showGlassDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AppDialog(
                title: 'Add holiday',
                icon: Icons.beach_access_outlined,
                width: 420,
                body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DsLabeledField(
                        label: 'Date',
                        child: InkWell(
                          onTap: () async {
                            final p = await showDatePicker(
                                context: ctx,
                                initialDate: date,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2035, 12, 31));
                            if (p != null) {
                              setState(() {
                                date = p;
                                error = null;
                              });
                            }
                          },
                          child: InputDecorator(
                              decoration: dsInput(icon: Icons.event),
                              child: Text(intl.DateFormat('EEEE d MMMM yyyy')
                                  .format(date))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DsLabeledField(
                          label: 'Name (optional)',
                          child: TextField(
                              controller: name,
                              decoration: dsInput(hint: 'Songkran'))),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        InfoStrip(
                            text: error!,
                            icon: Icons.error_outline,
                            color: DsColors.redFg),
                      ],
                    ]),
                actions: [
                  DsOutlineButton(
                      label: 'Cancel',
                      height: 40,
                      onPressed: () => Navigator.pop(ctx)),
                  DsPrimaryButton(
                    label: busy ? 'Adding…' : 'Add',
                    height: 40,
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              await api.postJson('/admin/holidays', {
                                'date': isoDate(date),
                                'name': name.text.trim()
                              });
                              if (ctx.mounted) Navigator.pop(ctx, date);
                            } on ApiException catch (e) {
                              if (ctx.mounted) {
                                setState(() {
                                  busy = false;
                                  error = friendlyError(e.message);
                                });
                              }
                            }
                          },
                  ),
                ],
              )),
    );
    name.dispose();
    if (added == null || !mounted) return;
    AppToast.success(context,
        'Holiday added · ${intl.DateFormat('d MMM yyyy').format(added)}');
    // Show the year the new day is in.
    _goYear(added.year);
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final list = rows ?? const <Map<String, dynamic>>[];
    final fromDb = list.where((h) => h['source'] == 'external').length;
    return PageBody(children: [
      _HolidayDbCard(onSaved: load),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: DsCardTitle('Company holidays',
                    icon: Icons.beach_access_outlined)),
            DsIconButton(
                icon: Icons.chevron_left,
                tooltip: 'Previous year',
                onTap: () => _goYear(year - 1)),
            Text('$year', style: DsType.cardTitle),
            DsIconButton(
                icon: Icons.chevron_right,
                tooltip: 'Next year',
                onTap: () => _goYear(year + 1)),
            const SizedBox(width: 10),
            DsPrimaryButton(
                label: 'Add holiday',
                icon: Icons.add,
                height: 36,
                onPressed: add),
          ]),
          const SizedBox(height: 4),
          const Text(
              'Every day off this year: the ones from the holiday database (read-only — change them in SAR) and the extra days added here. '
              'On these days no daily email is sent, and the calendar greys them out.',
              style: DsType.meta),
          if (rows != null) ...[
            const SizedBox(height: 6),
            Text(
                '${plural(list.length, 'day', 'days')} · $fromDb from the holiday database · ${list.length - fromDb} added here',
                style: DsType.metaSm),
          ],
          if (rows != null && !externalConfigured) ...[
            const SizedBox(height: 10),
            const InfoStrip(
                icon: Icons.cloud_off_outlined,
                color: DsColors.amberFg,
                text:
                    'The holiday database cannot be read right now — only the days added here are listed.'),
          ],
          const SizedBox(height: 10),
          if (rows == null)
            DsSkeletonRows(
              rows: 6,
              rowHeight: 44,
              padding: EdgeInsets.zero,
              columns: [
                DsSkelCol((_) => DsSkel.icon(18), width: 34),
                DsSkelCol((i) => DsSkel.line(DsSkel.vary(i, 170)), width: 230),
                DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 3, 140))),
                DsSkelCol((i) => DsSkel.tag(DsSkel.vary(i + 1, 80, .3)),
                    width: 130),
                DsSkelCol((_) => DsSkel.icon(18),
                    width: 36, align: Alignment.center),
              ],
            ),
          if (rows != null && list.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No holidays this year', style: DsType.meta)),
          for (final h in list)
            Container(
              height: 44,
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
              child: Row(children: [
                SizedBox(
                  width: 34,
                  child: Icon(Icons.event_busy,
                      size: 18,
                      color: h['source'] == 'external'
                          ? DsColors.icon
                          : DsColors.amberFg),
                ),
                SizedBox(
                  width: 230,
                  child: Text(
                      intl.DateFormat('EEE d MMMM yyyy')
                          .format(DateTime.parse('${h['date']}')),
                      style: DsType.rowTitle),
                ),
                Expanded(
                  child: Text('${h['name'] ?? '-'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DsType.meta),
                ),
                SizedBox(
                  width: 130,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: h['source'] == 'external'
                        ? const DsTag('Holiday DB')
                        : const DsTag('Added here',
                            color: DsColors.amberFg, bg: DsColors.amberBg),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: h['source'] == 'external'
                      ? null
                      : DsIconButton(
                          icon: Icons.delete_outline,
                          color: DsColors.redFg,
                          tooltip: 'Remove',
                          onTap: () async {
                            if (await guard(
                                    context,
                                    () => api.deleteJson(
                                        '/admin/holidays/${h['id']}'),
                                    success: 'Holiday removed') !=
                                null) {
                              unawaited(load());
                            }
                          },
                        ),
                ),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// The external holiday DB (SAR · Master_Holiday), shared with RAP.
/// Credentials and port live in backend/.env; host/database/table are edited
/// here, and blank fields fall back to .env.
class _HolidayDbCard extends StatefulWidget {
  const _HolidayDbCard({this.onSaved});

  /// After a save, so the holiday list reads the new source.
  final VoidCallback? onSaved;
  @override
  State<_HolidayDbCard> createState() => _HolidayDbCardState();
}

class _HolidayDbCardState extends State<_HolidayDbCard> {
  final host = TextEditingController();
  final database = TextEditingController();
  final table = TextEditingController();
  bool enabled = true;
  Map<String, dynamic> defaults = {};
  bool credentialsSet = true;
  bool loaded = false;
  bool saving = false;
  bool testing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  @override
  void dispose() {
    host.dispose();
    database.dispose();
    table.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> r) {
    host.text = '${r['host'] ?? ''}';
    database.text = '${r['database'] ?? ''}';
    table.text = '${r['table'] ?? ''}';
    enabled = r['enabled'] != false;
    defaults = Map<String, dynamic>.from(r['defaults'] as Map? ?? const {});
    credentialsSet = r['credentialsSet'] == true;
    loaded = true;
  }

  Future<void> load() async {
    final r = await guard(
        context, () => AppScope.read(context).api.getJson('/admin/holiday-db'));
    if (r != null && mounted) setState(() => _apply(r));
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final r = await guard(
        context,
        () => AppScope.read(context).api.putJson('/admin/holiday-db', {
              'host': host.text.trim(),
              'database': database.text.trim(),
              'table': table.text.trim(),
              'enabled': enabled,
            }),
        success: 'Holiday database settings saved');
    if (!mounted) return;
    setState(() {
      saving = false;
      if (r != null) _apply(r);
    });
    if (r != null) widget.onSaved?.call();
  }

  Future<void> _test() async {
    setState(() => testing = true);
    try {
      final r =
          await AppScope.read(context).api.getJson('/admin/holiday-db/verify');
      if (!mounted) return;
      final msg = '${r['message'] ?? (r['ok'] == true ? 'Connected' : 'Failed')}';
      r['ok'] == true
          ? AppToast.success(context, msg)
          : AppToast.error(context, msg);
    } on ApiException catch (e) {
      if (mounted) AppToast.error(context, friendlyError(e.message));
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  String _hint(String key, String fallback) {
    final d = '${defaults[key] ?? ''}';
    return d.isEmpty ? fallback : '$d (from .env)';
  }

  @override
  Widget build(BuildContext context) {
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
              child: DsCardTitle('Holiday database (external)',
                  icon: Icons.storage_outlined)),
          DsOutlineButton(
              label: testing ? 'Testing…' : 'Test connection',
              icon: Icons.wifi_tethering,
              height: 36,
              onPressed: testing || !loaded ? null : _test),
          const SizedBox(width: 8),
          DsPrimaryButton(
              label: saving ? 'Saving…' : 'Save',
              icon: Icons.save_outlined,
              height: 36,
              onPressed: saving || !loaded ? null : _save),
        ]),
        const SizedBox(height: 4),
        const Text(
            'Company holidays come from the same database as RAP (SAR · Master_Holiday). '
            'User, password and port are set in backend/.env; host, database and table can be changed here.',
            style: DsType.meta),
        if (loaded && !credentialsSet) ...[
          const SizedBox(height: 10),
          const InfoStrip(
              icon: Icons.key_off_outlined,
              color: DsColors.amberFg,
              text:
                  'HOLIDAY_SQL_USER / HOLIDAY_SQL_PASSWORD are not set in backend/.env yet.'),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: enabled,
          title: const Text('Read holidays from this database',
              style: TextStyle(fontSize: 13)),
          onChanged: (v) => setState(() => enabled = v),
        ),
        Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(
              width: 260,
              child: DsLabeledField(
                  label: 'Host / IP',
                  child: TextField(
                      controller: host,
                      decoration: dsInput(hint: _hint('host', '10.0.0.5'))))),
          SizedBox(
              width: 220,
              child: DsLabeledField(
                  label: 'Database',
                  child: TextField(
                      controller: database,
                      decoration: dsInput(hint: _hint('database', 'SAR'))))),
          SizedBox(
              width: 220,
              child: DsLabeledField(
                  label: 'Table',
                  child: TextField(
                      controller: table,
                      decoration:
                          dsInput(hint: _hint('table', 'Master_Holiday'))))),
        ]),
      ]),
    );
  }
}

class _LoginSecurity extends StatefulWidget {
  const _LoginSecurity();
  @override
  State<_LoginSecurity> createState() => _LoginSecurityState();
}

class _LoginSecurityState extends State<_LoginSecurity> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final r = await guard(context,
        () => AppScope.read(context).api.getJson('/auth/login-blocks'));
    if (r != null && mounted) setState(() => data = r);
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final ips = (data?['data'] as List? ?? const []).cast<Map>();
    final accounts = (data?['accounts'] as List? ?? const []).cast<Map>();
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Blocked sign-ins',
              icon: Icons.shield_outlined,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                DsIconButton(
                    icon: Icons.refresh, tooltip: 'Reload', onTap: load),
                if (ips.isNotEmpty || accounts.isNotEmpty)
                  DsOutlineButton(
                    label: 'Release all',
                    height: 34,
                    onPressed: () async {
                      if (await guard(context,
                              () => api.deleteJson('/auth/login-blocks'),
                              success: 'Everything released') !=
                          null) {
                        unawaited(load());
                      }
                    },
                  ),
              ])),
          const SizedBox(height: 4),
          const Text(
              '5 wrong passwords lock an account for 15 minutes; 5 failures from one computer block it for 15 minutes. '
              'Release here if a real user is stuck.',
              style: DsType.meta),
          const SizedBox(height: 14),
          const DsSectionLabel('Locked accounts'),
          if (accounts.isEmpty)
            const Padding(
                padding: EdgeInsets.all(10),
                child: Text('None', style: DsType.meta)),
          for (final a in accounts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_outline, color: DsColors.redFg),
              title: Text('${a['displayName']} · ${a['email']}',
                  style: DsType.rowTitle),
              subtitle: Text(
                  'until ${a['lockedUntil']} · from ${(a['ips'] as List).join(', ')}',
                  style: DsType.metaSm),
              trailing: DsOutlineButton(
                label: 'Unlock',
                height: 34,
                onPressed: () async {
                  if (await guard(
                          context,
                          () => api.postJson(
                              '/auth/login-blocks/accounts/${a['id']}/unlock',
                              {}),
                          success: 'Unlocked') !=
                      null) {
                    unawaited(load());
                  }
                },
              ),
            ),
          const SizedBox(height: 10),
          const DsSectionLabel('Blocked computers (IP)'),
          if (ips.isEmpty)
            const Padding(
                padding: EdgeInsets.all(10),
                child: Text('None', style: DsType.meta)),
          for (final ip in ips)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.computer, color: DsColors.amberFg),
              title: Text('${ip['ip']}',
                  style: mono(size: 12.5, weight: FontWeight.w700)),
              subtitle: Text(
                  'since ${ip['blockedAt']} · until ${ip['resetTime']}',
                  style: DsType.metaSm),
              trailing: DsOutlineButton(
                label: 'Release',
                height: 34,
                onPressed: () async {
                  if (await guard(
                          context,
                          () => api.deleteJson(
                              '/auth/login-blocks/${Uri.encodeComponent('${ip['ip']}')}'),
                          success: 'Released') !=
                      null) {
                    unawaited(load());
                  }
                },
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _SystemStatus extends StatefulWidget {
  const _SystemStatus();
  @override
  State<_SystemStatus> createState() => _SystemStatusState();
}

class _SystemStatusState extends State<_SystemStatus> {
  Map<String, dynamic>? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final r = await guard(
        context, () => AppScope.read(context).api.getJson('/admin/system'));
    if (r != null && mounted) setState(() => data = r);
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final d = data;
    final counts = (d?['counts'] as Map?) ?? const {};
    Widget kv(String k, String v, {bool ok = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(width: 200, child: Text(k, style: DsType.meta)),
            DsDot(ok ? DsColors.greenFg : DsColors.amberFg),
            const SizedBox(width: 8),
            Expanded(child: Text(v, style: DsType.rowTitle)),
          ]),
        );
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('System status',
              icon: Icons.dns_outlined,
              trailing: DsOutlineButton(
                label: 'Check SMTP connection',
                height: 34,
                onPressed: () async {
                  final r = await guard(
                      context, () => api.getJson('/admin/mail/verify'));
                  if (r != null && context.mounted) {
                    r['ok'] == true
                        ? AppToast.success(context, 'SMTP connection OK')
                        : AppToast.error(context, '${r['reason']}');
                  }
                },
              )),
          const SizedBox(height: 10),
          if (d == null) ...[
            // kv() rows, then the count tiles.
            DsSkeletonRows(
              rows: 6,
              rowHeight: 30,
              padding: EdgeInsets.zero,
              divider: false,
              fade: false,
              columns: [
                DsSkelCol((i) => DsSkel.line(DsSkel.vary(i, 100)), width: 200),
                DsSkelCol((_) => DsSkel.circle(8), width: 16),
                DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 3, 230), height: 11)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < 6; i++)
                Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: DsColors.subtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: DsColors.cardBorder)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DsSkel.box(DsSkel.vary(i, 34, .5), 20, radius: 5),
                        const SizedBox(height: 6),
                        DsSkel.line(DsSkel.vary(i + 2, 72), height: 9),
                      ]),
                ),
            ]),
          ] else ...[
            kv('Database', '${d['database']}'),
            kv(
                'SMTP',
                d['mailConfigured'] == true
                    ? '${d['smtpHost']} · from ${d['smtpFrom']}'
                    : 'Not configured (backend/.env)',
                ok: d['mailConfigured'] == true),
            kv(
                'Mail scheduler',
                d['schedulerEnabled'] == true
                    ? 'Running (checks every minute)'
                    : 'Off (MAIL_SCHEDULER_ENABLED=false)',
                ok: d['schedulerEnabled'] == true),
            kv('Link in emails',
                '${d['appPublicUrl'] ?? 'not set (APP_PUBLIC_URL)'}',
                ok: d['appPublicUrl'] != null),
            kv('Idle sign-out', '${d['sessionIdleMinutes']} minutes'),
            kv('Environment', '${d['nodeEnv']}',
                ok: d['nodeEnv'] == 'production'),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final e in [
                ('Users', counts['users']),
                ('POs', counts['pos']),
                ('Open POs', counts['active_pos']),
                ('Suppliers', counts['suppliers']),
                ('Materials', counts['materials']),
                ('Failed mails (7 d)', counts['failed_mail_7d']),
              ])
                Container(
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: DsColors.subtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: DsColors.cardBorder)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${e.$2 ?? 0}', style: DsType.stat(19)),
                        Text(e.$1, style: DsType.metaSm),
                      ]),
                ),
            ]),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      const _ActivityLog(system: true),
    ]);
  }
}

/// A settings card while its values load: the real title, then the shapes of
/// what the card holds — description lines, switch rows,
/// labelled fields with their Save button, tags, a row of buttons — so the
/// page lands in place instead of replacing a generic list.
class _CardGhost extends StatelessWidget {
  const _CardGhost(
    this.title,
    this.icon, {
    this.lines = 0,
    this.switches = 0,
    this.fields = const [],
    this.save = false,
    this.tags = 0,
    this.buttons = 0,
  });

  final String title;
  final IconData? icon;
  final int lines;
  final int switches;

  /// Field widths; null is a field that takes the rest of the row.
  final List<double?> fields;
  final bool save;
  final int tags;
  final int buttons;

  @override
  Widget build(BuildContext context) {
    Widget field(int k) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DsSkel.line(DsSkel.vary(k, 120, .3), height: 10),
              const SizedBox(height: 8),
              DsSkel.fill(42, radius: 10),
            ]);
    return DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        DsCardTitle(title, icon: icon),
        for (var k = 0; k < lines; k++) ...[
          SizedBox(height: k == 0 ? 8 : 6),
          DsSkel.line(k == lines - 1 && lines > 1 ? 380 : 640, height: 10),
        ],
        for (var k = 0; k < switches; k++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: DsSkel.lines(
                      DsSkel.vary(k, 280, .3), DsSkel.vary(k + 3, 420, .3),
                      titleH: 12),
                ),
              ),
              const SizedBox(width: 16),
              DsSkel.chip(40, height: 22),
            ]),
          ),
        // A row with a stretching field is a Row, like the mail card's; one of
        // fixed fields wraps, like the scheduling card's.
        if (fields.contains(null)) ...[
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var k = 0; k < fields.length; k++) ...[
              if (fields[k] == null)
                Expanded(child: field(k))
              else
                SizedBox(width: fields[k], child: field(k)),
              const SizedBox(width: 12),
            ],
            if (save) DsSkel.box(92, 42, radius: 9),
          ]),
        ] else if (fields.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
              spacing: 14,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                for (var k = 0; k < fields.length; k++)
                  SizedBox(width: fields[k], child: field(k)),
                if (save) DsSkel.box(92, 42, radius: 9),
              ]),
        ],
        if (tags > 0) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (var k = 0; k < tags; k++) DsSkel.tag(DsSkel.vary(k, 160, .5)),
          ]),
        ],
        if (buttons > 0) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var k = 0; k < buttons; k++)
              DsSkel.box(DsSkel.vary(k, 180, .4), 38, radius: 9),
          ]),
        ],
      ]),
    );
  }
}
