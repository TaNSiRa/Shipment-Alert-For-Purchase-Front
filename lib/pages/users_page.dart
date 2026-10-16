part of '../main.dart';

const List<String> kNamePrefixOptions = ['Mr.', 'Mrs.', 'Ms.', 'Miss', 'Dr.'];

/// "Full name (ABBR)", as RAP shows a job position.
String positionLabel(dynamic name, dynamic abbreviation) {
  final full = '${name ?? ''}'.trim();
  final abbr = '${abbreviation ?? ''}'.trim();
  if (full.isEmpty) return abbr;
  if (abbr.isEmpty) return full;
  return '$full ($abbr)';
}

/// Org dropdown lists shared by Manage Users and Profile (RAP's lists).
class OrgOptions {
  const OrgOptions({
    this.branches = const [],
    this.departments = const [],
    this.sections = const [],
    this.positions = const [],
  });
  factory OrgOptions.fromJson(Map<String, dynamic> j) {
    List<String> strings(dynamic v) =>
        (v as List? ?? const []).map((e) => '$e').toList();
    return OrgOptions(
      branches: strings(j['branches']),
      departments: strings(j['departments']),
      sections: strings(j['sections']),
      positions: (j['positions'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
  final List<String> branches;
  final List<String> departments;
  final List<String> sections;
  final List<Map<String, dynamic>> positions;

  /// Position dropdown items; a retired position a user still holds stays
  /// listed so the field does not go blank.
  List<SearchableDropdownItem<int>> positionItems(
      int? current, String? currentLabel) {
    return [
      for (final p in positions)
        SearchableDropdownItem<int>(
            value: intFrom(p['id']),
            label: positionLabel(p['name'], p['abbreviation'])),
      if (current != null && !positions.any((p) => intFrom(p['id']) == current))
        SearchableDropdownItem<int>(
            value: current, label: currentLabel ?? 'Position #$current'),
    ];
  }
}

/// String dropdown items, keeping a legacy value that is no longer listed.
List<SearchableDropdownItem<String>> stringItems(
        List<String> options, String? current) =>
    [
      for (final v in <String>{...options, if (current != null) current})
        SearchableDropdownItem<String>(value: v, label: v),
    ];

String? _blankToNull(dynamic v) {
  final s = '${v ?? ''}'.trim();
  return s.isEmpty ? null : s;
}

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});
  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> roles = [];
  OrgOptions org = const OrgOptions();
  final search = TextEditingController();
  // Multi-select filters beside the search — null means "show all" (RAP).
  Set<String>? _branchFilter;
  Set<String>? _sectionFilter;
  bool loading = true;
  int page = 0;
  /// Rows that fit the table's height (0 until the first layout).
  int pageSize = 0;
  static const _rowH = 56.0;
  String? error;
  int _tick = -1;

  static String _branchOf(Map<String, dynamic> u) => _blankToNull(u['branch']) ?? '-';
  static String _sectionOf(Map<String, dynamic> u) => _blankToNull(u['section']) ?? '-';

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
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final api = AppScope.read(context).api;
    try {
      final r = await api.getJson('/users');
      final ro = await api.getJson('/users/roles');
      final o = await api.getJson('/users/org-options');
      if (!mounted) return;
      setState(() {
        users = (r['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        roles = (ro['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        org = OrgOptions.fromJson(o);
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
    return u['roleCode'] != 'ADMIN';
  }

  InputDecoration _field(String label, {String? error, String? helper}) =>
      InputDecoration(labelText: label, errorText: error, helperText: helper);

  Future<void> _edit([Map<String, dynamic>? u]) async {
    final scope = AppScope.read(context);
    final api = scope.api;
    final isNew = u == null;
    final self = intFrom(u?['id']) == scope.userId;
    final employeeNo = TextEditingController(text: '${u?['employeeNo'] ?? ''}');
    final display = TextEditingController(text: '${u?['displayName'] ?? ''}');
    final full = TextEditingController(text: '${u?['fullName'] ?? ''}');
    final email = TextEditingController(text: '${u?['email'] ?? ''}');
    final phone = TextEditingController(text: '${u?['phone'] ?? ''}');
    final password = TextEditingController();
    String? prefix = _blankToNull(u?['namePrefix']);
    int? positionId = intFrom(u?['positionId']);
    String? branch = _blankToNull(u?['branch']);
    String? department = _blankToNull(u?['department']);
    String? section = _blankToNull(u?['section']);
    String? role = u == null
        ? (roles.any((r) => r['code'] == 'USER') ? 'USER' : null)
        : '${u['roleCode']}';
    bool isActive = u == null ? true : u['isActive'] == true;
    var errors = <String, String>{};
    bool busy = false;
    final positionItems = org.positionItems(
        positionId, positionLabel(u?['positionName'], u?['positionAbbr']));
    // Your own role stays as it is (the server refuses the change too).
    final roleItems = [
      for (final r in roles)
        SearchableDropdownItem<String>(value: '${r['code']}', label: '${r['name']}'),
      if (role != null && !roles.any((r) => r['code'] == role))
        SearchableDropdownItem<String>(value: role, label: roleLabel(role)),
    ];

    final saved = await showGlassDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        Future<void> save() async {
          final next = <String, String>{
            for (final e in {
              'employeeNo': employeeNo.text,
              'displayName': display.text,
              'email': email.text,
              if (isNew) 'password': password.text,
              'role': role ?? '',
              'branch': branch ?? '',
              'department': department ?? '',
              'section': section ?? '',
            }.entries)
              if (e.value.trim().isEmpty) e.key: 'Required',
          };
          if (next['email'] == null &&
              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) {
            next['email'] = 'Invalid email';
          }
          if (isNew && next['password'] == null) {
            final p = passwordPolicyProblem(password.text);
            if (p != null) next['password'] = p;
          }
          setState(() => errors = next);
          if (next.isNotEmpty) return;
          setState(() => busy = true);
          try {
            final body = {
              'employeeNo': employeeNo.text.trim(),
              'displayName': display.text.trim(),
              'fullName': full.text.trim(),
              'namePrefix': prefix ?? '',
              'positionId': positionId,
              'email': email.text.trim(),
              'branch': branch,
              'department': department,
              'section': section,
              'phone': phone.text.trim(),
            };
            if (isNew) {
              final created = await api.postJson('/users', {
                ...body,
                'roleCode': role,
                'password': password.text,
              });
              if (!isActive) {
                await api.patchJson('/users/${created['id']}', {'isActive': false});
              }
            } else {
              await api.patchJson('/users/${u['id']}', {
                ...body,
                if (!self && role != u['roleCode']) 'roleCode': role,
                if (!self && isActive != (u['isActive'] == true)) 'isActive': isActive,
              });
            }
            if (ctx.mounted) Navigator.pop(ctx, true);
          } on ApiException catch (e) {
            setState(() => busy = false);
            if (ctx.mounted) AppToast.error(ctx, friendlyError(e.message));
          }
        }

        Widget box(Widget child) => SizedBox(width: 330, child: child);
        Widget dropdown<T>(String label, String key, T? value,
                List<SearchableDropdownItem<T>> items, ValueChanged<T?>? onChanged,
                {String? helper}) =>
            box(SearchableDropdownField<T>(
              value: value,
              enabled: onChanged != null,
              decoration: _field(label, error: errors[key], helper: helper),
              items: items,
              onChanged: onChanged == null
                  ? null
                  : (v) => setState(() {
                        errors.remove(key);
                        onChanged(v);
                      }),
            ));
        Widget text(String label, String key, TextEditingController c,
                {bool obscure = false, String? helper}) =>
            box(TextField(
              controller: c,
              obscureText: obscure,
              onChanged: (_) => setState(() => errors.remove(key)),
              decoration: _field(label, error: errors[key], helper: helper),
            ));

        return AlertDialog(
          backgroundColor: DsColors.popupSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          title: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: DsColors.navy, borderRadius: BorderRadius.circular(8)),
              child: Icon(
                  isNew ? Icons.person_add_alt_1 : Icons.manage_accounts_outlined,
                  color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isNew ? 'Create user' : 'Edit user',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                Text('User identity, organization, and access',
                    style: Theme.of(ctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: const Color(0xff64748b))),
              ]),
            ),
          ]),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: DsColors.glass,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xffdbe3ea)),
                ),
                child: Wrap(spacing: 12, runSpacing: 12, children: [
                  text('Employee no', 'employeeNo', employeeNo),
                  text('Display name', 'displayName', display),
                  dropdown<String>('Title (optional)', 'prefix', prefix,
                      stringItems(kNamePrefixOptions, prefix), (v) => prefix = v),
                  box(TextField(
                      controller: full,
                      decoration: _field('Full name (optional)'))),
                  dropdown<int>('Position (optional)', 'position', positionId,
                      positionItems, (v) => positionId = v),
                  text('Email', 'email', email),
                  if (isNew)
                    text('Initial password', 'password', password,
                        obscure: true, helper: kPasswordRuleHint),
                  dropdown<String>('Role', 'role', role, roleItems,
                      self ? null : (v) => role = v,
                      helper: self
                          ? 'Your own role — another admin can change it'
                          : null),
                  dropdown<String>('Branch', 'branch', branch,
                      stringItems(org.branches, branch), (v) => branch = v),
                  dropdown<String>('Department', 'department', department,
                      stringItems(org.departments, department), (v) => department = v),
                  dropdown<String>('Section', 'section', section,
                      stringItems(org.sections, section), (v) => section = v),
                  box(TextField(controller: phone, decoration: _field('Phone'))),
                  SizedBox(
                    width: 330,
                    height: 48,
                    child: Row(children: [
                      // Switching your own account off is a lockout, not an
                      // edit — the server refuses it too.
                      Switch(
                          value: isActive,
                          onChanged: self ? null : (v) => setState(() => isActive = v)),
                      const SizedBox(width: 8),
                      Text(self ? 'Active (your own account)' : 'Active',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Saving…' : 'Save')),
          ],
        );
      }),
    );
    for (final c in [employeeNo, display, full, email, phone, password]) {
      c.dispose();
    }
    if (saved == true) {
      if (mounted) AppToast.success(context, isNew ? 'User created' : 'User saved');
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
      obscure: true,
      minLength: 1,
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
            'Password reset — ${u['displayName']} must choose a new one at the next sign-in');
    unawaited(load());
  }

  Future<void> _unlock(Map<String, dynamic> u) async {
    final api = AppScope.read(context).api;
    await guard(context, () => api.postJson('/users/${u['id']}/unlock', {}),
        success: 'Account unlocked');
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
    final q = search.text.toLowerCase().trim();
    // Filter options come from every user, so the choices stay put whatever
    // is selected (RAP).
    final allBranches = <String>{for (final u in users) _branchOf(u)}.toList()..sort();
    final allSections = <String>{for (final u in users) _sectionOf(u)}.toList()..sort();
    final shown = users.where((u) {
      if (_branchFilter != null && !_branchFilter!.contains(_branchOf(u))) return false;
      if (_sectionFilter != null && !_sectionFilter!.contains(_sectionOf(u))) return false;
      if (q.isEmpty) return true;
      return '${u['employeeNo'] ?? ''} ${u['displayName']} ${u['fullName'] ?? ''} ${u['email']} ${u['branch'] ?? ''} ${u['section'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: DsCard(
        padding: EdgeInsets.zero,
        clip: true,
        color: DsColors.sheet,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: search,
                  onChanged: (_) => setState(() => page = 0),
                  decoration: dsInput(
                      hint: 'Search name, email, employee no…', icon: Icons.search),
                ),
              ),
              const SizedBox(width: 12),
              MultiFilterButton(
                icon: Icons.location_on_outlined,
                allLabel: 'All branches',
                filter: _branchFilter,
                options: allBranches,
                labelOf: (v) => v,
                dialogTitle: 'Filter branch',
                height: 38,
                onApply: (v) => setState(() {
                  _branchFilter = v;
                  page = 0;
                }),
              ),
              const SizedBox(width: 12),
              MultiFilterButton(
                icon: Icons.account_tree_outlined,
                allLabel: 'All sections',
                filter: _sectionFilter,
                options: allSections,
                labelOf: (v) => v,
                dialogTitle: 'Filter section',
                height: 38,
                onApply: (v) => setState(() {
                  _sectionFilter = v;
                  page = 0;
                }),
              ),
              const Spacer(),
              DsPrimaryButton(
                  label: 'New user',
                  icon: Icons.person_add_alt_1,
                  height: 40,
                  onPressed: () => _edit()),
            ]),
          ),
          Expanded(
            child: loading
                ? MinWidthScroll(minWidth: 960, child: _skeleton())
                : error != null
                    ? Center(child: ErrorPanel(message: error!, onRetry: load))
                    : MinWidthScroll(
                        minWidth: 960,
                        child: Builder(builder: (context) {
                          final size = max(1, pageSize);
                          final pages = max(1, (shown.length / size).ceil());
                          final p = page.clamp(0, pages - 1);
                          return Column(children: [
                            _header(),
                            Expanded(
                              child: shown.isEmpty
                                  ? const Center(
                                      child: Text('No users found',
                                          style: TextStyle(color: DsColors.faint2)))
                                  : DsFitRows(
                                      rowHeight: _rowH,
                                      onFit: (fit) {
                                        if (fit == pageSize) return;
                                        final first = page * max(1, pageSize);
                                        setState(() {
                                          pageSize = fit;
                                          page = first ~/ fit;
                                        });
                                      },
                                      builder: (_, rowH) => Column(children: [
                                        for (final u in shown.skip(p * size).take(size))
                                          SizedBox(height: rowH, child: _row(scope, u)),
                                      ]),
                                    ),
                            ),
                            PaginationBar(
                              page: p,
                              totalItems: shown.length,
                              pageSize: size,
                              onChanged: (n) => setState(() => page = n),
                            ),
                          ]);
                        })),
          ),
        ]),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: const BoxDecoration(
          color: DsColors.subtle,
          border: Border(
              top: BorderSide(color: DsColors.line),
              bottom: BorderSide(color: DsColors.line)),
        ),
        child: const Row(children: [
          Expanded(flex: 14, child: DsSectionLabel('Name')),
          Expanded(flex: 16, child: DsSectionLabel('Email')),
          SizedBox(width: 150, child: DsSectionLabel('Role')),
          SizedBox(width: 120, child: DsSectionLabel('Branch')),
          SizedBox(width: 150, child: DsSectionLabel('Section')),
          SizedBox(width: 130, child: DsSectionLabel('Status')),
          SizedBox(width: 120, child: DsSectionLabel('Action')),
        ]),
      );

  /// [_row]'s columns, ghosted.
  Widget _skeleton() => DsSkeletonRows(
        rowHeight: _rowH,
        columns: [
          DsSkelCol(
              (i) => Row(children: [
                    DsSkel.circle(30),
                    const SizedBox(width: 10),
                    DsSkel.line(DsSkel.vary(i, 110)),
                  ]),
              flex: 14),
          DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 4, 170)), flex: 16),
          DsSkelCol((i) => DsSkel.tag(DsSkel.vary(i + 1, 84, .3)), width: 150),
          DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 2, 80)), width: 120),
          DsSkelCol((i) => DsSkel.line(DsSkel.vary(i + 3, 100)), width: 150),
          DsSkelCol((i) => DsSkel.tag(64), width: 130),
          DsSkelCol((_) => DsSkel.box(60, 22, radius: 6), width: 120),
        ],
      );

  Widget _row(AppScope scope, Map<String, dynamic> u) {
    final active = u['isActive'] == true;
    // Locked by failed sign-ins (the server only sends a lock still in force).
    final locked = active && u['lockedUntil'] != null;
    final manage = _canManage(u);
    final self = intFrom(u['id']) == scope.userId;
    final roleCode = '${u['roleCode']}';
    final roleBg = switch (roleCode) {
      'ADMIN' => DsColors.navy,
      'SECTION_ADMIN' => DsColors.purpleFg,
      'VIEWER' => DsColors.greenFg,
      _ => DsColors.faint,
    };
    final ok = active && !locked;
    const cell = TextStyle(fontSize: 12.5, color: DsColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: DsColors.lineSoft))),
      child: Row(children: [
        Expanded(
          flex: 14,
          child: Row(children: [
            UserAvatar(user: u, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text('${u['displayName']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: DsColors.heading)),
            ),
          ]),
        ),
        Expanded(
          flex: 16,
          child: Text('${u['email']}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: cell),
        ),
        SizedBox(
          width: 150,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration:
                  BoxDecoration(color: roleBg, borderRadius: BorderRadius.circular(6)),
              child: Text('${u['roleName'] ?? roleLabel(roleCode)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ),
        SizedBox(
            width: 120,
            child: Text(_branchOf(u),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: cell)),
        SizedBox(
            width: 150,
            child: Text(_sectionOf(u),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: cell)),
        SizedBox(
          width: 130,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                  color: ok ? DsColors.greenBg : DsColors.redBg,
                  borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(locked ? Icons.lock : (active ? Icons.check_circle : Icons.block),
                    size: 14, color: ok ? DsColors.greenFg : DsColors.redFg),
                const SizedBox(width: 5),
                Text(locked ? 'Locked' : (active ? 'Active' : 'Inactive'),
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: ok ? DsColors.greenFg : DsColors.redFg)),
              ]),
            ),
            if (u['mustChangePassword'] == true) ...[
              const SizedBox(width: 6),
              const Tooltip(
                  message: 'Must choose a new password at the next sign-in',
                  child: Icon(Icons.key, size: 15, color: DsColors.amberFg)),
            ],
          ]),
        ),
        SizedBox(
          width: 120,
          child: Row(children: [
            DsIconButton(
                icon: Icons.edit,
                iconSize: 17,
                size: 30,
                onTap: manage ? () => _edit(u) : null,
                tooltip: manage
                    ? 'Edit user'
                    : 'System administrators are managed by a system administrator'),
            if (manage)
              DsIconButton(
                  icon: Icons.key,
                  iconSize: 17,
                  size: 30,
                  // Your own password is changed in Profile › Security, where
                  // the current one is asked for. A system admin may still
                  // reset theirs here.
                  onTap: self && !scope.isAdmin ? null : () => _resetPassword(u),
                  tooltip: self && !scope.isAdmin
                      ? 'Change your own password in Profile › Security'
                      : 'Reset password'),
            if (locked && manage)
              DsIconButton(
                  icon: Icons.lock_open,
                  iconSize: 17,
                  size: 30,
                  onTap: () => _unlock(u),
                  tooltip: 'Unlock sign-in (locked after repeated wrong passwords)'),
          ]),
        ),
      ]),
    );
  }
}
