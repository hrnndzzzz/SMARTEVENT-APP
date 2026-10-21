import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import 'sap/sap_review_demo_screen.dart';
import '../main.dart';
import 'change_password_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _submitting = true);

    final app = context.read<AppState>();
    final error = await app.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (error == null) {
      // A temporary-password account can't reach anything until it sets a
      // real password, so go there instead of to the shell.
      if (app.mustSetPassword) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ChangePasswordScreen(mandatory: true),
          ),
        );
        return;
      }

      // Signing in and loading the dashboard's data are separate outcomes.
      // Say so when the second one failed, instead of landing on empty
      // screens that look like an empty database.
      final failures = app.loadFailures;
      if (failures.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Signed in, but some data could not load.\n'
              '${failures.first}',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RootShell(role: app.currentRole!)),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          // Save them retyping it if they already started.
          initialEmail: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
        ),
      ),
    );
  }

  /// The demo accounts, by the address they sign in with.
  ///
  /// Addresses are not secrets and belong here; the password does not.
  /// It is supplied at build time instead, so a shortcut that signs in
  /// for real never puts a credential in the repository:
  ///
  /// ```
  /// flutter run --dart-define=SMARTEVENT_DEMO_PASSWORD=...
  /// ```
  ///
  /// Without that define the sheet still opens and says what is missing,
  /// rather than failing at the first tap.
  static const _demoAccounts = [
    (
      'demo.treasurer@lcup.edu.ph',
      'Treasurer',
      Icons.account_balance_wallet_outlined,
    ),
    ('demo.admin@lcup.edu.ph', 'Admin', Icons.admin_panel_settings_outlined),
    ('demo.sds@lcup.edu.ph', 'SDS Staff', Icons.description_outlined),
  ];

  static const _demoPassword = String.fromEnvironment(
    'SMARTEVENT_DEMO_PASSWORD',
  );

  /// Signs in properly, as if the fields had been typed.
  ///
  /// The old shortcut set a role locally and asked the backend for
  /// nothing, so the app came up looking signed in while holding no
  /// token and every request it made returned 401. This one goes through
  /// the same sign-in the form does, which means a real token, a real
  /// profile, and the same handling of a temporary password or a failed
  /// load afterwards.
  Future<void> _signInAs(BuildContext sheetContext, String email) async {
    Navigator.of(sheetContext).pop();
    _emailController.text = email;
    _passwordController.text = _demoPassword;
    await _signIn();
  }

  void _showQuickLoginSheet(BuildContext context) {
    BrutSheet.show<void>(
      context,
      builder: (sheetContext) => BrutSheet(
        title: 'Demo',
        subtitle: 'Seeded data, no server. Nothing here leaves the phone.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Safe in any build: these talk to nothing and sign nobody
            // in. Unlike the quick logins below them, which fake a
            // session against a real backend and belong in debug only.
            for (final (role, label, meta, icon) in const [
              (
                UserRole.treasurer,
                'Explore as a treasurer',
                'Events, money, inventory, reports',
                Icons.account_balance_wallet_outlined,
              ),
              (
                UserRole.adviser,
                'Explore as an adviser',
                'The same, plus reviewing what others send',
                Icons.fact_check_outlined,
              ),
              (
                UserRole.sdsStaff,
                'Explore as the SDS Office',
                'All six parts of the proposal form',
                Icons.admin_panel_settings_outlined,
              ),
            ]) ...[
              BrutListRow(
                title: label,
                meta: meta,
                marker: BrutIconTile(
                  size: 32,
                  icon: icon,
                  tone: BrutTone.brand,
                ),
                onTap: () {
                  final navigator = Navigator.of(context);
                  Navigator.of(sheetContext).pop();
                  context.read<AppState>().enterDemo(role: role);
                  // The gate that decides welcome-or-app is the route
                  // under this one, so changing the state is not enough:
                  // without this the app is there and buried under the
                  // sign-in screen that is still on top of it.
                  navigator.popUntil((route) => route.isFirst);
                },
              ),
              const SizedBox(height: AppLayout.tight),
            ],
            BrutListRow(
              title: 'Review a proposal',
              meta: 'The form with a reviewer\'s marks on it',
              marker: const BrutIconTile(
                size: 32,
                icon: Icons.edit_note,
                tone: BrutTone.mint,
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SapReviewDemoScreen(),
                  ),
                );
              },
            ),
            if (kDebugMode) ...[
              const SizedBox(height: AppLayout.section),
              const BrutSectionTitle('Sign in as'),
              const SizedBox(height: AppLayout.tight),
            ],
            if (kDebugMode && _demoPassword.isEmpty)
              const BrutInlineMessage(
                text:
                    'Rebuild with '
                    '--dart-define=SMARTEVENT_DEMO_PASSWORD=… to use this. '
                    'The password is kept out of the repository on purpose.',
                icon: Icons.key_off_outlined,
              )
            else if (kDebugMode)
              for (final (email, label, icon) in _demoAccounts) ...[
                BrutListRow(
                  title: label,
                  meta: email,
                  marker: BrutIconTile(size: 32, icon: icon),
                  onTap: () => _signInAs(sheetContext, email),
                ),
                if (email != _demoAccounts.last.$1)
                  const SizedBox(height: AppLayout.tight),
              ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrutIconButton(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                // The hold opens in every build; what it offers does not.
                // The review demo talks to nothing and signs nobody in,
                // so it is safe anywhere. The quick logins fill in a role
                // without asking the backend, which leaves the app
                // looking signed in while holding no token and every call
                // coming back 401 — useful while building a screen,
                // terrible in front of a panel. Those stay in debug.
                onLongPress: () => _showQuickLoginSheet(context),
                child: const Text('Welcome back', style: AppText.display),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in to your SmartEvent account.',
                style: AppText.caption,
              ),
              const SizedBox(height: 24),
              BrutTextField(
                label: 'LCUP email',
                controller: _emailController,
                hint: 'yourname@lcup.edu.ph',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                label: 'Password',
                controller: _passwordController,
                hint: '••••••••••',
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitting ? null : _signIn(),
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: context.palette.subtle,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: _rememberMe,
                          onChanged: (v) =>
                              setState(() => _rememberMe = v ?? true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('Remember me', style: AppText.caption),
                    ],
                  ),
                  GestureDetector(
                    onTap: _openForgotPassword,
                    child: Text(
                      'Forgot password?',
                      style: AppText.caption.copyWith(
                        color: context.palette.ink,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationThickness: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              BrutButton(
                label: 'Sign in',
                size: BrutSize.large,
                busy: _submitting,
                busyLabel: 'Signing in…',
                onPressed: _signIn,
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  child: Text(
                    'On the roster but no account yet? Create one',
                    style: AppText.caption.copyWith(
                      color: context.palette.ink,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationThickness: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
