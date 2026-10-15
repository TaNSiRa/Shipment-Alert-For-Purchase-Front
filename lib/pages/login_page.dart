part of '../main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin, required this.health, this.initialError});
  final Future<String?> Function(String email, String password) onLogin;
  final Map<String, dynamic> health;

  /// Why the last attempt failed when it happened off this page (coming back
  /// from Microsoft's sign-in).
  final String? initialError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool obscure = true;
  String? error;
  bool leaving = false;

  @override
  void initState() {
    super.initState();
    error = widget.initialError;
  }

  /// Leaves for Microsoft's sign-in page; the API brings the browser back here.
  void signInWithMicrosoft() {
    if (busy || leaving) return;
    setState(() {
      leaving = true;
      error = null;
    });
    final page = Uri.base;
    final back = '${page.scheme}://${page.authority}${page.path}';
    html.window.location.assign(
        '${AppConfig.apiBaseUrl}/auth/microsoft/start?returnTo=${Uri.encodeComponent(back)}');
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email (or employee no.) and password');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final problem = await widget.onLogin(email.text.trim(), password.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 980;
    return Scaffold(
      body: DsAmbient(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1040 : 460),
              child: DsEnter(
                child: DsCard(
                  padding: EdgeInsets.zero,
                  radius: 26,
                  clip: true,
                  child: IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide)
                            const Expanded(flex: 11, child: _LoginHero()),
                          Expanded(flex: 9, child: _form()),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 32),
      child: AutofillGroup(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DsColors.cardBorder),
                  ),
                  child: Image.asset('logo_tpk.png', height: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Purchase Shipment Alert',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: DsColors.heading)),
                        Text('Thai Parkerizing · Purchase', style: DsType.meta),
                      ]),
                ),
              ]),
              const SizedBox(height: 34),
              const Text('Sign in',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: DsColors.heading,
                      letterSpacing: -.4)),
              const SizedBox(height: 4),
              const Text('Use your work email or employee number.',
                  style: DsType.meta),
              const SizedBox(height: 24),
              DsLabeledField(
                label: 'Email or employee no.',
                child: TextField(
                  controller: email,
                  autofocus: true,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email
                  ],
                  textInputAction: TextInputAction.next,
                  decoration: dsInput(
                      hint: 'name@thaiparker.co.th',
                      icon: Icons.alternate_email),
                  onChanged: (_) =>
                      error == null ? null : setState(() => error = null),
                ),
              ),
              const SizedBox(height: 14),
              DsLabeledField(
                label: 'Password',
                child: TextField(
                  controller: password,
                  obscureText: obscure,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => submit(),
                  decoration: dsInput(
                    hint: 'Your password',
                    icon: Icons.lock_outline,
                    suffix: IconButton(
                      tooltip: obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                          color: DsColors.iconSoft),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                  onChanged: (_) =>
                      error == null ? null : setState(() => error = null),
                ),
              ),
              AnimatedSize(
                duration: DsMotion.of(context, DsMotion.chrome),
                child: error == null
                    ? const SizedBox(height: 18)
                    : Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 4),
                        child: InfoStrip(
                            text: error!,
                            icon: Icons.error_outline,
                            color: DsColors.redFg),
                      ),
              ),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: busy || leaving ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: Colors.white))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                              Text('Sign in', style: TextStyle(fontSize: 14.5)),
                              SizedBox(width: 8),
                              Icon(Icons.arrow_forward, size: 18),
                            ]),
                ),
              ),
              if (widget.health['microsoftLogin'] == true) ...[
                const SizedBox(height: 14),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('or', style: DsType.metaSm),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  height: 46,
                  child: OutlinedButton(
                    onPressed: busy || leaving ? null : signInWithMicrosoft,
                    child: leaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                _MicrosoftMark(),
                                SizedBox(width: 10),
                                Text('Sign in with Microsoft',
                                    style: TextStyle(fontSize: 14.5)),
                              ]),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    DsHealthPill(
                        label: 'API',
                        ok: widget.health['api'] == 'ok',
                        description: dsApiPillDescription),
                    DsHealthPill(
                        label: 'SQL',
                        ok: widget.health['database'] == 'ok',
                        description: dsSqlPillDescription),
                  ]),
              const SizedBox(height: 18),
              const Text(
                  'Forgot your password? Ask your section admin to reset it.',
                  textAlign: TextAlign.center,
                  style: DsType.metaSm),
              const SizedBox(height: 6),
              const Text('Developed by Automation Department',
                  textAlign: TextAlign.center, style: DsType.metaSm),
            ]),
      ),
    );
  }
}

