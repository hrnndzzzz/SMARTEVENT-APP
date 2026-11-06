import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import '../../theme/peso.dart';
import 'sap_form_screen.dart';
import 'sds_sign_screen.dart';

/// The proposal as the SDS Office needs to read it.
///
/// The office does not fill this form in — the proposer does. Opening
/// the six-part list asked them to walk a form that is already written,
/// when what they have to do is read it, decide, and sign.
///
/// So: the whole thing on one screen, in the order the decision is made,
/// with the two actions at the bottom and the full form one tap away for
/// anything this leaves out.
class SdsSummaryScreen extends StatefulWidget {
  const SdsSummaryScreen({super.key, required this.form});

  final SapForm form;

  @override
  State<SdsSummaryScreen> createState() => _SdsSummaryScreenState();
}

class _SdsSummaryScreenState extends State<SdsSummaryScreen> {
  SapForm get form => widget.form;

  @override
  void initState() {
    super.initState();
    // The list hands over a form nobody has loaded. Only the full form
    // loaded it, so this read blank until that had been opened once.
    form.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: form,
      builder: (context, _) {
        final d = form.details;
        final waiting = form.state == SapState.pendingReview;

        return BrutScreen(
          header: BrutHeader(
            title: 'Proposal',
            eyebrow: 'SDS Office',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          footer: BrutFooter(
            child: BrutButton(
              label: waiting ? 'Review and decide' : 'Open the full form',
              icon: waiting ? Icons.draw_outlined : Icons.description_outlined,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => waiting
                      ? SdsSignScreen(form: form)
                      : SapFormScreen(form: form),
                ),
              ),
            ),
            secondary: waiting
                ? BrutButton(
                    label: 'Open the full form',
                    tone: BrutTone.neutral,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SapFormScreen(form: form),
                      ),
                    ),
                  )
                : null,
          ),
          child: form.loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: BrutSpinner()),
                )
              : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                d.title?.isNotEmpty == true ? d.title! : 'Untitled activity',
                style: AppText.display,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (d.organizationName?.isNotEmpty == true)
                    d.organizationName!,
                  if (d.schoolYear?.isNotEmpty == true) d.schoolYear!,
                ].join(' · '),
                style: AppText.caption,
              ),
              const SizedBox(height: 16),

              _Facts(details: d),
              const SizedBox(height: 16),

              const BrutSectionTitle('What is being asked for'),
              const SizedBox(height: 10),
              _Money(form: form),
              const SizedBox(height: 10),
              _Support(form: form),

              if (d.rationale?.isNotEmpty == true) ...[
                const SizedBox(height: 20),
                const BrutSectionTitle('Why'),
                const SizedBox(height: 8),
                Text(d.rationale!, style: AppText.body),
              ],
              if (d.objectives?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                const BrutSectionTitle('Objectives'),
                const SizedBox(height: 8),
                Text(d.objectives!, style: AppText.body),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// When, where, how, and for how many.
class _Facts extends StatelessWidget {
  const _Facts({required this.details});

  final SapDetails details;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      if (details.activityDate case final on?) ('Date', _date(on)),
      if (details.startTime != null && details.endTime != null)
        ('Time', '${_clock(details.startTime!)} to ${_clock(details.endTime!)}'),
      if (details.setting case final s?) ('Setting', s.label),
      if (details.modality case final m?) ('Modality', m.label),
      if (details.venue?.isNotEmpty == true) ('Venue', details.venue!),
      if (details.expectedStudents case final n?) ('Students', '$n'),
      if (details.personsInCharge?.isNotEmpty == true)
        ('In charge', details.personsInCharge!),
    ];

    if (rows.isEmpty) {
      return const BrutInlineMessage(
        tone: BrutTone.sun,
        icon: Icons.info_outline,
        text: 'Nothing has been filled in yet.',
      );
    }

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 92, child: MonoLabel(rows[i].$1, fontSize: 10)),
                Expanded(
                  child: Text(rows[i].$2, style: AppText.body),
                ),
              ],
            ),
            if (i != rows.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  /// Hours and minutes. The wire format carries seconds, which nobody
  /// reading a proposal needs.
  static String _clock(SapTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  static String _date(DateTime on) =>
      '${on.year}-${on.month.toString().padLeft(2, '0')}-'
      '${on.day.toString().padLeft(2, '0')}';
}

/// The total, and whether the lines under it agree with it.
class _Money extends StatelessWidget {
  const _Money({required this.form});

  final SapForm form;

  @override
  Widget build(BuildContext context) {
    final lines = form.budgetItems;
    final stated = double.tryParse(form.details.totalBudget ?? '') ?? 0;
    final summed = lines.fold(
      0.0,
      (total, item) => total + (double.tryParse(item.amount) ?? 0),
    );
    // The server refuses a submission where these disagree, so the
    // office should see it before it decides rather than after.
    final agrees = (stated - summed).abs() < 0.005;

    return BrutCard(
      tone: agrees ? BrutTone.neutral : BrutTone.coral,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: MonoLabel('Budget', fontSize: 10)),
              Text(peso(stated), style: AppText.moneyLarge),
            ],
          ),
          if (lines.isEmpty) ...[
            const SizedBox(height: 8),
            Text('No breakdown given.', style: AppText.caption),
          ] else ...[
            const SizedBox(height: 10),
            for (final item in lines) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.particulars, style: AppText.body),
                        // The two columns the office checks the
                        // arithmetic against, when the row gives them.
                        if (item.quantity > 1 || item.unitCost != null)
                          Text(
                            item.unitCost == null
                                ? '${item.quantity}'
                                : '${item.quantity} × '
                                      '${peso(double.tryParse(item.unitCost!) ?? 0)}',
                            style: AppText.caption.copyWith(fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  Text(peso(double.tryParse(item.amount) ?? 0),
                      style: AppText.body),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (!agrees) ...[
              const SizedBox(height: 8),
              Text(
                'The lines come to ${peso(summed)}, which is not the total '
                'above.',
                style: AppText.caption,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// What the school is being asked to provide.
class _Support extends StatelessWidget {
  const _Support({required this.form});

  final SapForm form;

  @override
  Widget build(BuildContext context) {
    final asked = form.supportRequests;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MonoLabel('School support', fontSize: 10),
          const SizedBox(height: 8),
          if (asked.isEmpty)
            Text('None requested.', style: AppText.caption)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final request in asked)
                  BrutBadge(
                    label: (request.specify ?? '').isEmpty
                        ? request.type.label
                        : '${request.type.label} · ${request.specify}',
                    tone: BrutTone.neutral,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
