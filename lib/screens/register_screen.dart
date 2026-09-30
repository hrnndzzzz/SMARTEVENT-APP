import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'verify_otp_screen.dart';

/// Roster-based self-registration.
///
/// There is deliberately no role, name or department picker: the backend
/// takes all three from the applicant's approved roster entry, which is
/// what stops anyone assigning themselves a role. An address that isn't on
/// the roster is rejected, and that rejection is the backend's to explain.
///
/// On success the next screen is Verify Email — never a dashboard, since
/// the account stays inactive until the code is confirmed.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  bool _obscure = true;
  String? _error;

  static const int _minPasswordLength = 8;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your school email address.');
      return;
    }
    if (_passwordController.text.length < _minPasswordLength) {
      setState(() =>
          _error = 'Your password must be at least $_minPasswordLength characters.');
      return;
    }
    if (_passwordController.text != _confirmController.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await context.read<AppState>().register(
          email: email,
          password: _passwordController.text,
        );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => VerifyOtpScreen(email: email)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Create your account',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your email must already be on your organization’s approved '
                'roster. Your name and role come from that record.',
                style: AppText.caption,
              ),
              const SizedBox(height: 22),
              const Text('School email', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'yourname@lcup.edu.ph'),
              ),
              const SizedBox(height: 14),
              const Text('Password', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  helperText: 'At least $_minPasswordLength characters.',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Confirm password', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(controller: _confirmController, obscureText: _obscure),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brick.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: AppText.caption.copyWith(color: AppColors.brick),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
