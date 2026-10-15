part of '../main.dart';

enum _SettingsTab {
  mail,
  scheduling,
  imports,
  outbox,
  activity,
  sections,
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
      (_SettingsTab.scheduling, Icons.timelapse, 'Due dates & alerts'),
      (_SettingsTab.imports, Icons.upload_file, 'Import history'),
      (_SettingsTab.outbox, Icons.outbox_outlined, 'Mail log'),
      (_SettingsTab.activity, Icons.history, 'Activity log'),
    ];
    final systemItems = [
      (_SettingsTab.sections, Icons.apartment, 'Sections'),
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
                    child: DsSectionLabel('Section · ${scope.section['name']}'),
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
            _SettingsTab.sections => const _SectionsAdmin(),
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
  final extra = TextEditingController();
  TimeOfDay time = const TimeOfDay(hour: 8, minute: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(loadSettings());
      unawaited(_status());
    });
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
    if (loading) return const PageBody(children: [DsSkeletonList(rows: 5)]);
    final configured = status?['configured'] == true;
    final recipients =
        (status?['recipients'] as List? ?? const []).cast<dynamic>();
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
              'Active members of this section who left "Receive the daily email" on in their profile, plus the extra recipients.',
              style: DsType.meta),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final r in recipients) DsTag('$r'),
            if (recipients.isEmpty)
              const Text('Nobody yet', style: DsType.meta),
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
  final defaultLead = TextEditingController();
  final minFlex = TextEditingController();
  final dueSoon = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => unawaited(loadSettings()));
  }

  @override
  void onLoaded() {
    defaultLead.text = '${values['workflow.defaultLeadTimeDays']}';
    minFlex.text = '${values['workflow.minFlexDays']}';
    dueSoon.text = '${values['alert.dueSoonDays']}';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const PageBody(children: [DsSkeletonList(rows: 5)]);
    Widget numberField(String label, TextEditingController c, String hint) =>
        SizedBox(
          width: 220,
          child: DsLabeledField(
            label: label,
            child: TextField(
              controller: c,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3)
              ],
              decoration: dsInput(hint: hint),
            ),
          ),
        );
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('How due dates are counted',
              icon: Icons.calculate_outlined),
          const SizedBox(height: 10),
          DsSegmented(
            selected: values['workflow.dayMode'] == 'WORKING' ? 1 : 0,
            length: 2,
            itemBuilder: (context, i, t) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                  [
                    'Calendar days (as in the PUR Process sheet)',
                    'Working days (skip weekends & holidays)'
                  ][i],
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(DsColors.muted, DsColors.navyDeep, t))),
            ),
            onSelect: (i) => unawaited(saveSettings(
                {'workflow.dayMode': i == 1 ? 'WORKING' : 'CALENDAR'})),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: values['workflow.useMaterialLeadTime'] == true,
            title: const Text('Use the material lead time for the ETA',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'On: the S/I step is stretched so the goods arrive on PO date + the longest lead time of the PO\'s materials. '
                'Off: the fixed day counts of the workflow are used for every PO.',
                style: DsType.metaSm),
            onChanged: (v) =>
                unawaited(saveSettings({'workflow.useMaterialLeadTime': v})),
          ),
          const SizedBox(height: 10),
          Wrap(
              spacing: 14,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                numberField('Default lead time (days)', defaultLead, '75'),
                numberField('Shortest S/I step (days)', minFlex, '5'),
                numberField('"Due soon" warning (days ahead)', dueSoon, '3'),
                DsPrimaryButton(
                  label: 'Save',
                  icon: Icons.save_outlined,
                  height: 42,
                  onPressed: saving
                      ? null
                      : () => unawaited(saveSettings({
                            'workflow.defaultLeadTimeDays':
                                int.tryParse(defaultLead.text) ?? 0,
                            'workflow.minFlexDays':
                                int.tryParse(minFlex.text) ?? 0,
                            'alert.dueSoonDays':
                                int.tryParse(dueSoon.text) ?? 0,
                          })),
                ),
              ]),
          const SizedBox(height: 12),
          const InfoStrip(
            text:
                'Default lead time is used when neither the materials nor the supplier have one. '
                'Changing how days are counted re-plans every open PO in this section.',
          ),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Row(children: [
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Re-plan open POs', style: DsType.cardTitle),
              SizedBox(height: 4),
              Text(
                  'After changing lead times in the Material Master, re-plan every open PO with the current rules. '
                  'Steps already done keep their dates.',
                  style: DsType.meta),
            ]),
          ),
          DsOutlineButton(
            label: 'Re-plan now',
            icon: Icons.sync,
            height: 40,
            onPressed: () async {
              if (!await confirmAction(context,
                  title: 'Re-plan all open POs?',
                  message: 'Due dates and ETAs of open steps are recalculated.',
                  confirmLabel: 'Re-plan')) {
                return;
              }
              if (!context.mounted) return;
              final r = await guard(
                  context,
                  () => AppScope.read(context)
                      .api
                      .postJson('/workflow/recalculate', {}));
              if (r != null && context.mounted) {
                AppToast.success(
                    context, '${r['recalculated']} open PO(s) re-planned');
              }
            },
          ),
        ]),
      ),
    ]);
  }
}

