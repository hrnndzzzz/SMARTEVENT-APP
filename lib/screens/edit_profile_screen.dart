import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';

class EditProfileScreen extends StatefulWidget {
  final String name;
  final String role;

  const EditProfileScreen({super.key, required this.name, required this.role});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    final account = context.read<AppState>().currentAccount;
    _nameController = TextEditingController(text: account?.name ?? widget.name);
    _emailController = TextEditingController(text: account?.email ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();

    if (name.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name and email cannot be empty.')),
      );
      return;
    }

    context.read<AppState>().updateProfile(name: name, email: email);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrutHeader(
              title: 'Edit profile',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Said plainly: there is no profile endpoint, so this
                    // only changes what this device shows until you sign
                    // out. A form that silently forgets is worse than one
                    // that admits it.
                    const BrutInlineMessage(
                      tone: BrutTone.sun,
                      icon: Icons.info_outline,
                      text:
                          'Changes apply on this device only and are lost '
                          'when you sign out. Ask an administrator to change '
                          'your name or email for real.',
                    ),
                    const SizedBox(height: 18),
                    BrutTextField(
                      label: 'Full name',
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 14),
                    BrutTextField(
                      label: 'LCUP email',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    const MonoLabel('Role'),
                    const SizedBox(height: 6),
                    // Read-only on purpose: a role comes from the roster,
                    // and self-assignment is the hole the backend closed.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: context.palette.line,
                        borderRadius: AppRadius.controlAll,
                        border: Border.fromBorderSide(context.disabledSide),
                      ),
                      child: Text(
                        widget.role,
                        style: AppText.body.copyWith(
                          color: context.palette.subtle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            BrutFooter(
              child: BrutButton(
                label: 'Save changes',
                size: BrutSize.large,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
