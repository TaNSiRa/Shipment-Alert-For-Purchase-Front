part of '../main.dart';

/// The Profile page, laid out as RAP's: the employee ID badge (or the classic
/// information card) on the left, and a tabbed column on the right — Profile,
/// Reminders, Security.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final name = TextEditingController();
  final fullName = TextEditingController();
  final phone = TextEditingController();
  String? namePrefix;
  // Dropdown-driven org fields. A value no longer in the configured list
  // (legacy data) stays visible and selectable.
  String? branch;
  String? department;
  String? section;
  int? positionId;
  OrgOptions org = const OrgOptions();
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  Map<String, String> errors = {};
  bool saving = false;
  Map<String, dynamic>? stats;
  List<Map<String, dynamic>> activity = [];
  bool _filled = false;

  // Measured height of the right-hand column; the left card is given it as a
  // minimum so both columns end level. Measured rather than IntrinsicHeight
  // because the form's TextFields don't support intrinsic sizing in a list.
  final GlobalKey _rightColumnKey = GlobalKey();
  double? _rightColumnHeight;

  // Which card is on screen: profile, reminders, security.
  int tab = 0;
  // Profile tab: read-only contact sheet until Edit is pressed.
  bool editing = false;

  Map<String, dynamic> get me => AppScope.of(context).me;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_filled) {
      _filled = true;
      _loadForm();
      // The ID badge is a live preview of the form: type a name and the card is
      // printed with it before Save is pressed.
      for (final c in [name, fullName, phone]) {
        c.addListener(_formChanged);
      }
      unawaited(_loadExtras());
    }
  }

  /// Fills the form from the saved row — on open, and again on Cancel.
  void _loadForm() {
    final m = AppScope.read(context).me;
    String? text(String key) {
      final v = '${m[key] ?? ''}'.trim();
      return v.isEmpty ? null : v;
    }

    name.text = '${m['displayName'] ?? ''}';
    fullName.text = '${m['fullName'] ?? ''}';
    phone.text = '${m['phone'] ?? ''}';
    namePrefix = text('namePrefix');
    branch = text('branch');
    department = text('department');
    section = text('section');
    positionId = intFrom(m['positionId']);
  }

  /// "Full name (ABBR)" for the position picked in the form, through the
  /// positions list; falls back to the saved label (which is also the old
  /// free-text position for someone who never picked one).
  String get _positionLabel {
    final id = positionId;
    if (id != null) {
      for (final p in org.positions) {
        if (intFrom(p['id']) == id) return positionLabel(p['name'], p['abbreviation']);
      }
      if (id == intFrom(me['positionId'])) return _str('position');
      return '';
    }
    return me['positionId'] == null ? _str('position') : '';
  }

  void _formChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [name, fullName, phone]) {
      c.removeListener(_formChanged);
      c.dispose();
    }
    currentPassword.dispose();
    newPassword.dispose();
    super.dispose();
  }

  Future<void> _loadExtras() async {
    final api = AppScope.read(context).api;
    try {
      final o = await api.getJson('/profile/org-options');
      if (mounted) setState(() => org = OrgOptions.fromJson(o));
    } catch (_) {}
    try {
      final s = await api.getJson('/profile/stats');
      final a = await api.getJson('/profile/activity');
      if (!mounted) return;
      setState(() {
        stats = s;
        activity = (a['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (_) {}
  }

  String _str(String key) => '${me[key] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final displayName = _str('displayName').isEmpty ? _str('email') : _str('displayName');
    final role = _str('roleCode');
    final avatar = _str('avatar');
    final hasAvatar = avatar.startsWith('data:image/');
    final savedSection = _str('section');
    final lastLogin = me['lastLoginAt'] == null ? null : fmtDateTime(me['lastLoginAt']);
    final memberSince = me['createdAt'] == null ? null : fmtDate(me['createdAt']);
    final sections = [
      for (final s in (me['sections'] as List? ?? const []))
        if (s is Map) Map<String, dynamic>.from(s),
    ];
    _ProfileFacts facts({bool dense = false}) => _ProfileFacts(
          email: _str('email'),
          phone: _str('phone'),
          employeeNo: _str('employeeNo'),
          branch: _str('branch'),
          department: _str('department'),
          sections: sections,
          stats: stats,
          lastLogin: lastLogin,
          memberSince: memberSince,
          leadingDivider: !dense,
          dense: dense,
        );

    return PageBody(children: [
      Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          // Wide enough for the info grid to keep three cells to a row next to
          // the 300 px badge column.
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(builder: (context, constraints) {
            final twoCol = constraints.maxWidth >= 720;
            final left = ValueListenableBuilder<bool>(
              valueListenable: ProfileCardStyle.idBadge,
              builder: (context, badge, _) => badge
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: _ProfileIdBadge(
                        // Straight off the form: the badge prints what is being
                        // typed. The classic card keeps showing the saved row.
                        name: name.text.trim().isEmpty ? displayName : name.text.trim(),
                        fullName: fullName.text.trim(),
                        namePrefix: namePrefix ?? '',
                        role: role,
                        position: _positionLabel,
                        section: section ?? '',
                        department: department ?? '',
                        employeeNo: _str('employeeNo'),
                        facts: facts(dense: true),
                        hasAvatar: hasAvatar,
                        onAvatarAction: _handleAvatarAction,
                        photo: hasAvatar ? avatar : null,
                        placement: me['badgePhotoPos'] as String?,
                        onPlacementChanged: _savePlacement,
                      ),
                    )
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      _ProfileCard(
                        me: me,
                        name: displayName,
                        fullName: _str('fullName'),
                        namePrefix: _str('namePrefix'),
                        role: roleLabel(role),
                        position: _str('position'),
                        section: savedSection,
                        hasAvatar: hasAvatar,
                        onAvatarAction: _handleAvatarAction,
                        facts: facts(),
                      ),
                      const SizedBox(height: 10),
                      _CardStyleLink(
                        icon: Icons.badge_outlined,
                        label: 'Employee badge',
                        onTap: () => ProfileCardStyle.idBadge.value = true,
                      ),
                    ]),
            );
            final right = Column(
              key: twoCol ? _rightColumnKey : null,
              children: [
                _tabBar(),
                const SizedBox(height: 12),
                switch (tab) {
                  1 => _remindersCard(),
                  2 => _securityTab(),
                  _ => _editProfileCard(),
                },
              ],
            );
            if (twoCol) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final h = _rightColumnKey.currentContext?.size?.height;
                if (h != null && h != _rightColumnHeight && mounted) {
                  setState(() => _rightColumnHeight = h);
                }
              });
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 300,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: _rightColumnHeight ?? 0),
                    child: left,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: right),
              ]);
            }
            return Column(children: [left, const SizedBox(height: 16), right]);
          }),
        ),
      ),
    ]);
  }

  // ── Profile tab ────────────────────────────────────────────────────────────

  // Reads like a contact sheet (icon · label · value, three to a row) and only
  // turns into a form once Edit is pressed — the same cells, with the value
  // swapped for its input, so nothing jumps around between the two.
  Widget _editProfileCard() {
    return Panel(
      title: editing ? 'Edit profile' : 'Profile information',
      icon: editing ? Icons.edit_outlined : Icons.person_outline,
      trailing: editing
          ? null
          : DsOutlineButton(label: 'Edit', icon: Icons.edit_outlined, height: 34, onPressed: _startEditing),
      child: LayoutBuilder(builder: (context, constraints) {
        final cols = constraints.maxWidth >= 640
            ? 3
            : constraints.maxWidth >= 420
                ? 2
                : 1;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _infoGroup('Personal information', cols, [
            _infoItem(
              icon: Icons.person_outline,
              label: 'Display name',
              value: name.text,
              input: _input(name, 'displayName'),
            ),
            _infoItem(
              icon: Icons.short_text,
              label: 'Title',
              value: namePrefix ?? '',
              input: _titleInput(),
            ),
            _infoItem(
              icon: Icons.badge_outlined,
              label: 'Full name',
              value: fullName.text,
              input: _input(fullName, null, hint: 'Optional'),
            ),
            _infoItem(icon: Icons.tag, label: 'Employee no', value: _str('employeeNo')),
            _infoItem(
              icon: Icons.work_outline,
              label: 'Position',
              value: _positionLabel,
              input: SearchableDropdownField<int>(
                value: positionId,
                decoration: dsInput(hint: 'Optional'),
                items: org.positionItems(positionId, positionLabel(me['positionName'], me['positionAbbr'])),
                onChanged: (v) => setState(() => positionId = v),
              ),
            ),
          ]),
          _groupDivider(),
          _infoGroup('Contact information', cols, [
            _infoItem(icon: Icons.mail_outline, label: 'Email', value: _str('email'), accent: true),
            _infoItem(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: phone.text,
              accent: true,
              input: _input(phone, null, hint: 'Optional'),
            ),
          ]),
          _groupDivider(),
          _infoGroup('Organization', cols, [
            _infoItem(
              icon: Icons.location_on_outlined,
              label: 'Branch',
              value: branch ?? '',
              input: _orgInput(branch, org.branches, (v) => branch = v),
            ),
            _infoItem(
              icon: Icons.apartment_outlined,
              label: 'Department',
              value: department ?? '',
              input: _orgInput(department, org.departments, (v) => department = v),
            ),
            _infoItem(
              icon: Icons.grid_view,
              label: 'Section',
              value: section ?? '',
              input: _orgInput(section, org.sections, (v) => section = v),
            ),
          ]),
          if (editing) ...[
            const SizedBox(height: 14),
            const Row(children: [
              Icon(Icons.lock_outline, size: 14, color: DsColors.faint2),
              SizedBox(width: 6),
              Expanded(
                child: Text('Employee no and email are changed by your admin.',
                    style: TextStyle(fontSize: 11.5, color: DsColors.faint2)),
              ),
            ]),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 10, children: [
                DsOutlineButton(
                    label: 'Cancel', icon: Icons.close, height: 40, onPressed: saving ? null : _cancelEditing),
                DsPrimaryButton(
                    label: saving ? 'Saving…' : 'Save profile',
                    icon: Icons.save,
                    height: 40,
                    onPressed: saving ? null : saveProfile),
              ]),
            ),
          ],
        ]);
      }),
    );
  }

  void _startEditing() => setState(() => editing = true);

  // Throws away whatever was typed: the form goes back to the saved row, which
  // also puts the live badge preview back to what is actually stored.
  void _cancelEditing() {
    _loadForm();
    setState(() {
      errors = {};
      editing = false;
    });
  }

  Widget _groupDivider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Divider(height: 1, thickness: 1, color: DsColors.line),
      );

  Widget _infoGroup(String title, int cols, List<Widget> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DsColors.heading)),
      const SizedBox(height: 14),
      LayoutBuilder(builder: (context, constraints) {
        const gap = 18.0;
        final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: editing ? 16 : 20,
          children: [for (final item in items) SizedBox(width: width, child: item)],
        );
      }),
    ]);
  }

  /// One "icon · label · value" cell. In edit mode the value line becomes
  /// [input]; a cell without one (set by an admin) keeps its value, greyed.
  Widget _infoItem({
    required IconData icon,
    required String label,
    required String value,
    Widget? input,
    bool accent = false,
  }) {
    final text = value.trim();
    final locked = editing && input == null;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Icon(icon, size: 20, color: DsColors.iconSoft),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: DsColors.faint2)),
          SizedBox(height: editing && !locked ? 6 : 3),
          if (editing && !locked)
            input!
          else
            Text(
              text.isEmpty ? '—' : text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: text.isEmpty || locked
                    ? DsColors.faint2
                    : accent
                        ? DsColors.navy
                        : DsColors.heading,
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _titleInput() {
    final items = <String>{...kNamePrefixOptions, if (namePrefix != null) namePrefix!}.toList();
    return SearchableDropdownField<String>(
      value: namePrefix,
      decoration: dsInput(hint: 'Optional'),
      items: [for (final o in items) SearchableDropdownItem<String>(value: o, label: o)],
      onChanged: (v) => setState(() => namePrefix = v),
    );
  }

  Widget _orgInput(String? value, List<String> options, void Function(String? v) assign) {
    return SearchableDropdownField<String>(
      value: value,
      decoration: dsInput(hint: 'Optional'),
      items: stringItems(options, value),
      onChanged: (v) => setState(() => assign(v)),
    );
  }

  Widget _input(TextEditingController controller, String? errorKey,
      {bool obscure = false, String? helperText, String? hint}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: errorKey == null ? null : (_) => clearFieldError(errorKey),
      decoration: dsInput(hint: hint, errorText: errors[errorKey]).copyWith(helperText: helperText),
    );
  }

  void clearFieldError(String key) {
    if (!errors.containsKey(key)) return;
    setState(() => errors = Map<String, String>.from(errors)..remove(key));
  }

  Future<void> saveProfile() async {
    final scope = AppScope.read(context);
    if (name.text.trim().isEmpty) {
      setState(() => errors = {...errors, 'displayName': 'Display name cannot be empty'});
      return;
    }
    final ok = await confirmAction(context, title: 'Save profile', message: 'Save these profile changes?');
    if (!ok || !mounted) return;
    setState(() => saving = true);
    final r = await guard(
      context,
      () => scope.api.patchJson('/profile', {
        'displayName': name.text.trim(),
        'fullName': fullName.text.trim(),
        'namePrefix': namePrefix ?? '',
        'branch': branch ?? '',
        'department': department ?? '',
        'section': section ?? '',
        'positionId': positionId,
        'phone': phone.text.trim(),
      }),
      success: 'Profile saved',
    );
    if (!mounted) return;
    setState(() => saving = false);
    if (r != null) {
      scope.onMeChanged(Map<String, dynamic>.from(r['user'] as Map));
      setState(() => editing = false);
    }
  }

  // ── Tabs ───────────────────────────────────────────────────────────────────

  // The sliding segmented control: the selection travels between tabs.
  Widget _tabBar() {
    const labels = ['Profile', 'Reminders', 'Security'];
    const icons = [
      Icons.person_outline,
      Icons.notifications_none,
      Icons.lock_outline,
    ];
    return DsCard(
      child: Align(
        alignment: Alignment.centerLeft,
        child: DsSegmented(
          selected: tab,
          length: labels.length,
          onSelect: (i) => setState(() => tab = i),
          itemBuilder: (context, i, t) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icons[i], size: 15, color: Color.lerp(DsColors.muted, DsColors.navy, t)),
              const SizedBox(width: 6),
              Text(labels[i],
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(DsColors.text, DsColors.heading, t))),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Reminders tab ──────────────────────────────────────────────────────────

  Widget _remindersCard() {
    final on = me['receiveDailyMail'] == true;
    return Panel(
      title: 'Email reminders',
      icon: Icons.notifications_none,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Choose whether the system emails you about the shipments of the sections you belong to. '
          'Mail is sent on working days only (company holidays excluded).',
          style: TextStyle(fontSize: 12.5, color: DsColors.muted, height: 1.5),
        ),
        const SizedBox(height: 10),
        _SwitchRow(
          on: on,
          icon: Icons.mail_outline,
          title: 'Daily shipment email',
          subtitle: 'Sent at 08:30 on working days, plus the monthly report at month end',
          onChanged: saving
              ? null
              : (v) async {
                  final scope = AppScope.read(context);
                  setState(() => saving = true);
                  final r = await guard(context, () => scope.api.patchJson('/profile', {'receiveDailyMail': v}),
                      success: v ? 'You will get the daily email' : 'Daily email turned off');
                  if (!mounted) return;
                  setState(() => saving = false);
                  if (r != null) scope.onMeChanged(Map<String, dynamic>.from(r['user'] as Map));
                },
        ),
      ]),
    );
  }

  // ── Security tab ───────────────────────────────────────────────────────────

  Widget _securityTab() {
    return Column(children: [
      _changePasswordCard(),
      const SizedBox(height: 12),
      _activityCard(),
    ]);
  }

  Widget _changePasswordCard() {
    return Panel(
      title: 'Change password',
      icon: Icons.lock_outline,
      child: LayoutBuilder(builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 560;
        final fields = [
          _field('Current password', currentPassword, 'currentPassword', obscure: true),
          _field('New password', newPassword, 'newPassword', obscure: true, helperText: kPasswordRuleHint),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (twoCol)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: fields[0]),
              const SizedBox(width: 13),
              Expanded(child: fields[1]),
            ])
          else ...[fields[0], const SizedBox(height: 13), fields[1]],
          const SizedBox(height: 12),
          Text(
              'Changing your password signs you out on every other device. '
              'You are signed out automatically after ${AppConfig.idleTimeoutMinutes} minutes without activity.',
              style: const TextStyle(fontSize: 12, color: DsColors.muted, height: 1.45)),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: DsOutlineButton(
                label: 'Change password', icon: Icons.lock_reset, height: 40, onPressed: changePassword),
          ),
        ]);
      }),
    );
  }

  Widget _field(String label, TextEditingController controller, String? errorKey,
      {bool obscure = false, String? helperText}) {
    return DsLabeledField(
      label: label,
      labelSize: 11.5,
      child: _input(controller, errorKey, obscure: obscure, helperText: helperText),
    );
  }

  Future<void> changePassword() async {
    final next = <String, String>{};
    if (currentPassword.text.isEmpty) next['currentPassword'] = 'Enter your current password';
    if (newPassword.text.isEmpty) {
      next['newPassword'] = 'Enter a new password';
    } else {
      final problem = passwordPolicyProblem(newPassword.text);
      if (problem != null) next['newPassword'] = problem;
    }
    final preserved = Map<String, String>.from(errors)
      ..removeWhere((key, _) => key == 'currentPassword' || key == 'newPassword');
    setState(() => errors = {...preserved, ...next});
    if (next.isNotEmpty) return;
    final scope = AppScope.read(context);
    final ok = await confirmAction(context, title: 'Change password', message: 'Change your password now?');
    if (!ok) return;
    try {
      final r = await scope.api.patchJson('/profile/password', {
        'currentPassword': currentPassword.text,
        'newPassword': newPassword.text,
      });
      // The old token is now revoked: adopt the replacement before anything else.
      scope.api.token = '${r['token']}';
      if (r['csrfToken'] != null) scope.api.csrfToken = '${r['csrfToken']}';
      currentPassword.clear();
      newPassword.clear();
      if (mounted) AppToast.success(context, 'Password changed — other devices have been signed out');
      unawaited(_loadExtras());
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.message.toLowerCase().contains('current password')) {
        setState(() => errors = {...errors, 'currentPassword': friendlyError(e.message)});
      } else {
        AppToast.error(context, friendlyError(e.message));
      }
    } catch (_) {
      if (mounted) AppToast.error(context, 'Could not reach the server. Check your connection and try again.');
    }
  }

  Widget _activityCard() {
    return Panel(
      title: 'Recent account activity',
      icon: Icons.shield_outlined,
      child: activity.isEmpty
          ? const Text('-', style: DsType.meta)
          : _FitToScreen(
              rowHeight: _activityRowH,
              count: activity.length,
              builder: (n) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final a in activity.take(n)) _activityRow(a),
              ]),
            ),
    );
  }

  static const _activityRowH = 30.0;

  Widget _activityRow(Map<String, dynamic> a) {
    return SizedBox(
            height: _activityRowH,
            child: Row(children: [
              Icon(
                _isWarning('${a['action']}') ? Icons.gpp_maybe_outlined : Icons.check_circle_outline,
                size: 16,
                color: _isWarning('${a['action']}') ? DsColors.redFg : DsColors.greenFg,
              ),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: Text(_actionLabel('${a['action']}'), style: DsType.rowTitle)),
              Expanded(flex: 3, child: Text(fmtDateTime(a['at']), style: DsType.metaSm)),
              Expanded(flex: 2, child: Text('${a['ip'] ?? ''}', style: DsType.metaSm)),
            ]),
          );
  }

  bool _isWarning(String a) => a == 'LOGIN_FAILED' || a == 'LOGIN_BLOCKED' || a == 'ACCOUNT_LOCKED';

  String _actionLabel(String a) => switch (a) {
        'LOGIN' => 'Signed in',
        'MICROSOFT_LOGIN' => 'Signed in (Microsoft 365)',
        'LOGOUT' => 'Signed out',
        'LOGIN_FAILED' => 'Wrong password',
        'LOGIN_BLOCKED' => 'Sign-in refused (locked)',
        'ACCOUNT_LOCKED' => 'Account locked',
        'CHANGE_PASSWORD' => 'Password changed',
        'EDIT_PROFILE' => 'Profile edited',
        'EDIT_AVATAR' => 'Picture changed',
        'PDPA_ACCEPT' => 'Accepted privacy notice',
        _ => a,
      };

  // ── Badge photo placement ──────────────────────────────────────────────────

  /// Saved to the account the moment a drag ends — a direct manipulation needs
  /// no Save button. Quiet on success; a failure toasts and the card keeps the
  /// drag until the page is reopened.
  Future<void> _savePlacement(String? placement) async {
    final scope = AppScope.read(context);
    final r = await guard(context, () => scope.api.putJson('/profile/badge-photo', {'placement': placement}));
    if (r != null) scope.onMeChanged(Map<String, dynamic>.from(r['user'] as Map));
  }

  // ── Profile picture: upload (with circle crop), re-adjust, remove ──────────

  Future<void> _handleAvatarAction(String action) async {
    switch (action) {
      case 'upload':
        await _uploadAvatar();
      case 'adjust':
        await _adjustAvatar();
      case 'remove':
        await _removeAvatar();
    }
  }

  Future<void> _uploadAvatar() async {
    final dataUrl = await pickImageDataUrl();
    if (dataUrl == null || dataUrl.isEmpty || !mounted) return;
    // ~10 MB of image as base64.
    if (dataUrl.length > 14 * 1024 * 1024) {
      AppToast.error(context, 'Image is too large (max 10 MB)');
      return;
    }
    if (!dataUrl.startsWith('data:image/')) {
      AppToast.error(context, 'Please choose an image file');
      return;
    }
    await _cropAndSave(dataUrl);
  }

  // Re-open the crop editor on the stored picture to re-position/zoom it.
  Future<void> _adjustAvatar() async {
    final current = _str('avatar');
    if (!current.startsWith('data:image/')) return;
    await _cropAndSave(current);
  }

  Future<void> _cropAndSave(String dataUrl) async {
    final image = await _decodeDataUrl(dataUrl);
    if (!mounted) return;
    if (image == null) {
      AppToast.error(context, 'That file could not be read as an image');
      return;
    }
    final cropped = await showGlassDialog<String>(
      context: context,
      builder: (context) => _AvatarCropDialog(image: image),
    );
    if (cropped == null || !mounted) return;
    await _saveAvatar(cropped);
  }

  static Future<ui.Image?> _decodeDataUrl(String dataUrl) async {
    try {
      final bytes = base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
      final codec = await ui.instantiateImageCodec(bytes);
      return (await codec.getNextFrame()).image;
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeAvatar() async {
    final ok = await confirmAction(context,
        title: 'Remove photo',
        message: 'Remove your profile picture? Your initials will be shown instead.',
        icon: Icons.delete_outline,
        confirmLabel: 'Remove',
        danger: true);
    if (!ok || !mounted) return;
    await _saveAvatar(null);
  }

  Future<void> _saveAvatar(String? dataUrl) async {
    final scope = AppScope.read(context);
    final r = await guard(context, () => scope.api.putJson('/profile/avatar', {'avatar': dataUrl}),
        success: dataUrl == null ? 'Profile picture removed' : 'Profile picture updated');
    if (r != null) scope.onMeChanged(Map<String, dynamic>.from(r['user'] as Map));
  }
}

/// The classic information card: round avatar, name, role, then the facts.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.me,
    required this.name,
    required this.fullName,
    required this.namePrefix,
    required this.role,
    required this.position,
    required this.section,
    required this.hasAvatar,
    required this.onAvatarAction,
    required this.facts,
  });
  final Map<String, dynamic> me;
  final String name;
  final String fullName;
  final String namePrefix;
  final String role;
  final String position;
  final String section;
  final bool hasAvatar;
  final ValueChanged<String> onAvatarAction;
  final Widget facts;

  @override
  Widget build(BuildContext context) {
    // The formal name as it is written on paper, skipped when it would only
    // repeat the display name above it.
    final formalName = [namePrefix, fullName].map((v) => v.trim()).where((v) => v.isNotEmpty).join(' ');
    final showFormalName = formalName.isNotEmpty && formalName.toLowerCase() != name.trim().toLowerCase();
    return DsCard(
      padding: const EdgeInsets.all(22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Stack(clipBehavior: Clip.none, children: [
            UserAvatar(user: me, size: 78),
            Positioned(
                right: -3, bottom: -3, child: _AvatarMenuButton(hasAvatar: hasAvatar, onAction: onAvatarAction)),
          ]),
        ),
        const SizedBox(height: 14),
        Text(name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: DsColors.heading)),
        if (showFormalName) ...[
          const SizedBox(height: 3),
          Text(formalName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: DsColors.muted2, height: 1.35)),
        ],
        const SizedBox(height: 3),
        Text(role, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: DsColors.faint)),
        if (position.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(position.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: DsColors.text2, height: 1.35)),
        ],
        if (section.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(color: DsColors.navySoft, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.grid_view, size: 15, color: DsColors.navy),
                const SizedBox(width: 6),
                Flexible(
                  child: Text('$section section',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: DsColors.navy)),
                ),
              ]),
            ),
          ),
        ],
        facts,
      ]),
    );
  }
}