class _ImportHistory extends StatefulWidget {
  const _ImportHistory();
  @override
  State<_ImportHistory> createState() => _ImportHistoryState();
}

class _ImportHistoryState extends State<_ImportHistory> {
  List<Map<String, dynamic>>? rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final r = await guard(context,
        () => AppScope.read(context).api.getJson('/pos/import/batches'));
    if (r != null && mounted) {
      setState(() => rows = (r['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('Excel uploads', icon: Icons.upload_file),
          const SizedBox(height: 4),
          const Text(
              'Every uploaded file is kept exactly as it was, and every column of every PO line is stored with the PO.',
              style: DsType.meta),
          const SizedBox(height: 12),
          if (rows == null) const DsSkeletonList(rows: 4),
          if (rows != null && rows!.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No upload yet', style: DsType.meta)),
          for (final b in rows ?? const <Map<String, dynamic>>[])
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
              child: Row(children: [
                const Icon(Icons.description_outlined, color: DsColors.greenFg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b['fileName']}', style: DsType.rowTitle),
                        Text(
                            '${fmtDateTime(b['createdAt'])} · ${b['uploadedBy'] ?? '-'} · sheet "${b['sheetName'] ?? '-'}"',
                            style: DsType.metaSm),
                      ]),
                ),
                SizedBox(
                    width: 260,
                    child: Text(
                        '${b['totalRows']} lines · ${b['created']} POs created · ${b['skipped']} skipped',
                        style: DsType.meta)),
                if (b['hasFile'] == true)
                  DsIconButton(
                    icon: Icons.download_outlined,
                    tooltip: 'Download the original file',
                    onTap: () => unawaited(downloadFromApi(
                        context,
                        '/pos/import/batches/${b['id']}/file',
                        '${b['fileName']}')),
                  ),
              ]),
            ),
        ]),
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
  List<Map<String, dynamic>>? rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final r = await guard(
        context, () => AppScope.read(context).api.getJson('/settings/outbox'));
    if (r != null && mounted) {
      setState(() => rows = (r['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    }
  }

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
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Mail log (last 100)',
              icon: Icons.outbox_outlined,
              trailing: DsIconButton(
                  icon: Icons.refresh, tooltip: 'Reload', onTap: load)),
          const SizedBox(height: 10),
          if (rows == null) const DsSkeletonList(rows: 4),
          if (rows != null && rows!.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No mail yet', style: DsType.meta)),
          for (final m in rows ?? const <Map<String, dynamic>>[])
            InkWell(
              onTap: () => open(intFrom(m['id'])!),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${m['subject']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.rowTitle),
                          Text('${m['to'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DsType.metaSm),
                          if (m['error'] != null)
                            Text('${m['error']}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: DsColors.redFg)),
                        ]),
                  ),
                  DsTag('${m['status']}',
                      color: colors('${m['status']}').$1,
                      bg: colors('${m['status']}').$2),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }
}

class _ActivityLog extends StatefulWidget {
  const _ActivityLog({required this.system});
  final bool system;
  @override
  State<_ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends State<_ActivityLog> {
  List<Map<String, dynamic>>? rows;
  int total = 0;
  int page = 1;
  bool securityOnly = false;
  final search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final base = widget.system ? '/admin/audit' : '/settings/audit';
    final r = await guard(
        context,
        () => AppScope.read(context).api.getJson('$base${qs({
                  'q': search.text.trim(),
                  'page': page,
                  'pageSize': 50,
                  if (widget.system && securityOnly) 'security': 'true',
                })}'));
    if (r != null && mounted) {
      setState(() {
        rows = (r['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        total = intFrom(r['total']) ?? 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = DsCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                  page = 1;
                  unawaited(load());
                });
              },
            ),
          ),
          if (widget.system) ...[
            const SizedBox(width: 10),
            FilterChip(
              label: const Text('Security events only'),
              selected: securityOnly,
              onSelected: (v) {
                securityOnly = v;
                page = 1;
                unawaited(load());
              },
            ),
          ],
          const Spacer(),
          Text(plural(total, 'entry', 'entries'), style: DsType.meta),
        ]),
        const SizedBox(height: 10),
        if (rows == null) const DsSkeletonList(rows: 6),
        for (final a in rows ?? const <Map<String, dynamic>>[])
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 130,
                  child: Text(fmtDateTime(a['at']), style: DsType.metaSm)),
              SizedBox(
                  width: 140,
                  child: Text('${a['actorName'] ?? '-'}',
                      overflow: TextOverflow.ellipsis, style: DsType.rowTitle)),
              SizedBox(
                width: 170,
                child: Text('${a['action']}',
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
                      overflow: TextOverflow.ellipsis, style: DsType.meta)),
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
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: PaginationBar(
            page: page - 1,
            totalItems: total,
            pageSize: 50,
            onChanged: (p) {
              page = p + 1;
              unawaited(load());
            },
          ),
        ),
      ]),
    );
    return widget.system ? body : PageBody(children: [body]);
  }
}

