import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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
  late Department _department;

  @override
  void initState() {
    super.initState();
    final account = context.read<AppState>().currentAccount;
    _nameController = TextEditingController(text: account?.name ?? widget.name);
    _emailController = TextEditingController(text: account?.email ?? '');
    _department = account?.department ?? Department.cite;
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

    context.read<AppState>().updateProfile(name: name, email: email, department: _department);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated.')),
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
                'Edit Profile',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 22,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 22),
              const _FieldLabel('Full Name'),
              const SizedBox(height: 6),
              _buildTextField(_nameController),
              const SizedBox(height: 14),
              const _FieldLabel('LCUP Email'),
              const SizedBox(height: 6),
              _buildTextField(_emailController),
              const SizedBox(height: 14),
              const _FieldLabel('Role'),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F2EC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(widget.role, style: const TextStyle(fontSize: 13, color: AppColors.inkMuted)),
              ),
              const SizedBox(height: 14),
              const _FieldLabel('Department'),
              const SizedBox(height: 2),
              const Text(
                'Visual demo only — shows how SmartEvent could theme itself per college.',
                style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 10, color: AppColors.inkFaint),
              ),
              const SizedBox(height: 8),
              _DepartmentGrid(
                selected: _department,
                onSelect: (d) => setState(() => _department = d),
                includeSystemWide: context.watch<AppState>().currentRole == UserRole.admin,
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13, color: AppColors.ink),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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

class _DepartmentGrid extends StatelessWidget {
  final Department selected;
  final ValueChanged<Department> onSelect;
  final bool includeSystemWide;

  const _DepartmentGrid({
    required this.selected,
    required this.onSelect,
    this.includeSystemWide = false,
  });

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