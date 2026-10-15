part of '../main.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final display = TextEditingController();
  final full = TextEditingController();
  final dept = TextEditingController();
  final position = TextEditingController();
  final phone = TextEditingController();
  String? prefix;
  bool saving = false;
  Map<String, dynamic>? stats;
  List<Map<String, dynamic>> activity = [];
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_filled) {
      _filled = true;
      final me = AppScope.of(context).me;
      display.text = '${me['displayName'] ?? ''}';
      full.text = '${me['fullName'] ?? ''}';
      dept.text = '${me['department'] ?? ''}';
      position.text = '${me['position'] ?? ''}';
      phone.text = '${me['phone'] ?? ''}';
      prefix = me['namePrefix'] as String?;
      unawaited(_loadExtras());
    }
  }

  @override
  void dispose() {
    for (final c in [display, full, dept, position, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExtras() async {
    final api = AppScope.read(context).api;
    try {
      final s = await api.getJson('/profile/stats');
      final a = await api.getJson('/profile/activity');
      if (!mounted) return;
      setState(() {
        stats = s;
        activity = (a['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _save(Map<String, dynamic> body,
      {String message = 'Profile saved'}) async {
    final scope = AppScope.read(context);
    setState(() => saving = true);
    final r = await guard(context, () => scope.api.patchJson('/profile', body),
        success: message);
    if (!mounted) return;
    setState(() => saving = false);
    if (r != null) {
      scope.onMeChanged(Map<String, dynamic>.from(r['user'] as Map));
    }
  }

  /// Crops the picked image to a centred square and scales it to 256 px, so
  /// what is uploaded is a few KB whatever the camera produced.
  Future<String?> _squareJpeg(String dataUrl) async {
    final img = html.ImageElement();
    final done = Completer<void>();
    img.onLoad.listen((_) => done.complete());
    img.onError.listen((_) => done.completeError('bad image'));
    img.src = dataUrl;
    try {
      await done.future;
    } catch (_) {
      return null;
    }
    final w = img.naturalWidth;
    final h = img.naturalHeight;
    final side = min(w, h);
    final canvas = html.CanvasElement(width: 256, height: 256);
    final ctx = canvas.context2D;
    ctx.drawImageScaledFromSource(
        img, (w - side) / 2, (h - side) / 2, side, side, 0, 0, 256, 256);
    return canvas.toDataUrl('image/jpeg', 0.86);
  }

  Future<void> _changePicture() async {
    final scope = AppScope.read(context);
    final picked = await pickImageDataUrl();
    if (picked == null) return;
    final square = await _squareJpeg(picked);
    if (square == null) {
      if (mounted) {
        AppToast.error(context, 'That file could not be read as an image');
      }
      return;
    }
    if (!mounted) return;
    final r = await guard(
        context, () => scope.api.putJson('/profile/avatar', {'avatar': square}),
        success: 'Picture updated');
    if (r != null) {
      scope.onMeChanged(Map<String, dynamic>.from(r['user'] as Map));
    }
  }

  Future<void> _removePicture() async {
    final scope = AppScope.read(context);
    final r = await guard(
        context, () => scope.api.putJson('/profile/avatar', {'avatar': null}),
        success: 'Picture removed');
    if (r != null) {
      scope.onMeChanged(Map<String, dynamic>.from(r['user'] as Map));
    }
  }

  Future<void> _changePassword() async {
    final scope = AppScope.read(context);
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    String? error;
    bool busy = false;
    await showGlassDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> submit() async {
          final p = passwordPolicyProblem(next.text);
          if (current.text.isEmpty) {
            return setState(() => error = 'Enter your current password');
          }
          if (p != null) return setState(() => error = p);
          if (next.text != confirm.text) {
            return setState(() => error = 'The new passwords do not match');
          }
          setState(() => busy = true);
          try {
            final r = await scope.api.patchJson('/profile/password',
                {'currentPassword': current.text, 'newPassword': next.text});
            scope.api.token = '${r['token']}';
            if (r['csrfToken'] != null) {
              scope.api.csrfToken = '${r['csrfToken']}';
            }
            if (ctx.mounted) {
              AppToast.success(
                  ctx, 'Password changed — other devices were signed out');
              Navigator.pop(ctx);
            }
          } on ApiException catch (e) {
            setState(() {
              busy = false;
              error = friendlyError(e.message);
            });
          }
        }

        return AppDialog(
          title: 'Change password',
          icon: Icons.key_outlined,
          width: 440,
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DsLabeledField(
                label: 'Current password',
                child: TextField(
                    controller: current,
                    obscureText: true,
                    autofocus: true,
                    decoration: dsInput(icon: Icons.lock_outline))),
            const SizedBox(height: 12),
            DsLabeledField(
                label: 'New password',
                child: TextField(
                    controller: next,
                    obscureText: true,
                    decoration: dsInput(
                        icon: Icons.lock_reset, hint: kPasswordRuleHint))),
            const SizedBox(height: 12),
            DsLabeledField(
              label: 'Confirm new password',
              child: TextField(
                  controller: confirm,
                  obscureText: true,
                  onSubmitted: (_) => submit(),
                  decoration: dsInput(icon: Icons.lock_reset)),
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
                onPressed: busy ? null : () => Navigator.pop(ctx)),
            DsPrimaryButton(
                label: busy ? 'Saving…' : 'Change password',
                height: 40,
                onPressed: busy ? null : submit),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final me = scope.me;
    final sections = (me['sections'] as List? ?? const []).cast<Map>();
    final wide = MediaQuery.of(context).size.width >= 1200;
    final left = Column(children: [
      DsCard(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          Stack(clipBehavior: Clip.none, children: [
            UserAvatar(user: me, size: 104),
            Positioned(
              right: -4,
              bottom: -4,
              child: Material(
                color: DsColors.navy,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Change picture',
                  icon: const Icon(Icons.photo_camera_outlined,
                      color: Colors.white, size: 18),
                  onPressed: _changePicture,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text('${me['namePrefix'] ?? ''} ${me['displayName'] ?? ''}'.trim(),
              style: DsType.pageTitle),
          if ('${me['fullName'] ?? ''}'.isNotEmpty)
            Text('${me['fullName']}', style: DsType.meta),
          const SizedBox(height: 4),
          Text('${me['email']}', style: DsType.meta),
          const SizedBox(height: 10),
          Wrap(spacing: 6, children: [
            DsTag(roleLabel('${me['roleCode']}'),
                color: DsColors.navyDeep, bg: DsColors.navySoft),
            if ('${me['employeeNo'] ?? ''}'.isNotEmpty)
              DsTag('No. ${me['employeeNo']}'),
          ]),
          if (me['avatar'] != null)
            TextButton(
                onPressed: _removePicture, child: const Text('Remove picture')),
          const Divider(height: 28),
          Row(children: [
            Expanded(child: _stat('POs added', stats?['posCreated'])),
            Expanded(child: _stat('Steps done', stats?['stepsDone'])),
            Expanded(child: _stat('Last 30 days', stats?['steps30d'])),
          ]),
          const Divider(height: 28),
          _kv('Last sign-in', fmtDateTime(me['lastLoginAt'])),
          _kv('Account since', fmtDateTime(me['createdAt'])),
          _kv(
              'Privacy consent',
              me['pdpaConsentAt'] == null
                  ? '-'
                  : fmtDateTime(me['pdpaConsentAt'])),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('My sections', icon: Icons.apartment),
          const SizedBox(height: 8),
          for (final s in sections)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                DsTag('${s['code']}'),
                const SizedBox(width: 8),
                Expanded(child: Text('${s['name']}', style: DsType.rowTitle)),
                Text(
                    s['isSectionAdmin'] == true
                        ? 'Section admin'
                        : s['canEdit'] == true
                            ? 'Can edit'
                            : 'Read only',
                    style: DsType.metaSm),
              ]),
            ),
        ]),
      ),
    ]);
    final right = Column(children: [
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('Personal details', icon: Icons.badge_outlined),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(
              width: 110,
              child: DsLabeledField(
                label: 'Prefix',
                child: DropdownButtonFormField<String>(
                  initialValue: prefix,
                  decoration: dsInput(),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('-')),
                    for (final p in const ['Mr.', 'Mrs.', 'Ms.', 'Miss', 'Dr.'])
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setState(() => prefix = v),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: DsLabeledField(
                    label: 'Display name',
                    child:
                        TextField(controller: display, decoration: dsInput()))),
            const SizedBox(width: 12),
            Expanded(
                flex: 2,
                child: DsLabeledField(
                    label: 'Full name',
                    child: TextField(controller: full, decoration: dsInput()))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: DsLabeledField(
                    label: 'Department',
                    child: TextField(controller: dept, decoration: dsInput()))),
            const SizedBox(width: 12),
            Expanded(
                child: DsLabeledField(
                    label: 'Position',
                    child: TextField(
                        controller: position, decoration: dsInput()))),
            const SizedBox(width: 12),
            Expanded(
                child: DsLabeledField(
                    label: 'Phone',
                    child: TextField(
                        controller: phone,
                        decoration: dsInput(icon: Icons.phone_outlined)))),
          ]),
          const SizedBox(height: 8),
          const Text('Your email and role are changed by your section admin.',
              style: DsType.metaSm),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: DsPrimaryButton(
              label: saving ? 'Saving…' : 'Save details',
              icon: Icons.save_outlined,
              height: 40,
              onPressed: saving
                  ? null
                  : () {
                      if (display.text.trim().isEmpty) {
                        AppToast.error(context, 'Display name cannot be empty');
                        return;
                      }
                      unawaited(_save({
                        'displayName': display.text.trim(),
                        'fullName': full.text.trim(),
                        'namePrefix': prefix ?? '',
                        'department': dept.text.trim(),
                        'position': position.text.trim(),
                        'phone': phone.text.trim(),
                      }));
                    },
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const DsCardTitle('Email', icon: Icons.mail_outline),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: me['receiveDailyMail'] == true,
            title: const Text('Receive the daily shipment email',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            subtitle: const Text(
                'Sent on working days (and the monthly report at month end) for every section you belong to.',
                style: DsType.metaSm),
            onChanged: saving
                ? null
                : (v) => unawaited(_save({'receiveDailyMail': v},
                    message: v
                        ? 'You will get the daily email'
                        : 'Daily email turned off')),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      DsCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsCardTitle('Security',
              icon: Icons.shield_outlined,
              trailing: DsOutlineButton(
                  label: 'Change password',
                  icon: Icons.key_outlined,
                  height: 36,
                  onPressed: _changePassword)),
          const SizedBox(height: 6),
          Text(
              'Changing your password signs you out on every other device. '
              'You are signed out automatically after ${AppConfig.idleTimeoutMinutes} minutes without activity.',
              style: DsType.meta),
          const SizedBox(height: 12),
          const DsSectionLabel('Recent account activity'),
          const SizedBox(height: 6),
          if (activity.isEmpty) const Text('-', style: DsType.meta),
          for (final a in activity.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(
                  a['action'] == 'LOGIN_FAILED' ||
                          a['action'] == 'ACCOUNT_LOCKED'
                      ? Icons.gpp_maybe_outlined
                      : Icons.check_circle_outline,
                  size: 16,
                  color: a['action'] == 'LOGIN_FAILED' ||
                          a['action'] == 'ACCOUNT_LOCKED'
                      ? DsColors.redFg
                      : DsColors.greenFg,
                ),
                const SizedBox(width: 8),
                SizedBox(
                    width: 150,
                    child: Text(_actionLabel('${a['action']}'),
                        style: DsType.rowTitle)),
                SizedBox(
                    width: 140,
                    child: Text(fmtDateTime(a['at']), style: DsType.metaSm)),
                Expanded(child: Text('${a['ip'] ?? ''}', style: DsType.metaSm)),
              ]),
            ),
        ]),
      ),
    ]);
    return PageBody(children: [
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 360, child: left),
          const SizedBox(width: 16),
          Expanded(child: right),
        ])
      else ...[left, const SizedBox(height: 16), right],
    ]);
  }

  String _actionLabel(String a) => switch (a) {
        'LOGIN' => 'Signed in',
        'LOGOUT' => 'Signed out',
        'LOGIN_FAILED' => 'Wrong password',
        'ACCOUNT_LOCKED' => 'Account locked',
        'CHANGE_PASSWORD' => 'Password changed',
        'EDIT_PROFILE' => 'Profile edited',
        'EDIT_AVATAR' => 'Picture changed',
        'PDPA_ACCEPT' => 'Accepted privacy notice',
        _ => a,
      };

  Widget _stat(String label, dynamic value) => Column(children: [
        Text('${value ?? '-'}', style: DsType.stat(20)),
        Text(label, style: DsType.metaSm),
      ]);

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: DsType.meta)),
          Text(v, style: DsType.rowTitle)
        ]),
      );
}
