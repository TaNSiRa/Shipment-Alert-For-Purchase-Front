part of '../main.dart';

/// Owns the signed-in session and everything around the pages: login, the
/// PDPA and first-password gates, section choice, idle sign-out, realtime
/// refresh, and the glass frame (side nav + top bar).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

enum _Stage { booting, login, consent, sectionPick, app }

class _AppShellState extends State<AppShell> {
  late final ApiClient api = ApiClient(onUnauthorized: _onUnauthorized);
  final RealtimeClient realtime = RealtimeClient();

  _Stage stage = _Stage.booting;
  Map<String, dynamic>? me;
  Map<String, dynamic>? section;
  AppPage page = AppPage.dashboard;
  Map<String, dynamic>? pageArgs;
  int pageKey = 0;
  int refreshTick = 0;
  bool navCollapsed = _readPref('psa.navCollapsed') == '1';
  Map<String, dynamic> health = const {'api': 'checking', 'database': 'checking'};
  List<dynamic> alerts = const [];

  Timer? _healthTimer;
  Timer? _idleTimer;
  Timer? _warnTimer;
  Timer? _refreshDebounce;
  DateTime _lastKeepAlive = DateTime.fromMillisecondsSinceEpoch(0);
  bool _warningOpen = false;

  static String? _readPref(String key) {
    try {
      return html.window.localStorage[key];
    } catch (_) {
      return null;
    }
  }

  static void _writePref(String key, String? value) {
    try {
      if (value == null) {
        html.window.localStorage.remove(key);
      } else {
        html.window.localStorage[key] = value;
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadHealth());
    _healthTimer = Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_loadHealth()));
    unawaited(_restoreSession());
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _idleTimer?.cancel();
    _warnTimer?.cancel();
    _refreshDebounce?.cancel();
    realtime.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- session

  Future<void> _loadHealth() async {
    try {
      final result = await api.getJson('/health');
      if (mounted) setState(() => health = result);
    } catch (_) {
      if (mounted) setState(() => health = const {'api': 'offline', 'database': 'offline'});
    }
  }

  Future<void> _restoreSession() async {
    final started = DateTime.now();
    try {
      final result = await api.getJson('/auth/session');
      _applyLogin(result);
    } catch (_) {
      // No live session: show the login page (after a short beat so the
      // splash does not flash).
      final wait = const Duration(milliseconds: 500) - DateTime.now().difference(started);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (mounted) setState(() => stage = _Stage.login);
    }
  }

  Future<String?> login(String email, String password) async {
    try {
      final result = await api.postJson('/auth/login', {'email': email, 'password': password});
      _applyLogin(result);
      return null;
    } on ApiException catch (e) {
      return friendlyError(e.message);
    } catch (_) {
      return 'Cannot reach the server. Check that the API is running.';
    }
  }

  void _applyLogin(Map<String, dynamic> result) {
    api.token = '${result['token']}';
    if (result['csrfToken'] != null) api.csrfToken = '${result['csrfToken']}';
    me = Map<String, dynamic>.from(result['user'] as Map);
    realtime.connect(baseUrl: AppConfig.apiBaseUrl, token: api.token!, onEvent: _onRealtime);
    _armIdleTimer();
    _advanceGates();
  }

