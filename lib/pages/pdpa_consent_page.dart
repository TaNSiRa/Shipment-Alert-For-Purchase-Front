part of '../main.dart';

// The PDPA consent page, ported from RAP so both systems ask for consent the
// same way: the full company policy (pdpa_policy_text.dart, PDF in
// web/pdpa/), and "Accept and continue" stays locked until it has been
// scrolled to the end.

class PdpaConsentPage extends StatefulWidget {
  const PdpaConsentPage({
    super.key,
    required this.displayName,
    required this.busy,
    required this.onAccept,
    required this.onLogout,
    this.waitingForPassword = false,
  });

  final String displayName;
  final bool busy;
  final Future<void> Function() onAccept;
  final Future<void> Function() onLogout;

  /// Consent is done and the first-password dialog is up over this page —
  /// show a placeholder instead of the policy again.
  final bool waitingForPassword;

  @override
  State<PdpaConsentPage> createState() => _PdpaConsentPageState();
}

class _PdpaConsentPageState extends State<PdpaConsentPage> {
  final scroll = ScrollController();
  bool canAccept = false;
  double readProgress = 0;

  @override
  void initState() {
    super.initState();
    scroll.addListener(updateAcceptState);
    WidgetsBinding.instance.addPostFrameCallback((_) => updateAcceptState());
  }

  @override
  void dispose() {
    scroll
      ..removeListener(updateAcceptState)
      ..dispose();
    super.dispose();
  }

  void updateAcceptState() {
    if (!scroll.hasClients) return;
    final position = scroll.position;
    final max = position.maxScrollExtent;
    final nextProgress =
        max <= 0 ? 1.0 : (position.pixels / max).clamp(0.0, 1.0);
    final nextCanAccept = max <= 0 || position.pixels >= max - 12;
    if (nextCanAccept != canAccept ||
        (nextProgress - readProgress).abs() > 0.01) {
      setState(() {
        canAccept = nextCanAccept;
        readProgress = nextProgress;
      });
    }
  }

  Future<void> accept() async {
    if (!canAccept || widget.busy) return;
    await widget.onAccept();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.waitingForPassword) {
      return const Scaffold(
        body: DsAmbient(
          child: Center(child: Text('Setting up your account…', style: DsType.meta)),
        ),
      );
    }
    final titleStyle = Theme.of(context)
        .textTheme
        .headlineSmall
        ?.copyWith(fontWeight: FontWeight.w900, color: const Color(0xff243746));
    final isCompact = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffeef7f5), Color(0xfff7fbff), Color(0xfff8fafc)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(isCompact ? 12 : 22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xffdbe7ef)),
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x1f4b6475),
                          blurRadius: 28,
                          offset: Offset(0, 14)),
                    ],
                  ),
                  child: Column(children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          isCompact ? 16 : 24, 20, isCompact ? 16 : 24, 14),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Image.asset('logo_tpk.png',
                                height: isCompact ? 40 : 48),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('PDPA Consent', style: titleStyle),
                                    const SizedBox(height: 3),
                                    Text(
                                      widget.displayName.isEmpty
                                          ? 'Please read the privacy policy before continuing.'
                                          : 'User: ${widget.displayName}',
                                      style: const TextStyle(
                                          color: Color(0xff667985)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ]),
                            ),
                            if (!isCompact) ...[
                              OutlinedButton.icon(
                                onPressed: () => html.window
                                    .open('pdpa/privacy-policy.pdf', '_blank'),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: const Text('View PDF'),
                              ),
                              const SizedBox(width: 10),
                            ],
                            IconButton(
                              onPressed: widget.busy
                                  ? null
                                  : () => unawaited(widget.onLogout()),
                              icon: const Icon(Icons.logout),
                              tooltip: 'Logout',
                            ),
                          ]),
                    ),
                    LinearProgressIndicator(
                      value: readProgress.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: const Color(0xffe2e8f0),
                      color: DsColors.navy,
                    ),
                    Expanded(
                      // Always-visible bar by hand, so Material's automatic one
                      // must go — see [NoAutoScrollbarBehavior].
                      child: ScrollConfiguration(
                        behavior: const NoAutoScrollbarBehavior(),
                        child: Scrollbar(
                          controller: scroll,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: scroll,
                            padding: EdgeInsets.fromLTRB(
                                isCompact ? 16 : 24, 18, isCompact ? 16 : 24, 18),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: const Color(0xfff0fdfa),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xffb9c6ff)),
                                    ),
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.privacy_tip_outlined,
                                              color: DsColors.navy),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              canAccept
                                                  ? 'You have read the full policy — press "Accept and continue" to enter the system'
                                                  : 'Please read the privacy policy in full — the consent button unlocks once you scroll to the end',
                                              style: const TextStyle(
                                                  color: Color(0xff334653),
                                                  height: 1.45,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ]),
                                  ),
                                  if (isCompact) ...[
                                    const SizedBox(height: 12),
                                    OutlinedButton.icon(
                                      onPressed: () => html.window.open(
                                          'pdpa/privacy-policy.pdf', '_blank'),
                                      icon: const Icon(
                                          Icons.picture_as_pdf_outlined),
                                      label: const Text('View PDF'),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: EdgeInsets.all(isCompact ? 16 : 22),
                                    decoration: BoxDecoration(
                                      color: const Color(0xfffbfdff),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                          color: const Color(0xffdbe7ef)),
                                    ),
                                    child: const SelectableText(
                                      pdpaPolicyText,
                                      style: TextStyle(
                                        color: Color(0xff1f3442),
                                        fontSize: 15.5,
                                        height: 1.62,
                                      ),
                                    ),
                                  ),
                                ]),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.fromLTRB(
                          isCompact ? 16 : 24, 14, isCompact ? 16 : 24, 20),
                      decoration: const BoxDecoration(
                        border:
                            Border(top: BorderSide(color: Color(0xffe2e8f0))),
                      ),
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                  FilledButton.icon(
                                    onPressed: canAccept && !widget.busy
                                        ? () => unawaited(accept())
                                        : null,
                                    icon: widget.busy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(
                                            Icons.verified_user_outlined),
                                    label: const Text('Accept and continue'),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: widget.busy
                                        ? null
                                        : () => unawaited(widget.onLogout()),
                                    icon: const Icon(Icons.logout),
                                    label: const Text('Logout'),
                                  ),
                                ])
                          : Row(children: [
                              Expanded(
                                child: Text(
                                  canAccept
                                      ? 'Ready to continue'
                                      : 'Scroll to the end of the policy to enable consent',
                                  style: TextStyle(
                                    color: canAccept
                                        ? DsColors.navy
                                        : const Color(0xff8ca0ac),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: widget.busy
                                    ? null
                                    : () => unawaited(widget.onLogout()),
                                icon: const Icon(Icons.logout),
                                label: const Text('Logout'),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: canAccept && !widget.busy
                                    ? () => unawaited(accept())
                                    : null,
                                icon: widget.busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.verified_user_outlined),
                                label: const Text('Accept and continue'),
                              ),
                            ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
