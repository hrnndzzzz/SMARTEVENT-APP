import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

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
      setState(
        () => _error = 'Enter the $_codeLength-character code from your email.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _notice = null;
    });

    final outcome = await context.read<AppState>().verifyOtp(
      email: widget.email,
      otpCode: code,
    );

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
      _notice = error == null
          ? 'A new code is on its way to ${widget.email}.'
          : null;
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
              BrutIconButton(
                icon: Icons.arrow_back,
                label: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(height: 20),
              const Text('Verify your email', style: AppText.titleBig),
              const SizedBox(height: 4),
              Text(
                'We sent a $_codeLength-character code to ${widget.email}. '
                'Enter it to activate your account.',
                style: AppText.caption,
              ),
              const SizedBox(height: 24),
              BrutTextField(
                label: 'Verification code',
                controller: _codeController,
                maxLength: _codeLength,
                textCapitalization: TextCapitalization.characters,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                BrutInlineMessage(text: _error!, tone: BrutTone.coral),
              ],
              if (_notice != null) ...[
                const SizedBox(height: 14),
                BrutInlineMessage(
                  text: _notice!,
                  tone: BrutTone.mint,
                  icon: Icons.mark_email_read_outlined,
                ),
              ],
              const SizedBox(height: 24),
              BrutButton(
                label: 'Verify',
                size: BrutSize.large,
                busy: _submitting,
                busyLabel: 'Verifying…',
                onPressed: _verify,
              ),
              const SizedBox(height: 10),
              BrutButton(
                label: 'Resend code',
                tone: BrutTone.neutral,
                busy: _resending,
                busyLabel: 'Sending…',
                onPressed: _submitting ? null : _resend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
