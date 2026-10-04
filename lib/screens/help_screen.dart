import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Questions about what the app actually does.
///
/// Every answer here describes a screen that exists. Earlier versions of
/// this FAQ documented attendance check-in, post-event evaluations and a
/// Restock button — none of which were ever built — which is worse than no
/// help at all, because it sends people looking for controls that are not
/// there.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      header: BrutHeader(
        title: 'Help and support',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrutSectionTitle('Events and approval'),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'How do I propose an event?',
            answer:
                'Open Events and tap New. Fill in the title, '
                'school year, semester, scope and requested budget, '
                'then submit. A Treasurer, Adviser or Admin can '
                'propose; an Officer cannot.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'Who approves it, and in what order?',
            answer:
                'Two stages. The Adviser reviews it first; if '
                'approved it moves to an Admin for final sign-off. '
                'Either can reject it with a remark. Nobody can '
                'approve a proposal they wrote themselves — the '
                'button does not appear, and the API refuses it.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'It was rejected. Can I fix it?',
            answer:
                'Yes. Open the event and tap Edit proposal, '
                'which appears only on a rejected one. Resubmitting '
                'restarts the review at the Adviser stage.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'Where do I review what is waiting on me?',
            answer:
                'Your dashboard lists it. Adviser and Admin '
                'dashboards each show the events and expenses at '
                'their own stage, with the decision on the detail '
                'screen.',
          ),
          const SizedBox(height: 20),
          const BrutSectionTitle('Money'),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'How do I record an expense from a receipt?',
            answer:
                'Open Scan, take or choose a photo, and check '
                'what was read. Every field — description, amount, '
                'date, category, event — is editable before you '
                'save. Nothing is saved until you press Save.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'When does the budget actually go down?',
            answer:
                'When a reviewer approves the expense. The '
                'deduction is made by the database at that moment, '
                'not by the phone, so two people approving at once '
                'cannot overspend a category.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'Why is approving an expense not enough?',
            answer:
                'An approval is permission to spend. Stock only '
                'exists once somebody confirms the goods arrived, '
                'which is the Complete purchase step on the '
                'expense. That records the payment and the '
                'delivery, and it runs once.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'What is a flagged expense?',
            answer:
                'A receipt that looks like another one, or an '
                'amount read from a receipt that disagrees with the '
                'amount entered. A flag is a prompt to look, not a '
                'finding. Flagged items are listed under Risk.',
          ),
          const SizedBox(height: 20),
          const BrutSectionTitle('Inventory'),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'Why can I not type a new quantity?',
            answer:
                'Stock only moves by a recorded movement, so '
                'every change carries a type, an event and a '
                'reason, and shows up in the ledger. Open the item '
                'and tap Record movement.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'What is an unconfirmed draft?',
            answer:
                'An item created for you by completing a '
                'purchase. An administrator confirms it before it '
                'can take movements. Confirming does not add stock '
                'again — that already happened.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'Why is something marked low stock?',
            answer:
                'Its quantity is at or below the low-stock '
                'threshold set on the item. Change the threshold, '
                'or record an incoming movement.',
          ),
          const SizedBox(height: 20),
          const BrutSectionTitle('Your account'),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'How do I get an account?',
            answer:
                'An administrator adds your email to the '
                'roster first. You then register with that email '
                'and verify it with the code you are sent. Your '
                'name, role and department come from the roster '
                'entry — you cannot choose them.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'I forgot my password.',
            answer:
                'Tap Forgot password on the sign-in screen. You '
                'will be emailed a reset code, then you choose a '
                'new password.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'Why does the app change colour?',
            answer:
                'It takes the accent of the department your '
                'account belongs to, so it is obvious whose records '
                'you are looking at.',
          ),
          const SizedBox(height: 10),
          const _FaqTile(
            question: 'What can an Officer do?',
            answer:
                'See everything belonging to their '
                'organization, and change none of it. SDS staff '
                'see proposal letters only. Each role is given one '
                'job, and the controls for the others are absent '
                'rather than disabled.',
          ),
          const SizedBox(height: 22),
          const BrutCard(
            tone: BrutTone.brand,
            tinted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrutSectionTitle('Still need help?'),
                SizedBox(height: 6),
                Text(
                  'Ask your organization adviser, or the CITE '
                  'Department office.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
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
    return BrutCard(
      radius: AppRadius.rowAll,
      shadow: _expanded ? AppShadows.base : AppShadows.sm,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => setState(() => _expanded = !_expanded),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.question,
                  style: AppText.cardTitle.copyWith(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            Text(
              widget.answer,
              style: AppText.body.copyWith(fontSize: 12.5, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
