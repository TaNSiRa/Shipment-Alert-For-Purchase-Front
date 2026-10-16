part of '../main.dart';

const String kPasswordRuleHint =
    'At least 8 characters, with a letter and a number';

/// Client-side copy of the server rule (RAP's, word for word), so the form can
/// say what is wrong before the round trip. The server still decides — it
/// also refuses the most common passwords.
String? passwordPolicyProblem(String password) {
  if (password.length < 8) return 'Password must be at least 8 characters long';
  if (password.length > 128) return 'Password must be at most 128 characters long';
  if (password.trim() != password) return 'Password must not start or end with a space';
  if (!RegExp(r'[A-Za-z]').hasMatch(password)) return 'Password must contain at least one letter';
  if (!RegExp(r'[0-9]').hasMatch(password)) return 'Password must contain at least one number';
  return null;
}

/// The mandatory "choose your own password" step for a new account or after
/// an admin reset. Returns the new {token, csrfToken}, or null to sign out.
Future<Map<String, dynamic>?> showFirstPasswordDialog(
    BuildContext context, ApiClient api) {
  final pass = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  bool busy = false;
  // Hidden at first, but they may look: it is a password never typed before.
  bool reveal = false;
  return showGlassDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
      Future<void> submit() async {
        final problem = passwordPolicyProblem(pass.text);
        if (problem != null) return setState(() => error = problem);
        if (pass.text != confirm.text) {
          return setState(() => error = 'The two passwords do not match');
        }
        setState(() {
          busy = true;
          error = null;
        });
        try {
          final result = await api
              .postJson('/auth/first-password', {'newPassword': pass.text});
          if (ctx.mounted) Navigator.pop(ctx, result);
        } on ApiException catch (e) {
          setState(() {
            busy = false;
            error = friendlyError(e.message);
          });
        }
      }

      return PopScope(
        canPop: false,
        child: AppDialog(
          title: 'Choose your own password',
          subtitle: 'Your password was set by an administrator',
          icon: Icons.key_outlined,
          width: 460,
          body:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const InfoStrip(
                text:
                    'For your security, set a password only you know before using the system. It must be different from the one you were given.'),
            const SizedBox(height: 16),
            DsLabeledField(
              label: 'New password',
              child: TextField(
                  controller: pass,
                  obscureText: !reveal,
                  autofocus: true,
                  decoration: dsInput(
                    icon: Icons.lock_outline,
                    suffix: IconButton(
                      tooltip: reveal ? 'Hide password' : 'Show password',
                      icon: Icon(reveal ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 19),
                      onPressed: () => setState(() => reveal = !reveal),
                    ),
                  )),
            ),
            const SizedBox(height: 4),
            const Text(kPasswordRuleHint, style: DsType.metaSm),
            const SizedBox(height: 12),
            DsLabeledField(
              label: 'Confirm new password',
              child: TextField(
                controller: confirm,
                obscureText: !reveal,
                onSubmitted: (_) => submit(),
                decoration: dsInput(icon: Icons.lock_outline, errorText: error),
              ),
            ),
          ]),
          actions: [
            DsOutlineButton(
                label: 'Sign out',
                height: 40,
                onPressed: busy ? null : () => Navigator.pop(ctx)),
            DsPrimaryButton(
                label: busy ? 'Saving…' : 'Save password',
                height: 40,
                onPressed: busy ? null : submit),
          ],
        ),
      );
    }),
  );
}

class SectionPickerPage extends StatelessWidget {
  const SectionPickerPage(
      {super.key,
      required this.me,
      required this.onPick,
      required this.onLogout});
  final Map<String, dynamic> me;
  final void Function(Map<String, dynamic> section) onPick;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final sections = (me['sections'] as List? ?? const []).cast<Map>();
    return Scaffold(
      body: DsAmbient(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: DsEnter(
                child: DsCard(
                  padding: const EdgeInsets.fromLTRB(30, 28, 30, 24),
                  radius: 22,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          UserAvatar(user: me, size: 42, radius: 12),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Welcome back, ${me['displayName'] ?? ''}',
                                      style: DsType.pageTitle),
                                  const Text(
                                      'Choose the purchasing section to open',
                                      style: DsType.meta),
                                ]),
                          ),
                          DsOutlineButton(
                              label: 'Sign out',
                              icon: Icons.logout,
                              height: 38,
                              onPressed: () => unawaited(onLogout())),
                        ]),
                        const SizedBox(height: 20),
                        if (sections.isEmpty)
                          const InfoStrip(
                            icon: Icons.lock_outline,
                            color: DsColors.amberFg,
                            text:
                                'Your account is not a member of any section yet. Ask your section admin to add you.',
                          )
                        else
                          Wrap(spacing: 14, runSpacing: 14, children: [
                            for (var i = 0; i < sections.length; i++)
                              DsRise(
                                index: i,
                                child: SizedBox(
                                  width: 316,
                                  child: DsHoverLift(
                                    onTap: () => onPick(
                                        Map<String, dynamic>.from(sections[i])),
                                    child: DsCard(
                                      padding: const EdgeInsets.all(18),
                                      child: Row(children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                              color: DsColors.navySoft,
                                              borderRadius:
                                                  BorderRadius.circular(13)),
                                          child: const Icon(
                                              Icons.inventory_2_outlined,
                                              color: DsColors.navyDeep),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text('${sections[i]['name']}',
                                                    style: DsType.cardTitle),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${sections[i]['activePos'] ?? 0} open · ${sections[i]['overduePos'] ?? 0} overdue',
                                                  style: DsType.meta,
                                                ),
                                              ]),
                                        ),
                                        DsTag('${sections[i]['code']}'),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                          ]),
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