/// Contact / Organisation / Section access / Activity — the saved identity as
/// label-and-value rows. Shared by the classic card and the back of the badge.
class _ProfileFacts extends StatelessWidget {
  const _ProfileFacts({
    required this.email,
    required this.phone,
    required this.employeeNo,
    required this.branch,
    required this.department,
    required this.sections,
    required this.stats,
    required this.lastLogin,
    required this.memberSince,
    this.leadingDivider = true,
    this.dense = false,
  });

  final String email;
  final String phone;
  final String employeeNo;
  final String branch;
  final String department;
  final List<Map<String, dynamic>> sections;
  final Map<String, dynamic>? stats;
  final String? lastLogin;
  final String? memberSince;

  /// The classic card runs these on from the avatar and needs the rule; the
  /// badge's back opens with them and does not.
  final bool leadingDivider;

  /// Tighter spacing for the badge's back, which has a fixed height.
  final bool dense;

  static const int _maxSectionRows = 6;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (leadingDivider) _divider(),
      _caption('Contact'),
      _row(context, 'Email', email, copyable: true),
      _row(context, 'Phone', phone, copyable: true),
      _row(context, 'Employee no', employeeNo, mono: true, copyable: true),
      _divider(),
      _caption('Organisation'),
      _row(context, 'Branch', branch),
      _row(context, 'Department', department),
      if (sections.isNotEmpty) ...[
        _divider(),
        _caption('Section access', trailing: '${sections.length}'),
        for (final s in sections.take(_maxSectionRows)) _sectionRow(s),
        if (sections.length > _maxSectionRows)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('+${sections.length - _maxSectionRows} more',
                style: TextStyle(fontSize: dense ? 10.5 : 11.5, color: DsColors.faint2)),
          ),
      ],
      _divider(),
      _caption('Activity'),
      if (stats != null) ...[
        _row(context, 'POs added', '${stats!['posCreated'] ?? '-'}', mono: true),
        _row(context, 'Steps done', '${stats!['stepsDone'] ?? '-'}', mono: true),
        _row(context, 'Last 30 days', '${stats!['steps30d'] ?? '-'}', mono: true),
      ],
      if (lastLogin != null) _row(context, 'Last login', lastLogin!, mono: true),
      if (memberSince != null) _row(context, 'Member since', memberSince!, mono: true),
    ]);
  }

  Widget _caption(String text, {String? trailing}) {
    final style =
        TextStyle(fontSize: dense ? 9 : 10, fontWeight: FontWeight.w700, letterSpacing: .8, color: DsColors.faint2);
    return Padding(
      padding: EdgeInsets.only(bottom: dense ? 5 : 7),
      child: Row(children: [
        Expanded(child: Text(text.toUpperCase(), style: style)),
        if (trailing != null) Text(trailing, style: style),
      ]),
    );
  }

  Widget _divider() => Padding(
        padding: EdgeInsets.symmetric(vertical: dense ? 9 : 15),
        child: const Divider(height: 1, color: DsColors.line),
      );

  // What this person is in a section. Admin outranks the rest.
  (String, Color) _sectionRole(Map<String, dynamic> s) {
    if (s['isSectionAdmin'] == true) return ('Section admin', DsColors.purpleFg);
    if (s['canEdit'] == true) return ('Can edit', DsColors.blueFg);
    return ('Read only', DsColors.faint2);
  }

  Widget _sectionRow(Map<String, dynamic> s) {
    final label = '${s['name'] ?? s['code'] ?? ''}';
    final (roleLabel, tone) = _sectionRole(s);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 2.5 : 4),
      child: Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: dense ? 11 : 12.5, fontWeight: FontWeight.w600, color: DsColors.text)),
        ),
        const SizedBox(width: 6),
        Text(roleLabel, style: TextStyle(fontSize: dense ? 10 : 11, fontWeight: FontWeight.w600, color: tone)),
      ]),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool mono = false, bool copyable = false}) {
    final filled = value.trim().isNotEmpty;
    final text = filled ? value.trim() : '-';
    if (!copyable || !filled) return _rowContent(label, text, mono: mono, dense: dense);
    return _CopyableRow(label: label, text: text, mono: mono, dense: dense);
  }

  static Widget _rowContent(String label, String text, {bool mono = false, bool dense = false, Widget? trailing}) {
    final size = dense ? 11.0 : 12.5;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: size, color: DsColors.faint2)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mono
                  ? TextStyle(
                      fontFamily: dsFontMono,
                      fontFamilyFallback: dsFontFallback,
                      fontSize: size,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: DsColors.text)
                  : TextStyle(fontSize: size, fontWeight: FontWeight.w600, height: 1.35, color: DsColors.text)),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 5),
          Padding(padding: const EdgeInsets.only(top: 1), child: trailing),
        ],
      ]),
    );
  }
}

