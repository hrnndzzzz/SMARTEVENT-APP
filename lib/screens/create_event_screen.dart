import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
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
                'New Event Proposal',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 22,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text('Submit a new activity for adviser review.', style: AppText.caption),
              const SizedBox(height: 22),
              const _FieldLabel('Event Name'),
              const SizedBox(height: 6),
              _buildTextField(hint: 'e.g. Leadership Summit 2026'),
              const SizedBox(height: 14),
              const _FieldLabel('Date'),
              const SizedBox(height: 6),
              _buildTextField(hint: 'Select a date', suffix: const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.inkMuted)),
              const SizedBox(height: 14),
              const _FieldLabel('Venue'),
              const SizedBox(height: 6),
              _buildTextField(hint: 'e.g. CITE Auditorium'),
              const SizedBox(height: 14),
              const _FieldLabel('Expected Attendees'),
              const SizedBox(height: 6),
              _buildTextField(hint: 'e.g. 120'),
              const SizedBox(height: 14),
              const _FieldLabel('Requested Budget'),
              const SizedBox(height: 6),
              _buildTextField(hint: '₱ 0.00'),
              const SizedBox(height: 14),
              const _FieldLabel('Description'),
              const SizedBox(height: 6),
              _buildTextField(hint: 'Briefly describe the event...', maxLines: 3),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: const Text('Submit for Review'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required String hint, Widget? suffix, int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        maxLines: maxLines,
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