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
              const SizedBox(height: 4),
              const Text('Getting started', style: AppText.caption),
              const SizedBox(height: 8),
              const _FaqTile(
                question: 'How do I request a budget for a new event?',
                answer: 'Go to the Events tab, tap "New", and fill out the proposal form. It first goes to your Faculty Adviser for review, then to the System Administrator for final approval.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'Who approves my event proposal, and in what order?',
                answer: 'Every proposal is reviewed by a Faculty Adviser first. If approved, it moves on to a System Administrator for final sign-off. Either reviewer can reject it with an optional reason.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'My event got rejected — can I fix and resubmit it?',
                answer: 'Yes. Open the event, tap "Edit Proposal", make your changes, and resubmit. This restarts the review from the Adviser stage. Proposals can only be edited while rejected — not while pending or already approved.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'As an Adviser or Admin, where do I approve or reject requests?',
                answer: 'Your dashboard lists everything awaiting your decision. Tap any item to open its details, where you\'ll find Approve and Reject buttons along with an optional feedback field.',
              ),
              const SizedBox(height: 18),
              const Text('Events & attendance', style: AppText.caption),
              const SizedBox(height: 8),
              const _FaqTile(
                question: 'How does attendance tracking work?',
                answer: 'On an event\'s detail page, tap "Check In" each time someone arrives. The counter and progress bar update live against the expected attendee count from the proposal.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'Who fills out the Post-Event Evaluation?',
                answer: 'Only the Faculty Adviser can submit official ratings and comments after an event. Officers and Admins can view a submitted evaluation, but only the Adviser can add or edit one.',
              ),
              const SizedBox(height: 18),
              const Text('Inventory & finances', style: AppText.caption),
              const SizedBox(height: 8),
              const _FaqTile(
                question: 'Why is an inventory item marked "Low Stock"?',
                answer: 'Items fall below the minimum threshold automatically after being issued. Use "Restock" on the item card to replenish it.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'How do I scan a receipt?',
                answer: 'Open the Scanner tab and tap the camera button to capture the receipt. Detected fields (vendor, date, total, category) are all editable before you confirm and log the expense.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'How does the Admin set category budgets?',
                answer: 'From the Admin dashboard, tap "Set Budget", choose a category, and enter the new amount. This updates the Dashboard\'s charts immediately.',
              ),
              const SizedBox(height: 18),
              const Text('Account & app', style: AppText.caption),
              const SizedBox(height: 8),
              const _FaqTile(
                question: 'How do notifications work?',
                answer: 'Notifications are targeted to whoever needs to act — for example, a new proposal notifies the Adviser, not the Admin, until it reaches their stage. You only see notifications relevant to your current role.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'What is the Department selector on my profile?',
                answer: 'This is a visual concept for the capstone defense, showing how SmartEvent could theme itself if adopted campus-wide beyond CITE. Choosing a department retints the app header and navigation bar. It doesn\'t change any actual data.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'How do I update my name or email?',
                answer: 'Go to Account > Edit Profile. Changes save immediately and apply across the app.',
              ),
              const SizedBox(height: 10),
              const _FaqTile(
                question: 'I forgot my password — what do I do?',
                answer: 'Tap "Forgot password?" on the Sign In screen. Password reset isn\'t available in this preview build yet.',
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