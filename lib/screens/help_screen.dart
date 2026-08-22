import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                'Help & Support',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 18),
              const _FaqTile(
                question: 'How do I request a budget for a new event?',
                answer: 'Go to the Events tab, tap "New", and fill out the proposal form. Your adviser will review it and it will move through the approval timeline.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'Why is an inventory item marked "Low Stock"?',
                answer: 'Items fall below the minimum threshold automatically after being issued. Use "Restock" on the item card to replenish it.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'How do I scan a receipt?',
                answer: 'Open the Scanner tab and tap the camera button. This opens your phone\'s camera to capture the receipt image.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'Who can approve budget requests?',
                answer: 'Faculty Advisers and System Administrators can approve or reject pending requests from their respective dashboards.',
              ),
              const SizedBox(height: 22),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Still need help?', style: AppText.cardTitle),
                      const SizedBox(height: 6),
                      const Text(
                        'Reach out to the CITE Department office or your organization adviser for further assistance.',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.question, style: AppText.cardTitle.copyWith(fontSize: 13)),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.inkMuted,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Text(widget.answer, style: AppText.caption.copyWith(height: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}