/// The camera badge that opens the upload / adjust / remove menu. Worn by both
/// faces: the classic card's avatar and the badge's printed photo.
class _AvatarMenuButton extends StatelessWidget {
  const _AvatarMenuButton({required this.hasAvatar, required this.onAction, this.size = 26});

  final bool hasAvatar;

  /// 'upload' | 'adjust' | 'remove'.
  final ValueChanged<String> onAction;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Profile picture',
      offset: const Offset(0, 30),
      color: DsColors.popupSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: onAction,
      itemBuilder: (context) => [
        _item('upload', Icons.photo_camera_outlined, hasAvatar ? 'Change photo' : 'Upload photo'),
        if (hasAvatar) _item('adjust', Icons.crop_rotate, 'Adjust position'),
        if (hasAvatar) _item('remove', Icons.delete_outline, 'Remove photo', danger: true),
      ],
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: DsColors.navy,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(Icons.photo_camera, size: size * .5, color: Colors.white),
      ),
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label, {bool danger = false}) {
    final color = danger ? DsColors.redFg : DsColors.text;
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 9),
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// A contact row with a tap-to-copy icon that flips to a checkmark for a beat.
class _CopyableRow extends StatefulWidget {
  const _CopyableRow({required this.label, required this.text, this.mono = false, this.dense = false});
  final String label;
  final String text;
  final bool mono;
  final bool dense;

