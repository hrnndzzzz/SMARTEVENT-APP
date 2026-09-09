import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Admin-only. Matches the real backend's POST /auth/register contract:
/// only an already-signed-in Admin can create a new account, and the
/// role is assigned right here at creation time — not chosen by the
/// new user, and not re-choosable later at Sign In.
class RegisterUserScreen extends StatefulWidget {
  const RegisterUserScreen({super.key});

  @override
  State<RegisterUserScreen> createState() => _RegisterUserScreenState();
}

class _RegisterUserScreenState extends State<RegisterUserScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _agreedToTerms = false;
  bool _submitting = false;
  UserRole _role = UserRole.officer;
  Department _department = Department.cite;

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

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    final app = context.read<AppState>();
    final error = app.registerUser(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      role: _role,
      department: _department,
    );

    setState(() => _submitting = false);

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Account created for ${_nameController.text.trim()} (${_role.name}).')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
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
                'Register New User',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Create an account and assign its role.', style: AppText.caption),
              const SizedBox(height: 22),
              const _FieldLabel('Full Name'),
              const SizedBox(height: 6),
              _buildTextField(controller: _nameController, hint: 'Juan Dela Cruz', onChanged: (_) => setState(() {})),
              const SizedBox(height: 14),
              const _FieldLabel('LCUP Email'),
              const SizedBox(height: 6),
              _buildTextField(
                controller: _emailController,
                hint: 'yourname@lcup.edu.ph',
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Temporary Password'),
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
              const _FieldLabel('Role'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _RoleChip(role: UserRole.officer, label: 'Officer', selected: _role == UserRole.officer, onTap: () => setState(() => _role = UserRole.officer))),
                  const SizedBox(width: 8),
                  Expanded(child: _RoleChip(role: UserRole.adviser, label: 'Adviser', selected: _role == UserRole.adviser, onTap: () => setState(() => _role = UserRole.adviser))),
                  const SizedBox(width: 8),
                  Expanded(child: _RoleChip(role: UserRole.admin, label: 'Admin', selected: _role == UserRole.admin, onTap: () => setState(() => _role = UserRole.admin))),
                ],
              ),
              const SizedBox(height: 16),
              const _FieldLabel('Department'),
              const SizedBox(height: 2),
              const Text(
                'Visual demo only, just in case sabihin na "paano pag gagamitin ng buong campus"',
                style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 10, color: AppColors.inkFaint),
              ),
              const SizedBox(height: 8),
              _DepartmentGrid(
                selected: _department,
                onSelect: (d) => setState(() => _department = d),
                includeSystemWide: _role == UserRole.admin,
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
                        'I confirm this user has consented to the processing of their personal data per RA 10173.',
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
                      : const Text('Create Account'),
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

class _RoleChip extends StatelessWidget {
  final UserRole role;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({required this.role, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
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

class _DepartmentGrid extends StatelessWidget {
  final Department selected;
  final ValueChanged<Department> onSelect;
  final bool includeSystemWide;

  const _DepartmentGrid({required this.selected, required this.onSelect, this.includeSystemWide = false});

  @override
  Widget build(BuildContext context) {
    final options = includeSystemWide
        ? Department.values
        : Department.values.where((d) => d != Department.systemWide);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in options) _chip(d),
      ],
    );
  }

  Widget _chip(Department d) {
    final isSelected = d == selected;
    return GestureDetector(
      onTap: () => onSelect(d),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? d.color : AppColors.surface,
          border: isSelected ? null : Border.all(color: AppColors.border, width: 0.8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : d.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              d.label,
              style: TextStyle(
                fontFamily: AppText.bodyFamily,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}