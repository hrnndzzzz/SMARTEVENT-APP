import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
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
      setState(
        () => _error =
            'Your password must be at least $_minPasswordLength characters.',
      );
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
    return BrutScreen(
      header: BrutFlowHeader(
        flowName: 'Create account',
        title: 'Create your account',
        currentStep: 0,
        steps: const [
          BrutStep(label: 'Account'),
          BrutStep(label: 'Verify'),
        ],
        onBack: () => Navigator.of(context).maybePop(),
      ),
      footer: BrutFooter(
        child: BrutButton(
          label: 'Create account',
          size: BrutSize.large,
          busy: _submitting,
          busyLabel: 'Creating…',
          onPressed: _submit,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Your email must already be on your organization’s approved '
            'roster. Your name and role come from that record.',
            style: AppText.caption,
          ),
          const SizedBox(height: 24),
          BrutTextField(
            label: 'School email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            hint: 'yourname@lcup.edu.ph',
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Password',
            controller: _passwordController,
            obscureText: _obscure,
            suffix: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'At least $_minPasswordLength characters.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Confirm password',
            controller: _confirmController,
            obscureText: _obscure,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(text: _error!, tone: BrutTone.coral),
          ],
        ],
      ),
    );
  }
}
