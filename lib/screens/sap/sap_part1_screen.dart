import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import 'proposal_steps.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import '../../theme/palette.dart';
import 'sap_form_fields.dart';

/// Part 1 — Activity Details.
///
/// The field order follows the paper closely, because people fill this in
/// with the printed form beside them. It opens on the activity title
/// rather than the paper's header block: the header is who you are and
/// when you are writing, which the account already knows, and the
/// proposer came to write about the activity. The programme flow and
/// emergency plan sit at the end, where the paper puts them.
class SapPart1Screen extends StatefulWidget {
  const SapPart1Screen({
    super.key,
    required this.form,
    this.step,
    this.onContinue,
  });

  final SapForm form;

  /// Where this part sits when it is being filled in as one of three.
  ///
  /// Null means it was opened on its own — from the SDS Office's
  /// six-part list — and it keeps a plain header and a Save button.
  /// Given a step, it becomes part of the run: the bar shows all three,
  /// and the button carries on to the next rather than going back.
  final int? step;

  /// What to do after this part saves, when it is one of three.
  final Future<void> Function(BuildContext)? onContinue;


  @override
  State<SapPart1Screen> createState() => _SapPart1ScreenState();
}

class _SapPart1ScreenState extends State<SapPart1Screen> {
  @override
  void initState() {
    super.initState();
    // So an off-campus proposal that already has its ROC/COC says so
    // instead of asking for it again.
    _form.loadAttachments();
  }

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

  /// The details and the programme are separate endpoints. Stop at the
  /// first failure rather than send the second at a version the server
  /// has already rejected.
  Future<bool> _saveAll() async {
    for (final save in [_form.saveDetails, _form.saveProgramFlow]) {
      if (!await save()) return false;
    }
    return true;
  }

