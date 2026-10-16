part of '../main.dart';

/// Owns the signed-in session and everything around the pages: login, the
/// PDPA and first-password gates, section choice, idle sign-out, realtime
/// refresh, and the glass frame (side nav + top bar).
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

enum _Stage { booting, login, consent, splash, sectionPick, app }

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

  /// Shown once on the login page (a failed Microsoft sign-in).
  String? loginNotice;

  /// The PDPA "Accept and continue" request is in flight.
  bool consentBusy = false;

  /// When the splash on screen started (boot counts as one), and whether this
  /// sign-in has had its splash yet — see [_advanceGates].
  DateTime _splashSince = DateTime.now();
  bool _splashDone = false;

  Timer? _healthTimer;
  Timer? _idleTimer;
  Timer? _warnTimer;
  Timer? _refreshDebounce;
  DateTime _lastKeepAlive = DateTime.fromMillisecondsSinceEpoch(0);
  bool _warningOpen = false;

  /// The "Still there?" dialog's context while it is open, so signing out
  /// (idle timeout or any other way) can close it.
  BuildContext? _warningContext;

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
    unawaited(_microsoftReturnOrRestore());
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

  /// Coming back from "Sign in with Microsoft" the page URL carries either a
  /// one-time `ms_ticket` or an `ms_error` code. Both are taken off the address
  /// bar at once (a reload or a bookmark must not replay them).
  Future<void> _microsoftReturnOrRestore() async {
    final params = Uri.base.queryParameters;
    final ticket = params['ms_ticket'];
    final failure = params['ms_error'];
    if (ticket == null && failure == null) return _restoreSession();
    try {
      final rest = {
        for (final e in params.entries)
          if (e.key != 'ms_ticket' && e.key != 'ms_error') e.key: e.value,
      };
      final page = Uri.base;
      // Keep the entry's state: Flutter's router keeps its own bookkeeping
      // there and fails when it finds null.
      html.window.history.replaceState(
          html.window.history.state,
          '',
          '${page.path}${rest.isEmpty ? '' : '?${Uri(queryParameters: rest).query}'}'
              '${page.hasFragment ? '#${page.fragment}' : ''}');
    } catch (_) {}
    if (failure != null) {
      loginNotice = microsoftErrorText(failure);
      if (mounted) setState(() => stage = _Stage.login);
      return;
    }
    try {
      _applyLogin(await api.postJson('/auth/microsoft/exchange', {'ticket': ticket}));
    } on ApiException catch (e) {
      loginNotice = friendlyError(e.message);
      if (mounted) setState(() => stage = _Stage.login);
    } catch (_) {
      loginNotice = 'Cannot reach the server. Check that the API is running.';
      if (mounted) setState(() => stage = _Stage.login);
    }
  }

  Future<void> _restoreSession() async {
    final started = DateTime.now();
    try {
      final result = await api.getJson('/auth/session');
      _applyLogin(result);
    } catch (_) {
      // No live session: show the login page (after a short beat so the
      // splash does not flash — long enough for RAP's lockup to surface).
      final wait = Duration(milliseconds: kSplashWaterEmerge ? 900 : 500) - DateTime.now().difference(started);
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
    loginNotice = null;
    api.token = '${result['token']}';
    if (result['csrfToken'] != null) api.csrfToken = '${result['csrfToken']}';
    me = Map<String, dynamic>.from(result['user'] as Map);
    realtime.connect(baseUrl: AppConfig.apiBaseUrl, token: api.token!, onEvent: _onRealtime);
    _armIdleTimer();
    _advanceGates();
  }

  /// Walks the gates in order: consent -> first password -> splash -> section.
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
    // RAP's splash, once per sign-in, after the gates (as in RAP). A refresh
    // that restored the session is already on it (booting) and carries on.
    if (kSplashWaterEmerge && !_splashDone) {
      _splashDone = true;
      if (stage != _Stage.booting) {
        _splashSince = DateTime.now();
        setState(() => stage = _Stage.splash);
      }
      unawaited(_holdSplash());
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

  /// Keeps the splash up for at least 1.5 s (RAP's hold — a fast sign-in
  /// would otherwise blink it away), then carries on through the gates.
  Future<void> _holdSplash() async {
    const minSplash = Duration(milliseconds: 1500);
    final wait = minSplash - DateTime.now().difference(_splashSince);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (!mounted || me == null) return;
    if (stage == _Stage.splash || stage == _Stage.booting) _advanceGates();
  }

  Future<void> acceptConsent() async {
    if (consentBusy) return;
    setState(() => consentBusy = true);
    final result = await guard(context, () => api.postJson('/auth/pdpa-consent', {}));
    if (mounted) setState(() => consentBusy = false);
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
    _closeIdleWarning();
    api.token = null;
    api.csrfToken = null;
    api.sectionCode = null;
    _splashDone = false;
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
      builder: (ctx) {
        _warningContext = ctx;
        return AppDialog(
          title: 'Still there?',
          icon: Icons.timer_outlined,
          width: 420,
          body: const Text('You will be signed out in 2 minutes because there has been no activity.',
              style: TextStyle(fontSize: 13.5, color: DsColors.text)),
          actions: [
            DsOutlineButton(label: 'Sign out', height: 40, onPressed: () => Navigator.pop(ctx, false)),
            DsPrimaryButton(label: 'Stay signed in', height: 40, onPressed: () => Navigator.pop(ctx, true)),
          ],
        );
      },
    );
    _warningOpen = false;
    _warningContext = null;
    if (stay == true) {
      _lastKeepAlive = DateTime.fromMillisecondsSinceEpoch(0);
      _onActivity();
    } else if (stay == false) {
      await logout();
    }
  }

  /// Takes the "Still there?" dialog down if it is showing. It then returns
  /// null, which [_showIdleWarning] treats as neither stay nor sign out.
  void _closeIdleWarning() {
    final ctx = _warningContext;
    _warningContext = null;
    if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
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
          // Boot and the post-sign-in splash share a key: a refresh that
          // restores the session runs one splash straight on, with no cut.
          child: KeyedSubtree(
              key: ValueKey(stage == _Stage.booting ? _Stage.splash : stage), child: _stageView()),
        ),
      ),
    );
  }

  Widget _stageView() {
    switch (stage) {
      case _Stage.splash:
        return const WaterEmergeSplash();
      case _Stage.booting:
        if (kSplashWaterEmerge) return const WaterEmergeSplash();
        return const Scaffold(
          body: DsAmbient(
            child: Center(child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3))),
          ),
        );
      case _Stage.login:
        return LoginPage(onLogin: login, health: health, initialError: loginNotice);
      case _Stage.consent:
        return PdpaConsentPage(
          displayName: '${me?['displayName'] ?? ''}',
          busy: consentBusy,
          waitingForPassword: me?['pdpaConsentAccepted'] == true,
          onAccept: acceptConsent,
          onLogout: logout,
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
                      title: 'Sign out?',
                      message: 'You will need to sign in again to use the system.',
                      confirmLabel: 'Sign out',
                      icon: Icons.logout);
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
      AppPage.workflow => const WorkflowPage(),
      AppPage.suppliers => const SupplierMasterPage(),
      AppPage.materials => MaterialMasterPage(args: pageArgs),
      AppPage.users => const UsersPage(),
      AppPage.settings => const SettingsPage(),
      AppPage.profile => const ProfilePage(),
    };
  }
}
