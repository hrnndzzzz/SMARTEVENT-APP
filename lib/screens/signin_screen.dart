import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
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
            content: Text('Signed in, but some data could not load.\n'
                '${failures.first}'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RootShell(role: app.currentRole!)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
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

  void _showQuickLoginSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dev Quick Login', style: AppText.cardTitle),
            const SizedBox(height: 4),
            const Text('Testing shortcut — not part of the real sign-in flow.', style: AppText.caption),
            const SizedBox(height: 16),
            for (final role in UserRole.values) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(switch (role) {
                  UserRole.officer => Icons.person_outline,
                  UserRole.treasurer => Icons.account_balance_wallet_outlined,
                  UserRole.adviser => Icons.fact_check_outlined,
                  UserRole.sdsStaff => Icons.description_outlined,
                  UserRole.admin => Icons.admin_panel_settings_outlined,
                  UserRole.superAdmin => Icons.shield_outlined,
                }),
                title: Text('Sign in as ${role.label}'),
                onTap: () {
                  context.read<AppState>().devQuickLogin(role);
                  Navigator.of(context).pop();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => RootShell(role: role)),
                  );
                },
              ),
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
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onLongPress: () => _showQuickLoginSheet(context),
                child: const Text(
                  'Welcome back',
                  style: TextStyle(
                    fontFamily: AppText.headerFamily,
                    fontWeight: FontWeight.w500,
                    fontSize: 24,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text('Sign in to your SmartEvent account.', style: AppText.caption),
              const SizedBox(height: 22),
              const _FieldLabel('LCUP Email'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _emailController,
                hint: 'yourname@lcup.edu.ph',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Password'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _passwordController,
                hint: '••••••••••',
                obscure: _obscurePassword,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                          onChanged: (v) => setState(() => _rememberMe = v ?? true),
                          activeColor: AppColors.indigo,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text('Remember me', style: AppText.caption),
                    ],
                  ),
                  GestureDetector(
                    onTap: _openForgotPassword,
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontFamily: AppText.bodyFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.indigo,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _signIn,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _submitting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Sign In'),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  ),
                  child: const Text(
                    'On the roster but no account yet? Create one',
                    style: TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.indigo,
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13, color: AppColors.inkFaint),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppText.caption);
  }
}