  /// Walks the gates in order: consent -> first password -> section.
  void _advanceGates() {
    if (!mounted || me == null) return;
    if (me!['pdpaConsentAccepted'] != true) {
      setState(() => stage = _Stage.consent);
      return;
    }
    if (me!['mustChangePassword'] == true) {
      setState(() => stage = _Stage.consent);
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_forcePasswordChange()));
      return;
    }
    final sections = (me!['sections'] as List? ?? const []).cast<dynamic>();
    final remembered = _readPref('psa.section');
    final match = sections.cast<Map>().where((s) => s['code'] == remembered).toList();
    if (match.isNotEmpty) {
      _enterSection(Map<String, dynamic>.from(match.first));
    } else if (sections.length == 1) {
      _enterSection(Map<String, dynamic>.from(sections.first as Map));
    } else {
      setState(() => stage = _Stage.sectionPick);
    }
  }

  Future<void> acceptConsent() async {
    final result = await guard(context, () => api.postJson('/auth/pdpa-consent', {}));
    if (result == null) return;
    api.token = '${result['token']}';
    if (result['csrfToken'] != null) api.csrfToken = '${result['csrfToken']}';
    me = Map<String, dynamic>.from(result['user'] as Map);
    _advanceGates();
  }

  Future<void> _forcePasswordChange() async {
    if (!mounted) return;
    final result = await showFirstPasswordDialog(context, api);
    if (result == null) {
      await logout();
      return;
    }
    api.token = '${result['token']}';
    if (result['csrfToken'] != null) api.csrfToken = '${result['csrfToken']}';
    me = {...?me, 'mustChangePassword': false};
    realtime.connect(baseUrl: AppConfig.apiBaseUrl, token: api.token!, onEvent: _onRealtime);
    if (mounted) AppToast.success(context, 'Password changed — welcome!');
    _advanceGates();
  }

  void _enterSection(Map<String, dynamic> s) {
    _writePref('psa.section', '${s['code']}');
    api.sectionCode = '${s['code']}';
    realtime.joinSection('${s['code']}');
    setState(() {
      section = s;
      stage = _Stage.app;
      page = AppPage.dashboard;
      pageArgs = null;
      pageKey++;
    });
    unawaited(_loadAlerts());
  }

  Future<void> _reloadMe() async {
    try {
      final result = await api.getJson('/auth/me');
      final fresh = Map<String, dynamic>.from(result['user'] as Map);
      final sections = (fresh['sections'] as List? ?? const []).cast<Map>();
      final current = sections.where((s) => s['code'] == section?['code']).toList();
      if (!mounted) return;
      setState(() {
        me = fresh;
        if (current.isNotEmpty) section = Map<String, dynamic>.from(current.first);
      });
      if (current.isEmpty && section != null) {
        // Access to this section was taken away while it was open.
        AppToast.info(context, 'Your access to ${section?['name']} has changed.');
        setState(() {
          section = null;
          stage = _Stage.sectionPick;
        });
      }
    } catch (_) {}
  }

  void _onUnauthorized() {
    if (stage == _Stage.login) return;
    _signedOut(message: 'Your session has ended. Please sign in again.');
  }

  Future<void> logout() async {
    try {
      await api.postJson('/auth/logout', {});
    } catch (_) {}
    _signedOut();
  }

  void _signedOut({String? message}) {
    realtime.dispose();
    _idleTimer?.cancel();
    _warnTimer?.cancel();
    IdleClock.deadline = null;
    api.token = null;
    api.csrfToken = null;
    api.sectionCode = null;
    if (!mounted) return;
    setState(() {
      me = null;
      section = null;
      alerts = const [];
      stage = _Stage.login;
    });
    if (message != null) AppToast.info(context, message);
  }

  // ------------------------------------------------------------- idle / live

  void _armIdleTimer() {
    _idleTimer?.cancel();
    _warnTimer?.cancel();
    const idle = Duration(minutes: AppConfig.idleTimeoutMinutes);
    IdleClock.deadline = DateTime.now().add(idle);
    _warnTimer = Timer(idle - IdleClock.warnLead, () => unawaited(_showIdleWarning()));
    _idleTimer = Timer(idle, () {
      if (me != null) _signedOut(message: 'Signed out after ${AppConfig.idleTimeoutMinutes} minutes without activity.');
    });
  }

  void _onActivity() {
    if (me == null || _warningOpen) return;
    _armIdleTimer();
    // Keep the server's rolling session cookie alive too — at most once a minute.
    if (DateTime.now().difference(_lastKeepAlive) > const Duration(minutes: 1)) {
      _lastKeepAlive = DateTime.now();
      unawaited(api.getJson('/auth/keepalive').catchError((_) => <String, dynamic>{}));
    }
  }

  Future<void> _showIdleWarning() async {
    if (!mounted || me == null) return;
    _warningOpen = true;
    final stay = await showGlassDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppDialog(
        title: 'Still there?',
        icon: Icons.timer_outlined,
        width: 420,
        body: const Text('You will be signed out in 2 minutes because there has been no activity.',
            style: TextStyle(fontSize: 13.5, color: DsColors.text)),
        actions: [
          DsOutlineButton(label: 'Sign out', height: 40, onPressed: () => Navigator.pop(ctx, false)),
          DsPrimaryButton(label: 'Stay signed in', height: 40, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    _warningOpen = false;
    if (stay == true) {
      _lastKeepAlive = DateTime.fromMillisecondsSinceEpoch(0);
      _onActivity();
    } else if (stay == false) {
      await logout();
    }
  }

  void _onRealtime(String event, dynamic data) {
    if (!mounted) return;
    if (event == 'users.updated' || event == 'sections.updated') unawaited(_reloadMe());
    // Several events often arrive together (an import touches many POs) —
    // one refresh for the burst.
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => refreshTick++);
      unawaited(_loadAlerts());
    });
  }

  Future<void> _loadAlerts() async {
    if (section == null) return;
    try {
      final overdue = await api.getJson('/pos?due=OVERDUE&pageSize=100&sort=due');
      final today = await api.getJson('/pos?due=TODAY&pageSize=100');
      if (!mounted) return;
      setState(() => alerts = [...(overdue['data'] as List), ...(today['data'] as List)]);
    } catch (_) {}
  }

  Future<void> refresh() async {
    setState(() => refreshTick++);
    await Future.wait([_loadHealth(), _loadAlerts(), _reloadMe()]);
  }

  void navigate(AppPage target, {Map<String, dynamic>? args}) {
    setState(() {
      page = target;
      pageArgs = args;
      pageKey++;
    });
  }

  Future<void> openPo(int id) async {
    if (me == null || section == null) return;
    await showPoDetail(context, id, scope: _scope(const SizedBox.shrink()));
  }

  AppScope _scope(Widget child) => AppScope(
        api: api,
        me: me!,
        section: section!,
        refreshTick: refreshTick,
        navigate: navigate,
        openPo: openPo,
        onMeChanged: (fresh) => setState(() => me = {...?me, ...fresh}),
        child: child,
      );

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _onActivity(),
      onPointerHover: (_) => _onActivity(),
      onPointerSignal: (_) => _onActivity(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, __) {
          _onActivity();
          return KeyEventResult.ignored;
        },
        child: AnimatedSwitcher(
          duration: DsMotion.of(context, DsMotion.page),
          child: KeyedSubtree(key: ValueKey(stage), child: _stageView()),
        ),
      ),
    );
  }

  Widget _stageView() {
    switch (stage) {
      case _Stage.booting:
        return const Scaffold(
          body: DsAmbient(
            child: Center(child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3))),
          ),
        );
      case _Stage.login:
        return LoginPage(onLogin: login, health: health);
      case _Stage.consent:
        return PdpaConsentPage(
          name: '${me?['displayName'] ?? ''}',
          waitingForPassword: me?['pdpaConsentAccepted'] == true,
          onAccept: acceptConsent,
          onDecline: logout,
        );
      case _Stage.sectionPick:
        return SectionPickerPage(
          me: me ?? const {},
          onPick: _enterSection,
          onLogout: logout,
        );
      case _Stage.app:
        return _frame();
    }
  }

  Widget _frame() {
    final heading = pageHeading(page);
    final sections = (me?['sections'] as List? ?? const []);
    final overdue = alerts.where((a) => (a as Map)['dueState'] == 'overdue').length;
    return _scope(
      Scaffold(
        backgroundColor: DsColors.scaffold,
        body: DsAmbient(
          child: DsGlassShell(
            child: Row(children: [
              SideNav(
                collapsed: navCollapsed,
                selected: page,
                section: section,
                overdue: overdue,
                onToggle: () {
                  setState(() => navCollapsed = !navCollapsed);
                  _writePref('psa.navCollapsed', navCollapsed ? '1' : '0');
                },
                onSelect: (p) => navigate(p),
                onLogout: () async {
                  final ok = await confirmAction(context,
                      title: 'Sign out?', message: 'You will need to sign in again to use the system.',
                      confirmLabel: 'Sign out', icon: Icons.logout);
                  if (ok) await logout();
                },
              ),
              Expanded(
                child: Column(children: [
                  TopBar(
                    title: heading.$1,
                    subtitle: heading.$2,
                    me: me,
                    health: health,
                    alerts: alerts,
                    sectionCount: sections.length,
                    onRefresh: refresh,
                    onChangeSection: () => setState(() => stage = _Stage.sectionPick),
                    onProfile: () => navigate(AppPage.profile),
                    onOpenAlert: (po) => unawaited(openPo(intFrom(po['id']) ?? 0)),
                    onSeeAllAlerts: () => navigate(AppPage.pos, args: {'due': 'OVERDUE'}),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: DsMotion.of(context, DsMotion.page),
                      switchInCurve: DsMotion.curveIn,
                      switchOutCurve: DsMotion.curveOut,
                      child: KeyedSubtree(key: ValueKey('$page-$pageKey'), child: _page()),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _page() {
    return switch (page) {
      AppPage.dashboard => const DashboardPage(),
      AppPage.pos => PoTablePage(args: pageArgs),
      AppPage.roadmap => const RoadmapPage(),
      AppPage.calendar => const CalendarPage(),
      AppPage.report => const MonthlyReportPage(),
      AppPage.workflow => const WorkflowPage(),
      AppPage.suppliers => const SupplierMasterPage(),
      AppPage.materials => MaterialMasterPage(args: pageArgs),
      AppPage.users => const UsersPage(),
      AppPage.settings => const SettingsPage(),
      AppPage.profile => const ProfilePage(),
    };
  }
}
