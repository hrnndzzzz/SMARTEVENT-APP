import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'signin_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _agreedToTerms = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _agreedToTerms &&
          _nameController.text.trim().isNotEmpty &&
          _emailController.text.trim().isNotEmpty &&
          _passwordController.text.isNotEmpty &&
          !_submitting;

  void _goToSignIn() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final success = context.read<AppState>().signUp(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _submitting = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created. Please sign in.')),
      );
      _goToSignIn();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An account with this email already exists.')),
      );
    }
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
              const Text(
                'Get Started',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Create your SmartEvent account.', style: AppText.caption),
              const SizedBox(height: 22),
              const _FieldLabel('Full Name'),
              const SizedBox(height: 6),
              _buildTextField(controller: _nameController, hint: 'Juan Dela Cruz', onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              const _FieldLabel('LCUP Email'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _emailController,
                hint: 'juan.delacruz@lcup.edu.ph',
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Password'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _passwordController,
                hint: '••••••••••',
                obscure: _obscurePassword,
                onChanged: (_) => setState(() {}),
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: _agreedToTerms,
                      onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                      activeColor: AppColors.indigo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'I consent to the processing of my personal data per RA 10173.',
                        style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 11, color: AppColors.inkMuted, height: 1.4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _submitting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Sign Up'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: _goToSignIn,
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: AppColors.inkMuted),
                      children: [
                        TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Sign In',
                          style: TextStyle(color: AppColors.indigo, fontWeight: FontWeight.w500),
                        ),
                      ],
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
    ValueChanged<String>? onChanged,
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
        onChanged: onChanged,
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