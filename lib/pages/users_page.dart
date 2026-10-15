part of '../main.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> roles = [];
  String filter = '';
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

  Future<void> load() async {
    final api = AppScope.read(context).api;
    try {
      final r = await api.getJson('/users');
      final ro = await api.getJson('/users/roles');
      if (!mounted) return;
      setState(() {
        users = (r['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        roles = (ro['data'] as List)
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

  bool _canManage(Map<String, dynamic> u) {
    final scope = AppScope.read(context);
    if (scope.isAdmin) return true;
    return u['roleCode'] == 'USER' || u['roleCode'] == 'VIEWER';
  }

  Future<void> _edit([Map<String, dynamic>? u]) async {
    final scope = AppScope.read(context);
    final api = scope.api;
    final isNew = u == null;
    final email = TextEditingController(text: '${u?['email'] ?? ''}');
    final display = TextEditingController(text: '${u?['displayName'] ?? ''}');
    final full = TextEditingController(text: '${u?['fullName'] ?? ''}');
    final empNo = TextEditingController(text: '${u?['employeeNo'] ?? ''}');
    final dept =
        TextEditingController(text: '${u?['department'] ?? 'Purchase'}');
    final position = TextEditingController(text: '${u?['position'] ?? ''}');
    final phone = TextEditingController(text: '${u?['phone'] ?? ''}');
    final password = TextEditingController();
    String role = '${u?['roleCode'] ?? 'USER'}';
    String? prefix = u?['namePrefix'] as String?;
    bool canEdit = (u?['membership']?['canEdit'] ?? true) == true;
    bool sectionAdmin = (u?['membership']?['isSectionAdmin'] ?? false) == true;
    String? error;
    bool busy = false;
    final self = intFrom(u?['id']) == scope.userId;

    final saved = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> save() async {
          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
              .hasMatch(email.text.trim())) {
            return setState(() => error = 'Enter a valid email');
          }
          if (display.text.trim().isEmpty) {
            return setState(() => error = 'Enter the display name');
          }
          if (isNew) {
            final p = passwordPolicyProblem(password.text);
            if (p != null) {
              return setState(() => error = 'Temporary password: $p');
            }
          }
          setState(() {
            busy = true;
            error = null;
          });
          try {
            final body = {
              'email': email.text.trim(),
              'displayName': display.text.trim(),
              'fullName': full.text.trim(),
              'namePrefix': prefix ?? '',
              'employeeNo': empNo.text.trim(),
              'department': dept.text.trim(),
              'position': position.text.trim(),
              'phone': phone.text.trim(),
            };
            if (isNew) {
              await api.postJson('/users', {
                ...body,
                'roleCode': role,
                'password': password.text,
                'canEdit': role != 'VIEWER' && canEdit,
                'isSectionAdmin': sectionAdmin,
              });
            } else {
              await api.patchJson('/users/${u['id']}', {
                ...body,
                if (!self && role != u['roleCode']) 'roleCode': role
              });
              final m = u['membership'] as Map?;
              final changes = <String, dynamic>{};
              if (role != 'VIEWER' && m?['canEdit'] != canEdit) {
                changes['canEdit'] = canEdit;
              }
              if (scope.isAdmin &&
                  role == 'SECTION_ADMIN' &&
                  m?['isSectionAdmin'] != sectionAdmin) {
                changes['isSectionAdmin'] = sectionAdmin;
              }
              if (changes.isNotEmpty) {
                await api.patchJson('/users/${u['id']}/membership', changes);
              }
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on ApiException catch (e) {
            setState(() {
              busy = false;
              error = friendlyError(e.message);
            });
          }
        }

        return AppDialog(
          title: isNew
              ? 'Add user to ${scope.section['name']}'
              : 'Edit ${u['displayName']}',
          icon: isNew ? Icons.person_add_alt : Icons.manage_accounts_outlined,
          width: 640,
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
                      for (final p in const [
                        'Mr.',
                        'Mrs.',
                        'Ms.',
                        'Miss',
                        'Dr.'
                      ])
                        DropdownMenuItem(value: p, child: Text(p)),
                    ],
                    onChanged: (v) => setState(() => prefix = v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: DsLabeledField(
                      label: 'Display name *',
                      child: TextField(
                          controller: display,
                          decoration: dsInput(hint: 'Somchai')))),
              const SizedBox(width: 12),
              Expanded(
                  flex: 2,
                  child: DsLabeledField(
                      label: 'Full name',
                      child:
                          TextField(controller: full, decoration: dsInput()))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  flex: 2,
                  child: DsLabeledField(
                      label: 'Email (sign-in) *',
                      child: TextField(
                          controller: email,
                          decoration: dsInput(icon: Icons.alternate_email)))),
              const SizedBox(width: 12),
              Expanded(
                  child: DsLabeledField(
                      label: 'Employee no.',
                      child:
                          TextField(controller: empNo, decoration: dsInput()))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: DsLabeledField(
                      label: 'Department',
                      child:
                          TextField(controller: dept, decoration: dsInput()))),
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
                      child:
                          TextField(controller: phone, decoration: dsInput()))),
            ]),
            const SizedBox(height: 16),
            const DsSectionLabel('Access'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in roles)
                ChoiceChip(
                  label: Text('${r['name']}'),
                  selected: role == r['code'],
                  onSelected: self
                      ? null
                      : (_) => setState(() {
                            role = '${r['code']}';
                            if (role == 'VIEWER') canEdit = false;
                            if (role != 'SECTION_ADMIN') sectionAdmin = false;
                          }),
                ),
            ]),
            const SizedBox(height: 6),
            Text(
              switch (role) {
                'ADMIN' => 'Everything in every section, plus system settings.',
                'SECTION_ADMIN' =>
                  'Manages users, masters, workflow and settings of the sections where "Section admin" is on.',
                'VIEWER' =>
                  'Can look at everything in the section but change nothing.',
                _ =>
                  'Imports POs and marks steps done (when "Can edit" is on).',
              },
              style: DsType.metaSm,
            ),
            if (role != 'VIEWER' && role != 'ADMIN')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: canEdit,
                title: const Text('Can edit in this section',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text('Import POs, add POs and mark steps done',
                    style: DsType.metaSm),
                onChanged: (v) => setState(() => canEdit = v),
              ),
            if (role == 'SECTION_ADMIN' && scope.isAdmin)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: sectionAdmin,
                title: const Text('Section admin of this section',
                    style: TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() => sectionAdmin = v),
              ),
            if (isNew) ...[
              const SizedBox(height: 10),
              DsLabeledField(
                label: 'Temporary password *',
                child: TextField(
                    controller: password,
                    decoration: dsInput(
                        icon: Icons.key_outlined, hint: kPasswordRuleHint)),
              ),
              const SizedBox(height: 6),
              const Text(
                  'The person must choose their own password at the first sign-in.',
                  style: DsType.metaSm),
            ],
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
                onPressed: busy ? null : () => Navigator.pop(ctx, false)),
            DsPrimaryButton(
                label: busy ? 'Saving…' : 'Save',
                icon: Icons.save_outlined,
                height: 40,
                onPressed: busy ? null : save),
          ],
        );
      }),
    );
    if (saved == true) {
      if (mounted) {
        AppToast.success(context, isNew ? 'User added' : 'User updated');
      }
      unawaited(load());
    }
  }

  Future<void> _addExisting() async {
    final api = AppScope.read(context).api;
    final search = TextEditingController();
    List<Map<String, dynamic>> found = [];
    Timer? debounce;
    final added = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AppDialog(
          title: 'Add an existing user',
          subtitle: 'Someone who already has an account in another section',
          icon: Icons.group_add_outlined,
          width: 520,
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: search,
              autofocus: true,
              decoration: dsInput(
                  hint: 'Type a name, email or employee no.',
                  icon: Icons.search),
              onChanged: (v) {
                debounce?.cancel();
                debounce = Timer(const Duration(milliseconds: 300), () async {
                  try {
                    final r = await api.getJson(
                        '/users/lookup?q=${Uri.encodeQueryComponent(v)}');
                    setState(() => found = (r['data'] as List)
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList());
                  } catch (_) {}
                });
              },
            ),
            const SizedBox(height: 10),
            if (found.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No match yet', style: DsType.meta))
            else
              for (final f in found)
                ListTile(
                  leading: UserAvatar(user: f, size: 32),
                  title: Text('${f['displayName']}'),
                  subtitle:
                      Text('${f['email']} · ${roleLabel('${f['roleCode']}')}'),
                  trailing: DsPrimaryButton(
                    label: 'Add',
                    height: 34,
                    onPressed: () async {
                      try {
                        await api.postJson('/users/${f['id']}/join', {});
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        if (ctx.mounted) {
                          AppToast.error(ctx, friendlyError(e.message));
                        }
                      }
                    },
                  ),
                ),
          ]),
          actions: [
            DsOutlineButton(
                label: 'Close',
                height: 40,
                onPressed: () => Navigator.pop(ctx, false))
          ],
        );
      }),
    );
    debounce?.cancel();
    if (added == true) {
      if (mounted) AppToast.success(context, 'User added to the section');
      unawaited(load());
    }
  }

  Future<void> _resetPassword(Map<String, dynamic> u) async {
    final pass = await askText(
      context,
      title: 'Reset password — ${u['displayName']}',
      label: 'New temporary password',
      helper:
          'They will be signed out everywhere and must choose their own password at the next sign-in. $kPasswordRuleHint.',
      confirmLabel: 'Reset password',
      minLength: 8,
    );
    if (pass == null || !mounted) return;
    final problem = passwordPolicyProblem(pass);
    if (problem != null) {
      AppToast.error(context, problem);
      return;
    }
    final api = AppScope.read(context).api;
    await guard(
        context,
        () => api.postJson(
            '/users/${u['id']}/reset-password', {'newPassword': pass}),
        success:
            'Password reset — tell ${u['displayName']} the temporary password');
    unawaited(load());
  }

  Future<void> _action(String action, Map<String, dynamic> u) async {
    final api = AppScope.read(context).api;
    switch (action) {
      case 'edit':
        await _edit(u);
      case 'reset':
        await _resetPassword(u);
      case 'unlock':
        await guard(context, () => api.postJson('/users/${u['id']}/unlock', {}),
            success: 'Account unlocked');
      case 'deactivate':
        if (await confirmAction(context,
            title: 'Deactivate ${u['displayName']}?',
            message:
                'They are signed out immediately and cannot sign in again until reactivated.',
            confirmLabel: 'Deactivate',
            danger: true)) {
          if (!mounted) return;
          await guard(context,
              () => api.patchJson('/users/${u['id']}', {'isActive': false}),
              success: 'Account deactivated');
        }
      case 'activate':
        await guard(context,
            () => api.patchJson('/users/${u['id']}', {'isActive': true}),
            success: 'Account reactivated');
      case 'remove':
        if (await confirmAction(context,
            title: 'Remove ${u['displayName']} from this section?',
            message:
                'Their account stays (for other sections); they just lose access here.',
            confirmLabel: 'Remove',
            danger: true)) {
          if (!mounted) return;
          await guard(
              context, () => api.deleteJson('/users/${u['id']}/membership'),
              success: 'Removed from the section');
        }
    }
    unawaited(load());
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    if (!scope.isSectionAdmin) {
      return const PageBody(children: [
        InfoStrip(
            icon: Icons.lock_outline,
            text: 'Only section admins can manage users.'),
      ]);
    }
    final q = filter.toLowerCase();
    final shown = users
        .where((u) =>
            q.isEmpty ||
            '${u['displayName']} ${u['fullName']} ${u['email']} ${u['employeeNo']}'
                .toLowerCase()
                .contains(q))
        .toList();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
        child: Row(children: [
          SizedBox(
            width: 320,
            child: TextField(
                onChanged: (v) => setState(() => filter = v),
                decoration:
                    dsInput(hint: 'Search people…', icon: Icons.search)),
          ),
          const SizedBox(width: 12),
          Text(
              '${plural(users.length, 'person', 'people')} in ${scope.section['name']}',
              style: DsType.meta),
          const Spacer(),
          DsOutlineButton(
              label: 'Add existing user',
              icon: Icons.group_add_outlined,
              height: 40,
              onPressed: _addExisting),
          const SizedBox(width: 8),
          DsPrimaryButton(
              label: 'New user',
              icon: Icons.person_add_alt,
              height: 40,
              onPressed: () => _edit()),
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
                ? const DsSkeletonList(rows: 6, avatar: true)
                : error != null
                    ? Center(child: ErrorPanel(message: error!, onRetry: load))
                    : MinWidthScroll(
                        minWidth: 1050,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, color: DsColors.lineSoft),
                          itemBuilder: (_, i) => _row(scope, shown[i]),
                        )),
          ),
        ),
      ),
    ]);
  }

  Widget _row(AppScope scope, Map<String, dynamic> u) {
    final m = u['membership'] as Map?;
    final active = u['isActive'] == true;
    final locked = u['lockedUntil'] != null;
    final manage = _canManage(u);
    final self = intFrom(u['id']) == scope.userId;
    final (roleFg, roleBg) = switch ('${u['roleCode']}') {
      'ADMIN' => (DsColors.redFg, DsColors.redBg),
      'SECTION_ADMIN' => (DsColors.purpleFg, DsColors.purpleBg),
      'VIEWER' => (DsColors.muted, DsColors.chip),
      _ => (DsColors.blueFg, DsColors.blueBg),
    };
    return Opacity(
      opacity: active ? 1 : .55,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          UserAvatar(user: u, size: 38),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(
                        '${u['namePrefix'] ?? ''} ${u['displayName']}'.trim(),
                        overflow: TextOverflow.ellipsis,
                        style: DsType.rowTitle)),
                if (self) ...[const SizedBox(width: 6), const DsTag('You')],
              ]),
              Text(
                  '${u['email']}${'${u['employeeNo'] ?? ''}'.isEmpty ? '' : ' · ${u['employeeNo']}'}',
                  overflow: TextOverflow.ellipsis,
                  style: DsType.metaSm),
            ]),
          ),
          Expanded(
              flex: 2,
              child: Text('${u['position'] ?? u['department'] ?? '-'}',
                  overflow: TextOverflow.ellipsis, style: DsType.meta)),
          SizedBox(
              width: 120,
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: DsTag(roleLabel('${u['roleCode']}'),
                      color: roleFg, bg: roleBg))),
          SizedBox(
            width: 210,
            child: Wrap(spacing: 4, runSpacing: 4, children: [
              if (m?['isSectionAdmin'] == true)
                const DsTag('Section admin',
                    color: DsColors.purpleFg, bg: DsColors.purpleBg),
              if (u['roleCode'] != 'ADMIN')
                m?['canEdit'] == true
                    ? const DsTag('Can edit',
                        color: DsColors.greenFg, bg: DsColors.greenBg)
                    : const DsTag('Read only'),
              if (!active)
                const DsTag('Inactive',
                    color: DsColors.redFg, bg: DsColors.redBg),
              if (locked)
                const DsTag('Locked',
                    color: DsColors.redFg, bg: DsColors.redBg),
              if (u['mustChangePassword'] == true)
                const DsTag('Temp password',
                    color: DsColors.amberFg, bg: DsColors.amberBg),
              if (u['receiveDailyMail'] == true)
                const Tooltip(
                    message: 'Gets the daily email',
                    child: Icon(Icons.mail_outline,
                        size: 16, color: DsColors.iconSoft)),
            ]),
          ),
          SizedBox(
              width: 150,
              child: Text(
                  u['lastLoginAt'] == null
                      ? 'Never signed in'
                      : 'Last in ${fmtDateTime(u['lastLoginAt'])}',
                  style: DsType.metaSm)),
          SizedBox(
            width: 48,
            child: !manage
                ? const SizedBox()
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert,
                        size: 19, color: DsColors.icon),
                    onSelected: (v) => _action(v, u),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                              dense: true,
                              leading: Icon(Icons.edit_outlined, size: 18),
                              title: Text('Edit'))),
                      const PopupMenuItem(
                          value: 'reset',
                          child: ListTile(
                              dense: true,
                              leading: Icon(Icons.key_outlined, size: 18),
                              title: Text('Reset password'))),
                      if (locked)
                        const PopupMenuItem(
                            value: 'unlock',
                            child: ListTile(
                                dense: true,
                                leading: Icon(Icons.lock_open, size: 18),
                                title: Text('Unlock'))),
                      if (!self && active)
                        const PopupMenuItem(
                            value: 'deactivate',
                            child: ListTile(
                                dense: true,
                                leading:
                                    Icon(Icons.person_off_outlined, size: 18),
                                title: Text('Deactivate'))),
                      if (!self && !active)
                        const PopupMenuItem(
                            value: 'activate',
                            child: ListTile(
                                dense: true,
                                leading: Icon(Icons.person_outline, size: 18),
                                title: Text('Reactivate'))),
                      if (!self && m != null)
                        const PopupMenuItem(
                            value: 'remove',
                            child: ListTile(
                                dense: true,
                                leading:
                                    Icon(Icons.group_remove_outlined, size: 18),
                                title: Text('Remove from section'))),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}
