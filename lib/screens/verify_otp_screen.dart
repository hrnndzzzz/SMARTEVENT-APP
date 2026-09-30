import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Verify Email — the step between registering and being able to sign in.
///
/// Registration is approved automatically once roster eligibility and this
/// code both pass; there is no separate approval button anywhere. An
/// invalid or expired code must not destroy progress, so Resend stays
/// available and the screen never sends the user back to registration.
class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key, required this.email});

  final String email;

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _codeController = TextEditingController();

  bool _submitting = false;
  bool _resending = false;
  String? _error;
  String? _notice;

  /// The backend requires exactly six characters.
  static const int _codeLength = 6;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != _codeLength) {
      setState(() => _error = 'Enter the $_codeLength-character code from your email.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });

    final outcome = await context
        .read<AppState>()
        .verifyOtp(email: widget.email, otpCode: code);

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = outcome.error;
    });

    final result = outcome.result;
    if (result == null) return;

    // Activation succeeded. A confirmation email that failed to send is
    // worth mentioning but is NOT a registration failure.
    final message = result.confirmationEmailFailed
        ? '${result.detail} We could not send the confirmation email, but '
            'your account is active — you can sign in now.'
        : result.detail;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _notice = null;
    });

    final error = await context.read<AppState>().resendOtp(email: widget.email);

    if (!mounted) return;
    setState(() {
      _resending = false;
      _error = error;
      _notice = error == null ? 'A new code is on its way to ${widget.email}.' : null;
    });
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
                'Verify your email',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'We sent a $_codeLength-character code to ${widget.email}. '
                'Enter it to activate your account.',
                style: AppText.caption,
              ),
              const SizedBox(height: 22),
              const Text('Verification code', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _codeController,
                maxLength: _codeLength,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(counterText: ''),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                _Note(message: _error!, tone: _NoteTone.error),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 14),
                _Note(message: _notice!, tone: _NoteTone.info),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _submitting ? null : _verify,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _resending || _submitting ? null : _resend,
                child: Text(_resending ? 'Sending…' : 'Resend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _NoteTone { error, info }

class _Note extends StatelessWidget {
  const _Note({required this.message, required this.tone});

  final String message;
  final _NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == _NoteTone.error ? AppColors.brick : AppColors.sageTeal;
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
