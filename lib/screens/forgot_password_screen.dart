import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail ?? '');
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
      setState(() => _error = 'Enter the $_codeLength-character code from your email.');
      return;
    }
    if (_passwordController.text.length < _minPasswordLength) {
      setState(() => _error =
          'The new password must be at least $_minPasswordLength characters.');
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
        const SnackBar(content: Text('Password reset. Sign in with your new password.')),
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
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Reset password',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isRequest
                    ? 'We will email you a code to reset your password.'
                    : 'Enter the code we emailed you and choose a new password.',
                style: AppText.caption,
              ),
              const SizedBox(height: 22),
              const Text('Email', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _emailController,
                enabled: isRequest,
                keyboardType: TextInputType.emailAddress,
              ),
              if (!isRequest) ...[
                const SizedBox(height: 14),
                const Text('Reset code', style: AppText.caption),
                const SizedBox(height: 6),
                TextField(
                  controller: _codeController,
                  maxLength: _codeLength,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(counterText: ''),
                ),
                const SizedBox(height: 14),
                const Text('New password', style: AppText.caption),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    helperText: 'At least $_minPasswordLength characters.',
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Confirm new password', style: AppText.caption),
                const SizedBox(height: 6),
                TextField(controller: _confirmController, obscureText: true),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 14),
                _Banner(message: _notice!, color: AppColors.sageTeal),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                _Banner(message: _error!, color: AppColors.brick),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _submitting ? null : (isRequest ? _requestCode : _reset),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isRequest ? 'Send reset code' : 'Reset password'),
              ),
              if (!isRequest) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                            _step = _Step.request;
                            _error = null;
                            _notice = null;
                          }),
                  child: const Text('Use a different email'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(message, style: AppText.caption.copyWith(color: color)),
    );
  }
}
