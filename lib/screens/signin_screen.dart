import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
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
  /// The way in to the demo: hold the heading, say yes.
  ///
  /// It starts as an officer and the role is changed from Settings
  /// afterwards, so exploring a second role does not mean coming back
  /// out here and holding the heading again.
  Future<void> _offerDemo(BuildContext context) async {
    final navigator = Navigator.of(context);
    final app = context.read<AppState>();

    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Access demo mode?'),
        content: const Text(
          'Seeded data, no server. Nothing here leaves the phone.\n\n'
          'You start as an officer. Settings has a role picker for the '
          'adviser, the SDS Office and the administrators.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Enter demo'),
          ),
        ],
      ),
    );
    if (yes != true) return;

    app.enterDemo(role: UserRole.officer);
    // The gate that decides welcome-or-app is the route under this one,
    // so changing the state is not enough: without this the app is there
    // and buried under the sign-in screen still on top of it.
    navigator.popUntil((route) => route.isFirst);
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
                onLongPress: () => _offerDemo(context),
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
