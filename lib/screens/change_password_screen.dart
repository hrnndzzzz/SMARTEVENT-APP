import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../main.dart';

/// Password change, and the mandatory first-login setup.
///
/// When [mandatory] is true the account is on a temporary password and the
/// backend restricts it until a real one is set, so there is no way out of
/// this screen except completing it or signing out.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.mandatory = false});

  final bool mandatory;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error;

  /// The backend's own minimum. Checked here too so the user finds out
  /// before a round trip, not from a 422.
  static const int _minPasswordLength = 8;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _localProblem() {
    if (_currentController.text.isEmpty) return 'Enter your current password.';
    if (_newController.text.length < _minPasswordLength) {
      return 'The new password must be at least $_minPasswordLength characters.';
    }
    if (_newController.text != _confirmController.text) {
      return 'The two new passwords do not match.';
    }
    if (_newController.text == _currentController.text) {
      return 'The new password must be different from the current one.';
    }
    return null;
  }

  Future<void> _submit() async {
    final problem = _localProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await context.read<AppState>().changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Password updated.')));

      final role = context.read<AppState>().currentRole;
      if (widget.mandatory && role != null) {
        // Nothing sensible to pop back to: this screen replaced the
        // sign-in, and the account has only now become usable.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => RootShell(role: role)),
          (route) => false,
        );
        return;
      }
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A temporary-password account cannot reach anything else, so there
      // is nothing useful to go back to.
      canPop: !widget.mandatory,
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A mandatory setup offers no way back, by design.
                if (!widget.mandatory) ...[
                  BrutIconButton(
                    icon: Icons.arrow_back,
                    label: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 20),
                ],
                Text(
                  widget.mandatory ? 'Set your password' : 'Change password',
                  style: AppText.titleBig,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.mandatory
                      ? 'Your account was created with a temporary password. '
                            'Set your own before continuing.'
                      : 'Choose a new password for your account.',
                  style: AppText.caption,
                ),
                const SizedBox(height: 22),
                _PasswordField(
                  label: widget.mandatory
                      ? 'Temporary password'
                      : 'Current password',
                  controller: _currentController,
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  label: 'New password',
                  controller: _newController,
                  helper: 'At least $_minPasswordLength characters.',
                ),
                const SizedBox(height: 14),
                _PasswordField(
                  label: 'Confirm new password',
                  controller: _confirmController,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  BrutInlineMessage(text: _error!, tone: BrutTone.coral),
                ],
                const SizedBox(height: 24),
                BrutButton(
                  label: widget.mandatory ? 'Set password' : 'Update password',
                  size: BrutSize.large,
                  busy: _submitting,
                  busyLabel: 'Saving…',
                  onPressed: _submit,
                ),
                if (widget.mandatory) ...[
                  const SizedBox(height: 10),
                  BrutButton(
                    label: 'Sign out instead',
                    tone: BrutTone.neutral,
                    onPressed: _submitting
                        ? null
                        : () => context.read<AppState>().signOut(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.label,
    required this.controller,
    this.helper,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BrutTextField(
          label: widget.label,
          controller: widget.controller,
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
        if (widget.helper != null) ...[
          const SizedBox(height: 6),
          Text(widget.helper!, style: AppText.caption),
        ],
      ],
    );
  }
}
