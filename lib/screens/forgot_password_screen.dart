import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Forgot password: request a code, then reset with it.
///
/// Both steps live on one screen because the code arrives by email and the
/// user comes straight back. The request step's response is deliberately
/// identical whether or not the address exists, so nothing here may hint at
/// whether an account was found.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { request, reset }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _Step _step = _Step.request;
  bool _submitting = false;
  String? _error;
  String? _notice;

  static const int _codeLength = 6;
  static const int _minPasswordLength = 8;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });

    final error = await context.read<AppState>().forgotPassword(email: email);

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
      if (error == null) {
        _step = _Step.reset;
        // Worded so it says nothing about whether the account exists.
        _notice = 'If that address has an account, a reset code is on its way.';
      }
    });
  }

  Future<void> _reset() async {
    final code = _codeController.text.trim();
    if (code.length != _codeLength) {
      setState(
        () => _error = 'Enter the $_codeLength-character code from your email.',
      );
      return;
    }
    if (_passwordController.text.length < _minPasswordLength) {
      setState(
        () => _error =
            'The new password must be at least $_minPasswordLength characters.',
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
      _notice = null;
    });

    final error = await context.read<AppState>().resetPassword(
      email: _emailController.text.trim(),
      otpCode: code,
      newPassword: _passwordController.text,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset. Sign in with your new password.'),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRequest = _step == _Step.request;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BrutIconButton(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 20),
              const Text('Reset password', style: AppText.titleBig),
              const SizedBox(height: 4),
              Text(
                isRequest
                    ? 'We will email you a code to reset your password.'
                    : 'Enter the code we emailed you and choose a new password.',
                style: AppText.caption,
              ),
              const SizedBox(height: 24),
              BrutTextField(
                label: 'Email',
                controller: _emailController,
                enabled: isRequest,
                keyboardType: TextInputType.emailAddress,
              ),
              if (!isRequest) ...[
                const SizedBox(height: 14),
                BrutTextField(
                  label: 'Reset code',
                  controller: _codeController,
                  maxLength: _codeLength,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 14),
                BrutTextField(
                  label: 'New password',
                  controller: _passwordController,
                  obscureText: true,
                ),
                const SizedBox(height: 6),
                Text(
                  'At least $_minPasswordLength characters.',
                  style: AppText.caption,
                ),
                const SizedBox(height: 14),
                BrutTextField(
                  label: 'Confirm new password',
                  controller: _confirmController,
                  obscureText: true,
                ),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 14),
                BrutInlineMessage(
                  text: _notice!,
                  tone: BrutTone.mint,
                  icon: Icons.mark_email_read_outlined,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                BrutInlineMessage(text: _error!, tone: BrutTone.coral),
              ],
              const SizedBox(height: 24),
              BrutButton(
                label: isRequest ? 'Send reset code' : 'Reset password',
                size: BrutSize.large,
                busy: _submitting,
                busyLabel: isRequest ? 'Sending…' : 'Resetting…',
                onPressed: isRequest ? _requestCode : _reset,
              ),
              if (!isRequest) ...[
                const SizedBox(height: 10),
                BrutButton(
                  label: 'Use a different email',
                  tone: BrutTone.neutral,
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                          _step = _Step.request;
                          _error = null;
                          _notice = null;
                        }),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