  Future<void> _save() async {
    _collect();
    final ok = await _saveAll();
    if (!mounted) return;
    if (ok) {
      // Part of a run: carry on rather than going back to whatever was
      // behind this.
      if (widget.onContinue case final next?) {
        await next(context);
      } else if (mounted) {
        Navigator.of(context).maybePop();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_form.error ?? 'Could not save.')),
      );
    }
  }

  /// The university wants a month's notice. The server enforces this only
  /// for off-campus activities, so the form holds every activity to it
  /// rather than let a proposal reach the SDS Office too late to act on.
  static const int _noticeDays = 30;

  /// Days between the proposal and the activity, or null while either
  /// date is still unset. Counted on whole days so that picking today
  /// and picking this evening read the same.
  int? _daysOfNotice(SapDetails d) {
    final activity = d.activityDate;
    if (activity == null) return null;
    final from = d.proposalDate ?? DateTime.now();
    return DateTime(activity.year, activity.month, activity.day)
        .difference(DateTime(from.year, from.month, from.day))
        .inDays;
  }

  /// Attaches the ROC or COC an off-campus submission cannot go without.
  ///
  /// The file is checked for type and size before it is sent, so a wrong
  /// one is refused here rather than after the whole transfer.
  Future<void> _attachRocCoc() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Choose the signed ROC or COC',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
    );
    final file = picked.firstOrNull;
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final problem = await _form.attachFile(
      category: SapAttachmentCategory.rocCoc,
      bytes: bytes,
      filename: file.name,
    );
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem ?? '${file.name} attached.')),
    );
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

  /// Asks before leaving, and saves a draft if that is what they want.
  Future<void> _leave(BuildContext context) async {
    final navigator = Navigator.of(context);
    final leaving = await LeaveProposal.confirm(
      context,
      save: () async {
        final ok = await _saveAll();
        if (!context.mounted) return ok;
        if (!ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_form.error ?? 'Could not save the draft.')),
          );
        }
        return ok;
      },
    );
    if (leaving) navigator.maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        final d = _form.details;
        final notice = _daysOfNotice(d);
        final tooSoon = notice != null && notice < _noticeDays;
        final unacknowledged =
            d.setting == SapSetting.offCampus && !d.offCampusAgreement;

        return BrutScreen(
          // One of three when it is being filled in as a run, its own
          // screen when the SDS Office opens it from their six-part
          // list.
          header: widget.step == null
              ? BrutHeader(
                  title: 'Activity Details',
                  eyebrow: 'Part 1',
                  onBack: () => _leave(context),
                )
              : BrutFlowHeader(
                  title: 'Activity Details',
                  flowName: 'Part 1 of 3',
                  currentStep: widget.step!,
                  onBack: () => _leave(context),
                  steps: [
                    for (final label in ProposalSteps.labels)
                      BrutStep(label: label),
                  ],
                ),
          // One back button, in the header. There were two doing the
          // same thing, and neither said whether anything was kept.
          footer: BrutFooter(
            child: BrutButton(
              label: widget.step == null ? 'Save' : 'Next: school support',
              busy: _form.saving,
              busyLabel: 'Saving',
              onPressed: _editable && !tooSoon && !unacknowledged
                  ? _save
                  : null,
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

              // The activity is what the proposer came to write about, so
              // the form opens on it. Department type and department are
              // still sent, taken from the account rather than asked for:
              // an officer cannot belong to a department they must type.
              _FieldGroup(
                title: 'The activity',
                tone: BrutTone.brand,
                hint: 'What it is called, and whose it is',
              ),
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
                controller: _schoolYear,
                label: 'School year',
                hint: '2026-2027',
                enabled: _editable,
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
              const SizedBox(height: 14),
              BrutTextField(
                controller: _course,
                label: 'Program / course',
                hint: 'Bachelor of Science in Computer Engineering',
                enabled: _editable,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 14),

              _FieldGroup(
                title: 'When',
                tone: BrutTone.sun,
                hint: 'And how it is being held',
              ),
              BrutDateField(
                label: 'Activity date',
                value: d.activityDate,
                hint: 'Pick a date',
                onTap: _editable ? _pickDate : () {},
              ),
              if (tooSoon) ...[
                const SizedBox(height: 10),
                BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.error_outline,
                  text: notice < 0
                      ? 'That date has already passed.'
                      : 'An activity needs $_noticeDays days of notice. '
                            'This one is ${notice == 0 ? 'today' : notice == 1 ? '1 day away' : '$notice days away'}.',
                ),
              ],
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

              // The setting was chosen on the cover, before any of this,
              // because it decides what the form will ask for. Shown
              // here so it is visible where it belongs on the paper, and
              // changed by going back to the cover rather than asked for
              // twice in two places.
              const MonoLabel('Setting'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 16,
                    color: context.palette.ink,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    d.setting?.label ?? 'Not chosen',
                    style: AppText.cardTitle.copyWith(fontSize: 14),
                  ),
                ],
              ),
              if (d.setting == SapSetting.offCampus) ...[
                const SizedBox(height: 14),
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
                const SizedBox(height: 10),
                if (_form.hasRocCoc)
                  const BrutInlineMessage(
                    tone: BrutTone.mint,
                    icon: Icons.check_circle_outline,
                    text: 'The ROC or COC is attached.',
                  )
                else ...[
                  BrutButton(
                    label: 'Attach the ROC or COC',
                    icon: Icons.attach_file,
                    tone: BrutTone.neutral,
                    busy: _form.saving,
                    busyLabel: 'Attaching',
                    onPressed: _editable ? _attachRocCoc : null,
                  ),
                  const SizedBox(height: 8),
                  const BrutInlineMessage(
                    tone: BrutTone.neutral,
                    icon: Icons.info_outline,
                    text:
                        'PDF, PNG or JPEG, up to 10 MB. It is attached to '
                        'this revision: a returned proposal needs it again.',
                  ),
                ],
              ],
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

              _FieldGroup(
                title: 'Where and who',
                tone: BrutTone.mint,
              ),
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
              _FieldGroup(
                title: 'What kind of activity',
                tone: BrutTone.violet,
              ),
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
              _FieldGroup(
                title: 'Why it is being held',
                tone: BrutTone.brand,
                hint: 'The case for it, and what it is meant to achieve',
              ),
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

              _FieldGroup(
                title: 'Safety',
                tone: BrutTone.coral,
              ),
              BrutTextField(
                controller: _emergency,
                label: 'Emergency plan',
                hint: 'What happens if something goes wrong',
                enabled: _editable,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
              _FieldGroup(
                title: 'Money',
                tone: BrutTone.mint,
                hint: 'The total here; the breakdown comes in step three',
              ),
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

/// A heading over a run of related fields.
///
/// Part 1 is twenty-odd fields in one column, which is what our
/// professor meant by cluttered: the eye has nothing to hold on to and
/// no sense of how much is left. Grouping them by what they are about —
/// and giving each group its own colour down the side — turns one long
/// list into six short ones.
class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.title, required this.tone, this.hint});

  final String title;
  final BrutTone tone;

  /// What the group is for, when the name alone does not say.
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The colour is the whole point, so it is a solid bar rather
          // than a tint behind the words, which the dark theme washes
          // out.
          Container(
            width: 5,
            height: hint == null ? 20 : 34,
            margin: const EdgeInsets.only(right: 10, top: 2),
            decoration: BoxDecoration(
              color: tone.fill(context),
              borderRadius: AppRadius.controlAll,
              border: Border.all(color: context.palette.ink, width: 1.5),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: AppText.cardTitle.copyWith(fontSize: 15)),
                if (hint case final line?) ...[
                  const SizedBox(height: 2),
                  Text(line, style: AppText.caption.copyWith(fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
