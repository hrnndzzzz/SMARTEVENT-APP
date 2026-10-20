import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/brut.dart';
import 'sap_form_fields.dart';

/// Part 1 — Activity Details.
///
/// The field order follows the paper exactly, because people fill this in
/// with the printed form beside them and a reordered screen makes that
/// harder for no gain. The programme flow and emergency plan sit at the
/// end, where the paper puts them.
class SapPart1Screen extends StatefulWidget {
  const SapPart1Screen({super.key, required this.form});

  final SapForm form;

  @override
  State<SapPart1Screen> createState() => _SapPart1ScreenState();
}

class _SapPart1ScreenState extends State<SapPart1Screen> {
  late final SapForm _form = widget.form;

  late final _title = TextEditingController(text: _d.title ?? '');
  late final _organization = TextEditingController(
    text: _d.organizationName ?? '',
  );
  late final _course = TextEditingController(text: _d.course ?? '');
  late final _venue = TextEditingController(text: _d.venue ?? '');
  late final _pic = TextEditingController(text: _d.personsInCharge ?? '');
  late final _attire = TextEditingController(text: _d.attire ?? '');
  late final _students = TextEditingController(
    text: _d.expectedStudents?.toString() ?? '',
  );
  late final _rationale = TextEditingController(text: _d.rationale ?? '');
  late final _objectives = TextEditingController(text: _d.objectives ?? '');
  late final _emergency = TextEditingController(text: _d.emergencyPlan ?? '');
  late final _funding = TextEditingController(text: _d.fundingSource ?? '');
  late final _budget = TextEditingController(text: _d.totalBudget ?? '');
  late final _schoolYear = TextEditingController(text: _d.schoolYear ?? '');
  late final _departmentType = TextEditingController(
    text: _d.departmentType ?? '',
  );
  late final _department = TextEditingController(text: _d.department ?? '');

  SapDetails get _d => _form.details;
  bool get _editable => _form.canEditProposerParts;

