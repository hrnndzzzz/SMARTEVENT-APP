import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _capturedImage;
  bool _logging = false;
  String _category = AppState.expenseCategories.first;

  final _vendorController = TextEditingController(text: 'Fresh Campus Catering');
  final _dateController = TextEditingController(text: 'Aug 12, 2026');
  final _totalController = TextEditingController(text: '2500.00');

  @override
  void dispose() {
    _vendorController.dispose();
    _dateController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      setState(() => _capturedImage = File(photo.path));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      setState(() {
        _dateController.text = '${months[picked.month - 1]} ${picked.day}, ${picked.year}';
      });
    }
  }

  Future<void> _confirmAndLog() async {
    final vendor = _vendorController.text.trim().isEmpty ? 'Unknown Vendor' : _vendorController.text.trim();
    final amount = double.tryParse(_totalController.text.trim());

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid total amount.')),
      );
      return;
    }

    setState(() => _logging = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    context.read<AppState>().logExpense(vendor, amount, category: _category);

    setState(() {
      _logging = false;
      _capturedImage = null;
      _category = AppState.expenseCategories.first;
      _vendorController.text = 'Fresh Campus Catering';
      _dateController.text = 'Aug 12, 2026';
      _totalController.text = '2500.00';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Expense logged: $vendor — ₱${amount.toStringAsFixed(2)} ($_category)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                initials: 'SO',
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'SO',
                      name: 'Juan Dela Cruz',
                      role: 'CITE Dept Officer',
                    ),
                  ),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Receipt Scanner',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  color: AppColors.ink,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Capture a receipt to auto-fill the expense entry.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    _CapturePreview(image: _capturedImage, onCapture: _capturePhoto),
                    const SizedBox(height: 16),
                    if (_capturedImage != null) ...[
                      _DetectedFieldsCard(
                        vendorController: _vendorController,
                        dateController: _dateController,
                        totalController: _totalController,
                        onDateTap: _pickDate,
                        category: _category,
                        onCategoryChanged: (c) => setState(() => _category = c),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        onPressed: _logging ? null : _confirmAndLog,
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: _logging
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : const Text('Confirm & Log Expense'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapturePreview extends StatelessWidget {
  final File? image;
  final VoidCallback onCapture;

  const _CapturePreview({required this.image, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 300,
            width: double.infinity,
            color: const Color(0xFFEFEBE0),
            child: image == null
                ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.receipt_long_outlined, size: 40, color: AppColors.inkFaint),
                  SizedBox(height: 10),
                  Text('No receipt captured yet', style: AppText.caption),
                ],
              ),
            )
                : Image.file(image!, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Material(
            color: AppColors.indigo,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onCapture,
              child: const SizedBox(
                width: 60,
                height: 60,
                child: Icon(Icons.camera_alt, color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetectedFieldsCard extends StatelessWidget {
  final TextEditingController vendorController;
  final TextEditingController dateController;
  final TextEditingController totalController;
  final VoidCallback onDateTap;
  final String category;
  final ValueChanged<String> onCategoryChanged;

  const _DetectedFieldsCard({
    required this.vendorController,
    required this.dateController,
    required this.totalController,
    required this.onDateTap,
    required this.category,
    required this.onCategoryChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Detected fields', style: AppText.cardTitle),
                const Spacer(),
                Icon(Icons.edit_outlined, size: 13, color: AppColors.inkFaint),
                const SizedBox(width: 4),
                const Text('Tap to edit', style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 10, color: AppColors.inkFaint)),
              ],
            ),
            const SizedBox(height: 10),
            _editableRow(
              label: 'Vendor',
              controller: vendorController,
              bottomBorder: true,
            ),
            GestureDetector(
              onTap: onDateTap,
              child: AbsorbPointer(
                child: _editableRow(
                  label: 'Date',
                  controller: dateController,
                  mono: true,
                  bottomBorder: true,
                  trailingIcon: Icons.calendar_today_outlined,
                ),
              ),
            ),
            _categoryRow(),
            const SizedBox(height: 4),
            _editableRow(
              label: 'Total',
              controller: totalController,
              mono: true,
              valueColor: AppColors.brick,
              bold: true,
              prefix: '₱',
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Category', style: AppText.caption),
          DropdownButton<String>(
            value: category,
            underline: const SizedBox.shrink(),
            style: const TextStyle(fontFamily: AppText.bodyFamily, fontSize: 12, color: AppColors.ink),
            items: [
              for (final c in AppState.expenseCategories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) {
              if (v != null) onCategoryChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _editableRow({
    required String label,
    required TextEditingController controller,
    bool mono = false,
    bool bold = false,
    bool bottomBorder = false,
    Color valueColor = AppColors.ink,
    String? prefix,
    IconData? trailingIcon,
    TextInputType? keyboardType,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: bottomBorder
          ? const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      )
          : null,
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: AppText.caption)),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              keyboardType: keyboardType,
              style: TextStyle(
                fontFamily: mono ? AppText.monoFamily : AppText.bodyFamily,
                fontWeight: bold ? FontWeight.w500 : FontWeight.w400,
                fontSize: bold ? 14 : 12,
                color: valueColor,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixText: prefix,
                prefixStyle: TextStyle(
                  fontFamily: mono ? AppText.monoFamily : AppText.bodyFamily,
                  fontWeight: bold ? FontWeight.w500 : FontWeight.w400,
                  fontSize: bold ? 14 : 12,
                  color: valueColor,
                ),
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 14, color: AppColors.inkMuted),
          ],
        ],
      ),
    );
  }
}