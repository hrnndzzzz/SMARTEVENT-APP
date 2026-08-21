import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../main.dart';
import 'signup_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  UserRole _role = UserRole.officer;
  bool _obscurePassword = true;
  bool _rememberMe = true;

  void _signIn() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => RootShell(role: _role)),
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
              const Text(
                'Welcome back',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Sign in to your SmartEvent account.', style: AppText.caption),
              const SizedBox(height: 22),
              const _FieldLabel('LCUP Email'),
              const SizedBox(height: 6),
              _buildTextField(hint: 'juan.delacruz@lcup.edu.ph'),
              const SizedBox(height: 14),
              const _FieldLabel('Password'),
              const SizedBox(height: 6),
              _buildTextField(
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
                  const Text(
                    'Forgot password?',
                    style: TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Text('Continue as', style: AppText.caption),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _RoleChip(role: UserRole.officer, label: 'Officer', icon: Icons.person_outline, selected: _role == UserRole.officer, onTap: () => setState(() => _role = UserRole.officer))),
                  const SizedBox(width: 8),
                  Expanded(child: _RoleChip(role: UserRole.adviser, label: 'Adviser', icon: Icons.fact_check_outlined, selected: _role == UserRole.adviser, onTap: () => setState(() => _role = UserRole.adviser))),
                  const SizedBox(width: 8),
                  Expanded(child: _RoleChip(role: UserRole.admin, label: 'Admin', icon: Icons.admin_panel_settings_outlined, selected: _role == UserRole.admin, onTap: () => setState(() => _role = UserRole.admin))),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _signIn,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Sign In'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    );
                  },
                  child: RichText(
                    text: const TextSpan(
                      style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: AppColors.inkMuted),
                      children: [
                        TextSpan(text: "Don't have an account? "),
                        TextSpan(
                          text: 'Sign Up',
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

  Widget _buildTextField({required String hint, bool obscure = false, Widget? suffix}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        obscureText: obscure,
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

class _RoleChip extends StatelessWidget {
  final UserRole role;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.indigo : AppColors.surface,
          border: selected ? null : Border.all(color: AppColors.border, width: 0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}