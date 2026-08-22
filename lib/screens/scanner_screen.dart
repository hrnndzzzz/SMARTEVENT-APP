import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  Future<void> _capturePhoto() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      setState(() => _capturedImage = File(photo.path));
    }
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
                      const _DetectedFieldsCard(),
                      const SizedBox(height: 14),
                      const _ConfirmButton(),
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
  const _DetectedFieldsCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detected fields', style: AppText.cardTitle),
            const SizedBox(height: 10),
            _fieldRow('Vendor', 'Fresh Campus Catering', bottomBorder: true),
            _fieldRow('Date', 'Aug 12, 2026', mono: true, bottomBorder: true),
            _fieldRow(
              'Total',
              '₱2,500.00',
              mono: true,
              valueColor: AppColors.brick,
              valueSize: 14,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldRow(
      String label,
      String value, {
        bool mono = false,
        bool bold = false,
        bool bottomBorder = false,
        Color valueColor = AppColors.ink,
        double valueSize = 12,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: bottomBorder
          ? const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.caption),
          Text(
            value,
            style: TextStyle(
              fontFamily: mono ? AppText.monoFamily : AppText.bodyFamily,
              fontWeight: bold ? FontWeight.w500 : FontWeight.w400,
              fontSize: valueSize,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton();

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {},
      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      child: const Text('Confirm & Log Expense'),
    );
  }
}