  @override
  State<_CopyableRow> createState() => _CopyableRowState();
}

class _CopyableRowState extends State<_CopyableRow> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  // Flutter's clipboard already falls back to execCommand("copy") on plain
  // http; this only runs if even that throws.
  bool _execCommandFallback() {
    try {
      final area = html.TextAreaElement()
        ..value = widget.text
        ..style.position = 'fixed'
        ..style.left = '-9999px'
        ..readOnly = true;
      html.document.body?.append(area);
      area.select();
      final ok = html.document.execCommand('copy');
      area.remove();
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<void> _copy() async {
    var ok = true;
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } catch (_) {
      ok = _execCommandFallback();
    }
    if (!mounted) return;
    if (!ok) {
      AppToast.error(context, 'Could not copy ${widget.label.toLowerCase()}');
      return;
    }
    AppToast.success(context, '${widget.label} copied');
    _resetTimer?.cancel();
    setState(() => _copied = true);
    _resetTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final row = _ProfileFacts._rowContent(
      widget.label,
      widget.text,
      mono: widget.mono,
      dense: widget.dense,
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: Icon(
          _copied ? Icons.check_rounded : Icons.copy_rounded,
          key: ValueKey(_copied),
          size: 12,
          color: _copied ? DsColors.greenFg : DsColors.iconSoft,
        ),
      ),
    );
    return Tooltip(
      message: _copied ? 'Copied' : 'Copy ${widget.label}',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(borderRadius: BorderRadius.circular(7), onTap: _copy, child: row),
    );
  }
}