  @override
  void dispose() {
    for (final c in [
      _title,
      _organization,
      _course,
      _venue,
      _pic,
      _attire,
      _students,
      _rationale,
      _objectives,
      _emergency,
      _funding,
      _budget,
      _schoolYear,
      _departmentType,
      _department,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Folds the typed text back into the model before saving. The pickers
  /// write through as they are touched; the text fields only here, so
  /// every keystroke does not rebuild the screen.
  void _collect() {
    _form.updateDetails(
      (d) => d.copyWith(
        title: _title.text.trim(),
        organizationName: _organization.text.trim(),
        course: _course.text.trim(),
        venue: _venue.text.trim(),
        personsInCharge: _pic.text.trim(),
        attire: _attire.text.trim(),
        expectedStudents: int.tryParse(_students.text.trim()),
        rationale: _rationale.text.trim(),
        objectives: _objectives.text.trim(),
        emergencyPlan: _emergency.text.trim(),
        fundingSource: _funding.text.trim(),
        // Kept as typed. The server compares this against the breakdown
        // in Part 3 as an exact decimal, so rounding it through a double
        // is how a 422 appears that nobody can account for.
        totalBudget: _budget.text.trim().replaceAll(',', ''),
        schoolYear: _schoolYear.text.trim(),
        departmentType: _departmentType.text.trim(),
        department: _department.text.trim(),
      ),
    );
  }

  /// Programme rows the server would reject: it requires
  /// `start <= row.start < row.end <= end`.
  List<SapProgramFlowItem> _outsideWindow(SapDetails d) {
    final from = d.startTime;
    final to = d.endTime;
    if (from == null || to == null) return const [];
    return [
      for (final row in _form.programFlow)
        if (row.start.compareTo(from) < 0 ||
            row.end.compareTo(to) > 0 ||
            row.start.compareTo(row.end) >= 0)
          row,
    ];
  }

  Future<void> _pickProposalDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _d.proposalDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (chosen != null) {
      _form.updateDetails((d) => d.copyWith(proposalDate: chosen));
    }
  }

  Future<void> _save() async {
    _collect();
    final ok = await _form.saveDetails();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_form.error ?? 'Could not save.')),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _d.activityDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (chosen != null) {
      _form.updateDetails((d) => d.copyWith(activityDate: chosen));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        final d = _form.details;

        return BrutScreen(
          header: BrutHeader(
            title: 'Activity Details',
            eyebrow: 'Part 1',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          footer: BrutFooter(
            onBack: () => Navigator.of(context).maybePop(),
            child: BrutButton(
              label: 'Save',
              busy: _form.saving,
              busyLabel: 'Saving',
              onPressed: _editable ? _save : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_editable)
                const BrutInlineMessage(
                  tone: BrutTone.sun,
                  icon: Icons.lock_outline,
                  text:
                      'This proposal is under review, so Parts 1 to 3 are '
                      'read-only until it is returned for revision.',
                ),
              const SizedBox(height: 12),

              // The paper's header block. Every one of these is required
              // at submission, so the form asks for them rather than
              // letting the attempt fail on four fields at once.
              BrutTextField(
                controller: _schoolYear,
                label: 'School year',
                hint: '2026-2027',
                enabled: _editable,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _departmentType,
                label: 'Department type',
                hint: 'College',
                enabled: _editable,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _department,
                label: 'Department',
                hint: 'CITE Department',
                enabled: _editable,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              BrutDateField(
                label: 'Date of proposal',
                value: d.proposalDate,
                hint: 'Pick a date',
                onTap: _editable ? _pickProposalDate : () {},
              ),
              if (d.proposalDate != null &&
                  d.activityDate != null &&
                  d.proposalDate!.isAfter(d.activityDate!)) ...[
                const SizedBox(height: 10),
                const BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.error_outline,
                  text: 'The proposal date cannot come after the activity.',
                ),
              ],
              const SizedBox(height: 20),

              BrutTextField(
                controller: _title,
                label: 'Activity title',
                hint: 'HACK THE FUTURE: Cybersecurity…',
                enabled: _editable,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _organization,
                label: 'Organization',
                hint: 'Association of Computer Engineering Students',
                enabled: _editable,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _course,
                label: 'Program / course',
                hint: 'Bachelor of Science in Computer Engineering',
                enabled: _editable,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),

              BrutDateField(
                label: 'Activity date',
                value: d.activityDate,
                hint: 'Pick a date',
                onTap: _editable ? _pickDate : () {},
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: SapTimeField(
                      label: 'Start',
                      value: d.startTime,
                      enabled: _editable,
                      onChanged: (t) => _form.updateDetails(
                        (x) => x.copyWith(startTime: t),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SapTimeField(
                      label: 'End',
                      value: d.endTime,
                      enabled: _editable,
                      onChanged: (t) =>
                          _form.updateDetails((x) => x.copyWith(endTime: t)),
                    ),
                  ),
                ],
              ),
              if (d.startTime != null &&
                  d.endTime != null &&
                  d.endTime!.compareTo(d.startTime!) <= 0) ...[
                const SizedBox(height: 10),
                const BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.error_outline,
                  text: 'The end time has to be after the start time.',
                ),
              ],
              const SizedBox(height: 18),

              SapSingleChoice<SapModality>(
                label: 'Modality',
                options: SapModality.values,
                labelOf: (m) => m.label,
                value: d.modality,
                enabled: _editable,
                onChanged: (m) =>
                    _form.updateDetails((x) => x.copyWith(modality: m)),
              ),
              const SizedBox(height: 18),

              SapSingleChoice<SapSetting>(
                label: 'Setting',
                options: SapSetting.values,
                labelOf: (s) => s.label,
                value: d.setting,
                enabled: _editable,
                onChanged: (s) =>
                    _form.updateDetails((x) => x.copyWith(setting: s)),
              ),
              // The paper has a third tick box here. This workflow does
              // not carry it, and saying so beats a box that fails on
              // submission.
              const SizedBox(height: 8),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text:
                    'Off-campus activities go through the separate CHED '
                    'compliance workflow, not this form.',
              ),
              if (d.setting == SapSetting.online &&
                  d.modality != null &&
                  d.modality != SapModality.online) ...[
                const SizedBox(height: 8),
                const BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.error_outline,
                  text: 'An online setting needs the modality to be online.',
                ),
              ],
              const SizedBox(height: 14),

              BrutTextField(
                controller: _venue,
                label: 'Venue',
                hint: 'Zoom Platform',
                enabled: _editable,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _pic,
                label: 'Personnel-in-charge',
                hint: 'Engr. Aileen M. Habaradas, Engr. Glazen M. Perez',
                enabled: _editable,
                maxLines: 2,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _attire,
                label: 'Attire',
                hint: 'Any decent attire',
                enabled: _editable,
              ),
              const SizedBox(height: 18),

              // The server prints these two lists on the PDF exactly as
              // they arrive, joined with commas — unlike the core values,
              // which it title-cases. So the stored value has to be the
              // wording the paper uses, not a snake_case key.
              SapMultiChoice<String>(
                label: 'Activity type',
                options: const [
                  'Co-Curricular',
                  'Extra-Curricular',
                  'Subject-Embedded/Academic',
                ],
                labelOf: (v) => v,
                selected: d.activityTypes,
                enabled: _editable,
                onChanged: (v) =>
                    _form.updateDetails((x) => x.copyWith(activityTypes: v)),
              ),
              const SizedBox(height: 18),

              SapSingleChoice<String>(
                label: 'Scope',
                // The paper offers five. This workflow keeps the existing
                // two-value scope, so only those can be chosen.
                options: const ['organizational', 'departmental'],
                labelOf: (v) =>
                    v == 'organizational' ? 'Organizational' : 'Departmental',
                value: d.scope,
                enabled: _editable,
                onChanged: (v) =>
                    _form.updateDetails((x) => x.copyWith(scope: v)),
              ),
              const SizedBox(height: 18),

              SapMultiChoice<String>(
                label: 'Program',
                options: const [
                  'Team Building',
                  'Leadership Summit',
                  'General Assembly',
                  'Competition',
                  'Press Conference',
                  'Seminar/Convention',
                  'Others',
                ],
                labelOf: (v) => v,
                selected: d.programTypes,
                enabled: _editable,
                onChanged: (v) =>
                    _form.updateDetails((x) => x.copyWith(programTypes: v)),
              ),
              const SizedBox(height: 14),

              BrutTextField(
                controller: _students,
                label: 'Number of students',
                hint: '145',
                enabled: _editable,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _rationale,
                label: 'Rationale',
                hint: 'Why the activity is being proposed',
                enabled: _editable,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _objectives,
                label: 'Objectives',
                hint: 'One per line',
                enabled: _editable,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 18),

              SapMultiChoice<SapCoreValue>(
                label: 'Augustinian core values',
                options: SapCoreValue.values,
                labelOf: (c) => c.label,
                selected: d.coreValues,
                enabled: _editable,
                onChanged: (v) =>
                    _form.updateDetails((x) => x.copyWith(coreValues: v)),
              ),
              const SizedBox(height: 18),

              SapMultiChoice<int>(
                label: 'Expected graduate attributes',
                options: const [1, 2, 3, 4],
                labelOf: (i) => switch (i) {
                  1 => 'EGA 1 · Critical and Creative Thinker',
                  2 => 'EGA 2 · Competent Professional',
                  3 => 'EGA 3 · Socially Responsive Steward',
                  _ => 'EGA 4 · Transformative Lifelong Learner',
                },
                selected: d.egas,
                enabled: _editable,
                onChanged: (v) =>
                    _form.updateDetails((x) => x.copyWith(egas: v)),
              ),
              const SizedBox(height: 20),

              const BrutSectionTitle('Program flow'),
              const SizedBox(height: 8),
              if (_outsideWindow(d).isNotEmpty) ...[
                BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.error_outline,
                  text:
                      '${_outsideWindow(d).length} row(s) fall outside '
                      '${d.startTime!.label} – ${d.endTime!.label}. Every row '
                      'has to sit inside the activity.',
                ),
                const SizedBox(height: 10),
              ],
              _ProgramFlowEditor(form: _form, enabled: _editable),
              const SizedBox(height: 20),

              BrutTextField(
                controller: _emergency,
                label: 'Emergency plan',
                hint: 'What happens if something goes wrong',
                enabled: _editable,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _budget,
                label: 'Budget',
                hint: '2500.00',
                enabled: _editable,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 14),
              BrutTextField(
                controller: _funding,
                label: 'Source of budget',
                hint: 'Organizational funds',
                enabled: _editable,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The timed programme, as rows.
///
/// The API replaces this collection wholesale, so the list is edited here
/// and sent in full when Part 1 is saved.
class _ProgramFlowEditor extends StatelessWidget {
  const _ProgramFlowEditor({required this.form, required this.enabled});

  final SapForm form;
  final bool enabled;

  Future<void> _add(BuildContext context) async {
    final item = await showModalBottomSheet<SapProgramFlowItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProgramFlowSheet(),
    );
    if (item != null) form.setProgramFlow([...form.programFlow, item]);
  }

  @override
  Widget build(BuildContext context) {
    final items = form.programFlow;
    final full = items.length >= SapProposal.maxCollectionItems;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (items.isEmpty)
          const BrutInlineMessage(
            tone: BrutTone.neutral,
            icon: Icons.schedule,
            text: 'No rows yet. Add the programme one slot at a time.',
          ),
        for (var i = 0; i < items.length; i++) ...[
          SapRowCard(
            title: items[i].activity,
            subtitle: '${items[i].start.label} – ${items[i].end.label}',
            onRemove: enabled
                ? () => form.setProgramFlow([...items]..removeAt(i))
                : null,
          ),
          const SizedBox(height: 8),
        ],
        if (enabled) ...[
          const SizedBox(height: 4),
          BrutButton(
            label: full ? 'Sixteen rows is the limit' : 'Add a row',
            icon: Icons.add,
            tone: BrutTone.neutral,
            size: BrutSize.small,
            onPressed: full ? null : () => _add(context),
          ),
        ],
      ],
    );
  }
}

class _ProgramFlowSheet extends StatefulWidget {
  const _ProgramFlowSheet();

  @override
  State<_ProgramFlowSheet> createState() => _ProgramFlowSheetState();
}

class _ProgramFlowSheetState extends State<_ProgramFlowSheet> {
  final _activity = TextEditingController();
  SapTime? _start;
  SapTime? _end;

  @override
  void dispose() {
    _activity.dispose();
    super.dispose();
  }

  bool get _valid =>
      _activity.text.trim().isNotEmpty &&
      _start != null &&
      _end != null &&
      _end!.compareTo(_start!) > 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BrutSectionTitle('Programme row'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SapTimeField(
                  label: 'From',
                  value: _start,
                  onChanged: (t) => setState(() => _start = t),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SapTimeField(
                  label: 'To',
                  value: _end,
                  onChanged: (t) => setState(() => _end = t),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BrutTextField(
            controller: _activity,
            label: 'Activity',
            hint: 'Opening prayer',
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          BrutButton(
            label: 'Add',
            onPressed: _valid
                ? () => Navigator.of(context).pop(
                    SapProgramFlowItem(
                      start: _start!,
                      end: _end!,
                      activity: _activity.text.trim(),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