class _SectionsAdmin extends StatefulWidget {
  const _SectionsAdmin();
  @override
  State<_SectionsAdmin> createState() => _SectionsAdminState();
}

class _SectionsAdminState extends State<_SectionsAdmin> {
  List<Map<String, dynamic>>? rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final r = await guard(
        context, () => AppScope.read(context).api.getJson('/admin/sections'));
    if (r != null && mounted) {
      setState(() => rows = (r['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    }
  }

  Future<void> edit([Map<String, dynamic>? s]) async {
    final api = AppScope.read(context).api;
    final code = TextEditingController(text: '${s?['code'] ?? ''}');
    final name = TextEditingController(text: '${s?['name'] ?? ''}');
    final desc = TextEditingController(text: '${s?['description'] ?? ''}');
    bool active = s?['isActive'] != false;
    String? error;
    final ok = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AppDialog(
                title: s == null ? 'New section' : 'Edit section ${s['code']}',
                icon: Icons.apartment,
                width: 480,
                body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (s == null)
                        DsLabeledField(
                            label: 'Code (cannot change later)',
                            child: TextField(
                                controller: code,
                                decoration: dsInput(hint: 'PUR2'))),
                      const SizedBox(height: 12),
                      DsLabeledField(
                          label: 'Name',
                          child: TextField(
                              controller: name,
                              decoration: dsInput(hint: 'Purchase — Rayong'))),
                      const SizedBox(height: 12),
                      DsLabeledField(
                          label: 'Description',
                          child: TextField(
                              controller: desc, decoration: dsInput())),
                      if (s != null)
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: active,
                            title: const Text('Active'),
                            onChanged: (v) => setState(() => active = v)),
                      if (s == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: InfoStrip(
                              text:
                                  'A new section starts with the default 9-step workflow and empty masters. You are added as its section admin.'),
                        ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        InfoStrip(
                            text: error!,
                            icon: Icons.error_outline,
                            color: DsColors.redFg)
                      ],
                    ]),
                actions: [
                  DsOutlineButton(
                      label: 'Cancel',
                      height: 40,
                      onPressed: () => Navigator.pop(ctx, false)),
                  DsPrimaryButton(
                    label: 'Save',
                    height: 40,
                    onPressed: () async {
                      try {
                        if (s == null) {
                          await api.postJson('/admin/sections', {
                            'code': code.text.trim(),
                            'name': name.text.trim(),
                            'description': desc.text.trim()
                          });
                        } else {
                          await api.patchJson('/admin/sections/${s['id']}', {
                            'name': name.text.trim(),
                            'description': desc.text.trim(),
                            'isActive': active
                          });
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        setState(() => error = friendlyError(e.message));
                      }
                    },
                  ),
                ],
              )),
    );
    if (ok == true) {
      if (mounted) AppToast.success(context, 'Section saved');
      unawaited(load());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Sections',
              icon: Icons.apartment,
              trailing: DsPrimaryButton(
                  label: 'New section',
                  icon: Icons.add,
                  height: 36,
                  onPressed: () => edit())),
          const SizedBox(height: 4),
          const Text(
              'Each section is one purchasing team with its own POs, masters, workflow and email settings.',
              style: DsType.meta),
          const SizedBox(height: 12),
          if (rows == null) const DsSkeletonList(rows: 3),
          for (final s in rows ?? const <Map<String, dynamic>>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: DsTag('${s['code']}'),
              title: Text('${s['name']}', style: DsType.rowTitle),
              subtitle: Text(
                  '${s['members']} members · ${s['activePos']} open POs${s['isActive'] == true ? '' : ' · inactive'}',
                  style: DsType.metaSm),
              trailing: DsIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit',
                  onTap: () => edit(s)),
            ),
        ]),
      ),
    ]);
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(load()));
  }

  Future<void> load() async {
    final r = await guard(context,
        () => AppScope.read(context).api.getJson('/admin/holidays?year=$year'));
    if (r != null && mounted) {
      setState(() => rows = (r['data'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList());
    }
  }

  Future<void> add() async {
    final api = AppScope.read(context).api;
    DateTime date = DateTime(year, DateTime.now().month, DateTime.now().day);
    final name = TextEditingController();
    final ok = await showGlassDialog<bool>(
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
                                lastDate: DateTime(2035));
                            if (p != null) setState(() => date = p);
                          },
                          child: InputDecorator(
                              decoration: dsInput(icon: Icons.event),
                              child: Text(fmtDate(isoDate(date)))),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DsLabeledField(
                          label: 'Name',
                          child: TextField(
                              controller: name,
                              decoration: dsInput(hint: 'Songkran'))),
                    ]),
                actions: [
                  DsOutlineButton(
                      label: 'Cancel',
                      height: 40,
                      onPressed: () => Navigator.pop(ctx, false)),
                  DsPrimaryButton(
                    label: 'Add',
                    height: 40,
                    onPressed: () async {
                      if (name.text.trim().isEmpty) return;
                      try {
                        await api.postJson('/admin/holidays',
                            {'date': isoDate(date), 'name': name.text.trim()});
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        if (ctx.mounted) {
                          AppToast.error(ctx, friendlyError(e.message));
                        }
                      }
                    },
                  ),
                ],
              )),
    );
    if (ok == true) unawaited(load());
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    return PageBody(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
                child: DsCardTitle('Company holidays',
                    icon: Icons.beach_access_outlined)),
            DsIconButton(
                icon: Icons.chevron_left,
                onTap: () {
                  year--;
                  unawaited(load());
                }),
            Text('$year', style: DsType.cardTitle),
            DsIconButton(
                icon: Icons.chevron_right,
                onTap: () {
                  year++;
                  unawaited(load());
                }),
            const SizedBox(width: 10),
            DsPrimaryButton(
                label: 'Add holiday',
                icon: Icons.add,
                height: 36,
                onPressed: add),
          ]),
          const SizedBox(height: 4),
          const Text(
              'No daily email is sent on these days. In "working days" mode they are also skipped when counting due dates.',
              style: DsType.meta),
          const SizedBox(height: 12),
          if (rows == null) const DsSkeletonList(rows: 3),
          if (rows != null && rows!.isEmpty)
            const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No holidays entered for this year',
                    style: DsType.meta)),
          for (final h in rows ?? const <Map<String, dynamic>>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy, color: DsColors.amberFg),
              title: Text('${h['name']}', style: DsType.rowTitle),
              subtitle: Text(
                  intl.DateFormat('EEEE d MMMM yyyy')
                      .format(DateTime.parse('${h['date']}')),
                  style: DsType.metaSm),
              trailing: DsIconButton(
                icon: Icons.delete_outline,
                color: DsColors.redFg,
                tooltip: 'Remove',
                onTap: () async {
                  if (await guard(context,
                          () => api.deleteJson('/admin/holidays/${h['id']}'),
                          success: 'Holiday removed') !=
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
          if (d == null)
            const DsSkeletonList(rows: 4)
          else ...[
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
                ('Sections', counts['sections']),
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
