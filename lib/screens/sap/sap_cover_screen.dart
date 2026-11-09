import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../api/models/scope.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import '../../theme/palette.dart';
import '../../widgets/scope_picker.dart';
import 'sap_form_fields.dart';

/// The cover of the form, before any of it is filled in.
///
/// The three steps used to open straight onto the activity details, so
/// the first thing anyone saw was a field. The paper opens with the
/// university's own header and the handful of facts that frame
/// everything after it — which school year, when it is being written,
/// and whether it leaves campus.
///
/// That last one is not a detail. Going off campus brings thirty days'
/// notice, a signed ROC or COC and the parents' consent with it, and
/// asking at the top means nobody fills in three steps before finding
/// out.
class SapCoverScreen extends StatelessWidget {
  const SapCoverScreen({
    super.key,
    required this.form,
    required this.onBegin,
    this.departments,
    this.organizationsIn,
  });

  final SapForm form;

  /// Into Part 1.
  final void Function(BuildContext context) onBegin;

  /// Given only for a proposer who has to say whose event this is — a
  /// Super Admin, who belongs to no organization. The form cannot be
  /// started until one is chosen, because the server refuses the event
  /// without it.
  final List<RemoteDepartment>? departments;
  final List<RemoteOrganization> Function(String? departmentId)?
  organizationsIn;

  /// The school year an activity in [now] belongs to.
  ///
  /// The academic year turns over in June, so August 2026 is 2026-2027
  /// and February 2027 is still 2026-2027.
  static String schoolYearFor(DateTime now) =>
      now.month >= 6 ? '${now.year}-${now.year + 1}' : '${now.year - 1}-${now.year}';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: form,
      builder: (context, _) {
        final d = form.details;
        final editable = form.canEditProposerParts;
        final offCampus = d.setting == SapSetting.offCampus;
        final departments = this.departments;
        final scoped = departments == null || form.scopeOrganizationId != null;
        final ready =
            scoped &&
            d.setting != null &&
            (!offCampus || d.offCampusAgreement);

        return BrutScreen(
          header: BrutHeader(
            title: 'Activity Proposal',
            eyebrow: 'Before you start',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          footer: BrutFooter(
            child: BrutButton(
              label: 'Start the form',
              trailingIcon: Icons.arrow_forward,
              onPressed: editable && ready ? () => onBegin(context) : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FormHeader(),
              const SizedBox(height: 20),

              if (departments != null) ...[
                ScopePicker(
                  departments: departments,
                  departmentId: form.scopeDepartmentId,
                  onDepartmentChanged: (id) => form.chooseScope(
                    departmentId: id,
                    departmentName: departments
                        .where((x) => x.id == id)
                        .map((x) => x.name)
                        .firstOrNull,
                  ),
                  organizations:
                      organizationsIn?.call(form.scopeDepartmentId) ??
                      const [],
                  organizationId: form.scopeOrganizationId,
                  onOrganizationChanged: (id) => form.chooseScope(
                    departmentId: form.scopeDepartmentId,
                    departmentName: d.department,
                    organizationId: id,
                    organizationName:
                        (organizationsIn?.call(form.scopeDepartmentId) ??
                                const <RemoteOrganization>[])
                            .where((o) => o.id == id)
                            .map((o) => o.name)
                            .firstOrNull,
                  ),
                  explanation:
                      'Your account belongs to no organization, so choose '
                      'whose activity this is.',
                ),
                const SizedBox(height: 20),
              ],

              const MonoLabel('School year'),
              const SizedBox(height: 6),
              Text(
                d.schoolYear ?? schoolYearFor(DateTime.now()),
                style: AppText.cardTitle,
              ),
              const SizedBox(height: 14),
              const MonoLabel('Date of proposal'),
              const SizedBox(height: 6),
              Text(
                _readable(d.proposalDate ?? DateTime.now()),
                style: AppText.cardTitle,
              ),
              const SizedBox(height: 6),
              const Text(
                'Both are filled in for you, and both can be changed on '
                'the first step.',
                style: AppText.caption,
              ),

              const SizedBox(height: 24),
              const BrutSectionTitle('Where is it being held?'),
              const SizedBox(height: 4),
              const Text(
                'This decides what else the form will ask for, so it is '
                'asked first.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              SapSingleChoice<SapSetting>(
                label: 'Setting',
                options: SapSetting.values,
                labelOf: (s) => s.label,
                value: d.setting,
                enabled: editable,
                onChanged: (s) =>
                    form.updateDetails((x) => x.copyWith(setting: s)),
              ),

              if (offCampus) ...[
                const SizedBox(height: 14),
                BrutCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Going off campus means all of this:',
                        style: AppText.cardTitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '•  Thirty days of notice, counted from the '
                        'date of proposal.\n'
                        '•  A signed ROC or COC attached before it is '
                        'sent.\n'
                        '•  The parents’ consent forms on file.',
                        style: AppText.body,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IntrinsicWidth(
                          child: BrutChip(
                            label: d.offCampusAgreement
                                ? 'Acknowledged'
                                : 'I acknowledge these',
                            selected: d.offCampusAgreement,
                            onTap: editable
                                ? () => form.updateDetails(
                                    (x) => x.copyWith(
                                      offCampusAgreement:
                                          !x.offCampusAgreement,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!d.offCampusAgreement) ...[
                  const SizedBox(height: 8),
                  const BrutInlineMessage(
                    tone: BrutTone.coral,
                    icon: Icons.error_outline,
                    text:
                        'An off-campus activity cannot be sent until this '
                        'is acknowledged.',
                  ),
                ],
              ],

              const SizedBox(height: 24),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text:
                    'Five steps: what the activity is, when and where, '
                    'the detail, the school support you need, and the '
                    'budget breakdown. Nothing is sent until the end, and '
                    'a draft can be left at any point.',
              ),
            ],
          ),
        );
      },
    );
  }

  static String _readable(DateTime on) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[on.month - 1]} ${on.day}, ${on.year}';
  }
}

/// The university's own heading, as it is printed on the paper.
class _FormHeader extends StatelessWidget {
  const _FormHeader();

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      tone: BrutTone.neutral,
      child: Column(
        children: [
          Text(
            'LA CONSOLACION UNIVERSITY PHILIPPINES',
            textAlign: TextAlign.center,
            style: AppText.cardTitle.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Student Affairs and Services',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
          const SizedBox(height: 10),
          Container(height: 2, color: context.palette.ink),
          const SizedBox(height: 10),
          Text(
            'STUDENT ACTIVITY PROPOSAL FORM',
            textAlign: TextAlign.center,
            style: AppText.cardTitle.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 4),
          const MonoLabel('SAS-SDS-FO-020 (001)'),
        ],
      ),
    );
  }
}