/// What to tell someone the API sent back from a Microsoft sign-in that did
/// not end in a session (`ms_error` on the return address).
String microsoftErrorText(String code) {
  switch (code) {
    case 'NOT_REGISTERED':
      return 'Your Microsoft account is not set up in this system. Ask your section admin to add your work email.';
    case 'LOCKED':
      return 'This account is locked for a few minutes after too many failed sign-ins.';
    case 'CANCELLED':
      return 'Microsoft sign-in was cancelled.';
    case 'EXPIRED':
      return 'The Microsoft sign-in took too long or was opened twice. Please try again.';
    default:
      return 'Microsoft sign-in did not complete. Please try again or use your password.';
  }
}

/// The four-square mark Microsoft asks "Sign in with Microsoft" buttons to use.
class _MicrosoftMark extends StatelessWidget {
  const _MicrosoftMark();

  @override
  Widget build(BuildContext context) {
    Widget sq(Color c) => Container(width: 8, height: 8, color: c);
    return SizedBox(
      width: 18,
      height: 18,
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          sq(const Color(0xfff25022)),
          sq(const Color(0xff7fba00)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          sq(const Color(0xff00a4ef)),
          sq(const Color(0xffffb900)),
        ]),
      ]),
    );
  }
}

/// Left half of the login card: what the system does, drawn as the shipment's
/// journey (PO -> supplier -> sea -> customs -> factory).
class _LoginHero extends StatelessWidget {
  const _LoginHero();

  @override
  Widget build(BuildContext context) {
    const stops = [
      (Icons.receipt_long_outlined, 'Issue PO'),
      (Icons.mark_email_read_outlined, 'Supplier ACK'),
      (Icons.directions_boat_outlined, 'Shipping'),
      (Icons.local_shipping_outlined, 'Clearing'),
      (Icons.warehouse_outlined, 'Received'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 36),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff6f66ee), Color(0xff5b53e0), Color(0xff3a3390)],
        ),
      ),
      child: Stack(children: [
        Positioned(
          right: -60,
          top: -40,
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .07)),
          ),
        ),
        Positioned(
          left: -50,
          bottom: -70,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .06)),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('PURCHASE · IMPORT SHIPMENTS',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1)),
          ),
          const SizedBox(height: 22),
          const Text('Know where every\norder is — and when\nit will arrive.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6)),
          const SizedBox(height: 14),
          Text(
              'Import POs straight from the SAP export, tick each step as it happens, '
              'and get a daily 08:30 email of what is due and what is late.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .86),
                  fontSize: 13.5,
                  height: 1.55)),
          const SizedBox(height: 34),
          Row(children: [
            for (var i = 0; i < stops.length; i++) ...[
              Column(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: i == 2 ? .95 : .18),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(stops[i].$1,
                      size: 21, color: i == 2 ? DsColors.navy : Colors.white),
                ),
                const SizedBox(height: 7),
                Text(stops[i].$2,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ]),
              if (i < stops.length - 1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Container(
                        height: 2,
                        color:
                            Colors.white.withValues(alpha: i < 2 ? .8 : .28)),
                  ),
                ),
            ],
          ]),
          const SizedBox(height: 30),
          for (final line in const [
            'Upload the SAP "DATA BY SAP" Excel — no retyping',
            '9 steps, one input: just mark each step done',
            'Overdue alerts, road map and a month-end email',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(children: [
                const Icon(Icons.check_circle,
                    size: 17, color: Color(0xffb7f0d6)),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(line,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13))),
              ]),
            ),
        ]),
      ]),
    );
  }
}