/// Circle crop editor for the profile picture: drag to position, zoom with the
/// slider, mouse wheel, or pinch. Pops the cropped square as a PNG data URL
/// (PNG keeps a cut-out photo's transparency for the badge), or null.
class _AvatarCropDialog extends StatefulWidget {
  const _AvatarCropDialog({required this.image});
  final ui.Image image;

  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  static const double _viewport = 300;
  // Largest first; smaller sizes are fallbacks for the API's 400 KB limit.
  static const List<int> _outputSizes = [512, 384, 256, 192];
  // 400 KB of image as base64, with headroom for the data-URL prefix.
  static const int _maxDataUrlLength = 540000;
  static const double _maxZoom = 6;

  double zoom = 1;
  Offset offset = Offset.zero;
  double dragStartZoom = 1;
  Offset dragStartOffset = Offset.zero;
  Offset dragStartFocal = Offset.zero;
  bool exporting = false;

  double get _coverScale => _viewport / min(widget.image.width, widget.image.height);

  double get _scale => _coverScale * zoom;

  // The image always covers the whole square, so panning stops at the edges.
  Offset _clampOffset(Offset value) {
    final maxDx = max(0.0, (widget.image.width * _scale - _viewport) / 2);
    final maxDy = max(0.0, (widget.image.height * _scale - _viewport) / 2);
    return Offset(value.dx.clamp(-maxDx, maxDx), value.dy.clamp(-maxDy, maxDy));
  }

  void _zoomTo(double next) {
    next = next.clamp(1.0, _maxZoom);
    setState(() {
      final ratio = next / zoom;
      zoom = next;
      offset = _clampOffset(offset * ratio);
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _zoomTo(zoom * pow(1.0015, -event.scrollDelta.dy).toDouble());
  }

  void _onScaleStart(ScaleStartDetails details) {
    dragStartZoom = zoom;
    dragStartOffset = offset;
    dragStartFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      zoom = (dragStartZoom * details.scale).clamp(1.0, _maxZoom);
      final ratio = zoom / dragStartZoom;
      offset = _clampOffset(dragStartOffset * ratio + (details.localFocalPoint - dragStartFocal));
    });
  }

  Future<String> _encodeAt(int size) async {
    final out = size.toDouble();
    final f = out / _viewport;
    final w = widget.image.width.toDouble();
    final h = widget.image.height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      widget.image,
      Rect.fromLTWH(0, 0, w, h),
      Rect.fromCenter(center: Offset(out / 2, out / 2) + offset * f, width: w * _scale * f, height: h * _scale * f),
      Paint()..filterQuality = FilterQuality.high,
    );
    final image = await recorder.endRecording().toImage(size, size);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('could not encode the image');
    return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
  }

  Future<void> _usePhoto() async {
    setState(() => exporting = true);
    try {
      String? dataUrl;
      for (final size in _outputSizes) {
        dataUrl = await _encodeAt(size);
        if (dataUrl.length <= _maxDataUrlLength) break;
      }
      if (mounted) Navigator.of(context).pop(dataUrl);
    } catch (e) {
      if (mounted) {
        setState(() => exporting = false);
        AppToast.error(context, 'Could not crop image: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: DsColors.popupSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 366),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Adjust profile picture',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: DsColors.heading)),
            const SizedBox(height: 4),
            const Text('Drag to position · pinch, scroll, or use the slider to zoom',
                style: TextStyle(fontSize: 11.5, color: DsColors.faint)),
            const SizedBox(height: 14),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: _viewport,
                  height: _viewport,
                  child: Listener(
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.move,
                        child: CustomPaint(
                          painter: _AvatarCropPainter(image: widget.image, scale: _scale, offset: offset),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.zoom_out, size: 18, color: DsColors.icon),
              Expanded(
                child: Slider(value: zoom, min: 1, max: _maxZoom, activeColor: DsColors.navy, onChanged: _zoomTo),
              ),
              const Icon(Icons.zoom_in, size: 18, color: DsColors.icon),
            ]),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              DsOutlineButton(
                  label: 'Cancel', height: 38, onPressed: exporting ? null : () => Navigator.of(context).pop()),
              const SizedBox(width: 10),
              DsPrimaryButton(
                  label: exporting ? 'Saving…' : 'Use photo',
                  icon: Icons.check,
                  height: 38,
                  onPressed: exporting ? null : _usePhoto),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _AvatarCropPainter extends CustomPainter {
  _AvatarCropPainter({required this.image, required this.scale, required this.offset});
  final ui.Image image;
  final double scale;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xff10142a));
    // The checker shows a cut-out photo as cut out.
    final check = Paint()..color = const Color(0xff1b2143);
    const cell = 11.0;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = (y.isEven ? 0 : 1); x * cell < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), check);
      }
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, w, h),
      Rect.fromCenter(center: center + offset, width: w * scale, height: h * scale),
      Paint()..filterQuality = FilterQuality.high,
    );
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(Rect.fromCircle(center: center, radius: size.shortestSide / 2)),
    );
    canvas.drawPath(outside, Paint()..color = const Color(0x8a000000));
    canvas.drawCircle(
      center,
      size.shortestSide / 2 - .75,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _AvatarCropPainter old) =>
      old.image != image || old.scale != scale || old.offset != offset;
}

/// Icon tile · title and subtitle · switch, the whole row tappable.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.on,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  final bool on;
  final IconData icon;
  final String title;
  final String subtitle;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onChanged == null ? null : () => onChanged!(!on),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? DsColors.navySoft : DsColors.chip,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 19, color: on ? DsColors.navyDeep : DsColors.iconSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: DsColors.heading)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 11.5, color: DsColors.faint2, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 12),
          Switch(value: on, onChanged: onChanged, activeThumbColor: DsColors.navy),
        ]),
      ),
    );
  }
}

/// Shows only as many fixed-height rows as fit between where it sits and the
/// bottom of the window, so the list never makes the page scroll. Re-measures
/// when the window is resized.
class _FitToScreen extends StatefulWidget {
  const _FitToScreen({required this.rowHeight, required this.count, required this.builder});
  final double rowHeight;
  final int count;
  final Widget Function(int rows) builder;

  @override
  State<_FitToScreen> createState() => _FitToScreenState();
}

class _FitToScreenState extends State<_FitToScreen> {
  // What is left below the list: the card's own bottom padding and the page's.
  static const _below = 60.0;
  int? _rows;

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final height = MediaQuery.of(context).size.height;
    final rows = max(1, ((height - top - _below) / widget.rowHeight).floor());
    if (rows != _rows) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    MediaQuery.sizeOf(context); // rebuild (and so re-measure) on resize
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final rows = min(widget.count, _rows ?? 0);
    return SizedBox(
      width: double.infinity,
      child: widget.builder(rows),
    );
  }
}
