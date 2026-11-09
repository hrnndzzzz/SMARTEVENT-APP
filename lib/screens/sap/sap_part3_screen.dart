import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import 'proposal_steps.dart';
import 'sap_form_screen.dart' show MissingForSubmit;
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import '../../theme/peso.dart';
import 'sap_form_fields.dart';

/// Part 3 — Additional Information.
///
/// Three things the paper groups together: free notes, the budget
/// breakdown that must add up to the total in Part 1, and the classes the
/// activity interrupts.
///
/// The budget total is shown against Part 1's figure rather than quietly
/// corrected. The backend checks exact decimal equality, so a mismatch is
/// something the person filling this in has to resolve, not something the
/// form should paper over by rewriting one of the two numbers.
class SapPart3Screen extends StatefulWidget {
  const SapPart3Screen({
    super.key,
    required this.form,
    this.step,
    this.onContinue,
    this.onJumpTo,
  });

  final SapForm form;

  /// Where this part sits when it is being filled in as one of three.
  ///
  /// Null means it was opened on its own — from the SDS Office's
  /// six-part list — and it keeps a plain header and a Save button.
  /// Given a step, it becomes part of the run: the bar shows all three,
  /// and the button carries on to the next rather than going back.
  final int? step;

  /// What to do after this part saves, when it is one of a run.
  final Future<void> Function(BuildContext)? onContinue;

  /// Goes back to an earlier step from the bar. Only steps already
  /// passed are offered: jumping forward would skip the point where
  /// the event record is made.
  final Future<void> Function(int)? onJumpTo;


  @override
  State<SapPart3Screen> createState() => _SapPart3ScreenState();
}

class _SapPart3ScreenState extends State<SapPart3Screen> {
  late final SapForm _form = widget.form;

  /// The headings a real filled form uses, in the order it uses them.
  /// Taken from the submitted copies rather than invented: a blank box
  /// labelled "other details" is how this part gets left empty.
  static const List<String> _otherDetailHeadings = [
    'Attendance monitoring',
    'Focus',
    'Attire',
    'Guest speaker coordination',
    'Class interruption notice',
    'Educational continuity',
    'Certificates or credits',
    'Registration process',
    'Target audience',
    'Documentation and media coverage',
  ];

  static String _hintFor(String heading) => switch (heading) {
    'Attendance monitoring' => 'A registration log sheet will be used…',
    'Focus' => 'What the activity is for, in a sentence or two',
    'Attire' => 'Organizational shirt or decent civilian attire',
    'Guest speaker coordination' => 'Who is being approached, and when',
    'Class interruption notice' => 'Which students are excused, and by whom',
    'Educational continuity' => 'What affected classes get instead',
    'Certificates or credits' => 'What participants receive',
    'Registration process' => 'Where and when they sign in',
    'Target audience' => 'Who it is for',
    _ => 'Who is photographing it, and what for',
  };

  /// One breakdown row, as the paper prints it.
  ///
  /// Quantity and unit cost are left out when they say nothing — one of
  /// something, at a price the paper never gave — so an ordinary row
  /// still reads as a single figure.
  String _budgetLine(SapBudgetItem item) {
    final amount = _peso(SapForm.centavos(item.amount));
    final unit = item.unitCost;

    if (item.quantity <= 1 && unit == null) return amount;
    if (unit == null) return '${item.quantity} · $amount';
    return '${item.quantity} × ${_peso(SapForm.centavos(unit))} · $amount';
  }

  /// What the backend will take for this whole part.
  ///
  /// Raised from 500 to 4000 by the backend on 24 Oct, which is what
  /// made a real proposal fillable: the two filled forms we measured run
  /// about 1,500 characters across the ten headings, so 500 refused them
  /// outright. Raised again to 10000 on 26 Oct for the longer ones.
  static const int _otherDetailsLimit = 10000;

  late final Map<String, TextEditingController> _otherDetails = {
    for (final heading in _otherDetailHeadings)
      heading: TextEditingController(
        text: _sectionOf(heading, _form.details.additionalInformation ?? ''),
      ),
  };

  /// Reads one heading back out of the stored text. The headings are
  /// written by this screen, so they are reliable delimiters.
  static String _sectionOf(String heading, String stored) {
    final start = stored.indexOf('$heading:');
    if (start < 0) return '';
    final from = start + heading.length + 1;
    final next = stored.indexOf('\n\n', from);
    return stored.substring(from, next < 0 ? stored.length : next).trim();
  }

  /// The headings and their answers, as one block, skipping the blanks.
  String get _composedOtherDetails => [
    for (final heading in _otherDetailHeadings)
      if (_otherDetails[heading]!.text.trim().isNotEmpty)
        '$heading: ${_otherDetails[heading]!.text.trim()}',
  ].join('\n\n');

  int get _otherDetailsLength => _composedOtherDetails.length;
  late final _excuse = TextEditingController(
    text: _form.details.excuseArrangement ?? '',
  );

  bool get _editable => _form.canEditProposerParts;

  @override
  void dispose() {
    for (final c in _otherDetails.values) {
      c.dispose();
    }
    _excuse.dispose();
    super.dispose();
  }

  /// Sums the lines as exact centavos.
  ///
  /// Parsed as integer centavos rather than a double: the server compares
  /// decimals exactly, and 2000.00 + 300.00 + 200.00 is the kind of sum
  /// binary floating point gets wrong by a hundredth.
  int get _totalCentavos {
    var total = 0;
    for (final item in _form.budgetItems) {
      total += SapForm.centavos(item.amount);
    }
    return total;
  }

  /// Centavos in, the app's own money format out.
  ///
  /// The arithmetic stays in whole centavos — the backend compares exact
  /// decimals — but the thousands separator has to match the rest of the
  /// app and the paper, which writes 1,500.00.
  static String _peso(int centavos) =>
      '₱${grouped(centavos ~/ 100, decimals: 0)}'
      '.${(centavos % 100).toString().padLeft(2, '0')}';

  /// The detail text and two collections, each its own endpoint. Stop at
  /// the first failure rather than firing the rest at a version the
  /// server has already rejected. Takes the typed text first, so saving on
  /// the way out keeps it too.
  Future<bool> _saveAll() async {
    _form.updateDetails(
      (d) => d.copyWith(
        additionalInformation: _composedOtherDetails,
        excuseArrangement: _excuse.text.trim(),
      ),
    );
    for (final save in [
      _form.saveDetails,
      _form.saveBudgetItems,
      _form.saveAffectedClasses,
    ]) {
      if (!await save()) return false;
    }
    return true;
  }

  Future<void> _save() async {
    final ok = await _saveAll();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_form.error ?? 'Could not save.')),
      );
      return;
    }
    if (widget.onContinue case final next?) {
      await next(context);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _addBudgetLine() async {
    final item = await showModalBottomSheet<SapBudgetItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BudgetLineSheet(),
    );
    if (item != null) _form.setBudgetItems([..._form.budgetItems, item]);
  }

  Future<void> _addClass() async {
    final item = await showModalBottomSheet<SapAffectedClass>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AffectedClassSheet(
        activityDate: _form.details.activityDate ?? DateTime.now(),
      ),
    );
    if (item != null) {
      _form.setAffectedClasses([..._form.affectedClasses, item]);
    }
  }

  /// Asks before leaving, and saves a draft if that is what they want.
  Future<void> _leave(BuildContext context) async {
    final navigator = Navigator.of(context);
    final leaving = await LeaveProposal.confirm(
      context,
      form: _form,
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
    if (leaving && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The phone's back button and swipe ask too, as the header's
      // does: they used to leave without a word, and an event made on
      // the way out of Part 1 stayed behind.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(context);
      },
      child: AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        final declared = _form.details.totalBudget;
        final summed = _totalCentavos;
        final ready = _form.missingForSubmit.isEmpty;
        final mismatch =
            declared != null &&
            declared.isNotEmpty &&
            _form.budgetItems.isNotEmpty &&
            SapForm.centavos(declared) != summed;

        return BrutScreen(
          // One of three when it is being filled in as a run, its own
          // screen when the SDS Office opens it from their six-part
          // list.
          header: widget.step == null
              ? BrutHeader(
                  title: 'Additional Information',
                  eyebrow: 'Part 3',
                  onBack: () => _leave(context),
                )
              : BrutFlowHeader(
                  title: 'Additional Information',
                  flowName: 'Part 3 of 3',
                  currentStep: widget.step!,
                  onBack: () => _leave(context),
                  steps: [
                    for (var i = 0; i < ProposalSteps.labels.length; i++)
                      BrutStep(
                        label: ProposalSteps.labels[i],
                        onJump: (widget.onJumpTo != null && i < widget.step!)
                            ? () => widget.onJumpTo!(i)
                            : null,
                      ),
                  ],
                ),
          // One back button, in the header. There were two doing the
          // same thing, and neither said whether anything was kept.
          footer: BrutFooter(
            child: BrutButton(
              label: widget.step == null ? 'Save' : 'Send for review',
              busy: _form.saving,
              busyLabel: 'Saving',
              // As a run's last step this sends it, and a half-filled
              // proposal is not sent.
              onPressed: _editable && (widget.step == null || ready)
                  ? _save
                  : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.step != null && _editable && !ready) ...[
                MissingForSubmit(_form.missingForSubmit),
                const SizedBox(height: 14),
              ],
              const BrutSectionTitle('Budget breakdown'),
              const SizedBox(height: 8),
              if (_form.budgetItems.isEmpty)
                const BrutInlineMessage(
                  tone: BrutTone.neutral,
                  icon: Icons.receipt_long,
                  text: 'No lines yet.',
                ),
              for (var i = 0; i < _form.budgetItems.length; i++) ...[
                SapRowCard(
                  title: _form.budgetItems[i].particulars,
                  // The paper's row reads across: how many, at what each,
                  // coming to what. Showing only the total hid the two
                  // columns the office checks the arithmetic against.
                  subtitle: _budgetLine(_form.budgetItems[i]),
                  onRemove: _editable
                      ? () => _form.setBudgetItems(
                          [..._form.budgetItems]..removeAt(i),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              if (_form.budgetItems.isNotEmpty) ...[
                const SizedBox(height: 4),
                BrutCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const MonoLabel('TOTAL'),
                      Text(_peso(summed), style: AppText.moneyLarge),
                    ],
                  ),
                ),
              ],
              if (mismatch) ...[
                const SizedBox(height: 10),
                BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.error_outline,
                  text:
                      'These lines come to ${_peso(summed)}, but Part 1 says '
                      '${_peso(SapForm.centavos(declared))}. They have to match '
                      'exactly before this can be submitted.',
                ),
              ],
              if (_editable) ...[
                const SizedBox(height: 10),
                BrutButton(
                  label: _form.budgetItems.length >=
                          SapProposal.maxCollectionItems
                      ? 'Sixteen lines is the limit'
                      : 'Add a line',
                  icon: Icons.add,
                  tone: BrutTone.neutral,
                  size: BrutSize.small,
                  onPressed: _form.budgetItems.length >=
                          SapProposal.maxCollectionItems
                      ? null
                      : _addBudgetLine,
                ),
              ],
              const SizedBox(height: 22),

              const BrutSectionTitle('Affected classes'),
              const SizedBox(height: 8),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.school_outlined,
                text:
                    'Declared by hand. Nothing is read from a timetable, and '
                    'each row has to overlap the activity on the same day.',
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < _form.affectedClasses.length; i++) ...[
                SapRowCard(
                  title:
                      '${_form.affectedClasses[i].yearLevel} · '
                      '${_form.affectedClasses[i].subject}',
                  subtitle:
                      '${_form.affectedClasses[i].start.label} – '
                      '${_form.affectedClasses[i].end.label} · '
                      '${_form.affectedClasses[i].professor}',
                  onRemove: _editable
                      ? () => _form.setAffectedClasses(
                          [..._form.affectedClasses]..removeAt(i),
                        )
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              if (_editable) ...[
                const SizedBox(height: 4),
                BrutButton(
                  label: 'Add a class',
                  icon: Icons.add,
                  tone: BrutTone.neutral,
                  size: BrutSize.small,
                  onPressed: _addClass,
                ),
              ],
              const SizedBox(height: 22),

              BrutTextField(
                controller: _excuse,
                label: 'Excuse letter arrangement',
                hint: 'How affected students will be excused',
                enabled: _editable,
                // The server's own limit. Without it the field accepts
                // whatever is typed and the refusal arrives as a 422
                // after Save, naming a field the writer cannot see.
                maxLength: 400,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text: 'Letters are not issued automatically; this is the plan '
                    'for them.',
              ),              // Last, not first. Ten long free-text headings opened
              // this step and buried the breakdown it is named for, which
              // is also the part with a total that has to agree.
              const BrutSectionTitle('Other details'),
              const SizedBox(height: 6),
              Text(
                'The headings a filled form uses. Leave any of them '
                'blank and they are simply left out.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              for (final heading in _otherDetailHeadings) ...[
                BrutTextField(
                  controller: _otherDetails[heading]!,
                  label: heading,
                  hint: _hintFor(heading),
                  enabled: _editable,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
              ],
              if (_otherDetailsLength > _otherDetailsLimit) ...[
                BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.error_outline,
                  text:
                      'These come to $_otherDetailsLength characters and the '
                      'server takes $_otherDetailsLimit. Shorten them before '
                      'submitting.',
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 10),


            ],
          ),
        );
      },
      ),
    );
  }
}

class _BudgetLineSheet extends StatefulWidget {
  const _BudgetLineSheet();

  @override
  State<_BudgetLineSheet> createState() => _BudgetLineSheetState();
}

class _BudgetLineSheetState extends State<_BudgetLineSheet> {
  final _particulars = TextEditingController();
  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _particulars.dispose();
    _quantity.dispose();
    _unitCost.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _valid =>
      _particulars.text.trim().isNotEmpty &&
      (double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? -1) >= 0;

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
          const BrutSectionTitle('Budget line'),
          const SizedBox(height: 12),
          BrutTextField(
            controller: _particulars,
            label: 'Particulars',
            hint: 'Guest speaker',
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          // The paper's own columns. Quantity and unit cost are what the
          // row shows; amount is what the office checks against the
          // total, so the server treats it as authoritative and does not
          // work it out from the other two.
          Row(
            children: [
              Expanded(
                child: BrutTextField(
                  controller: _quantity,
                  label: 'Quantity',
                  hint: '150',
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BrutTextField(
                  controller: _unitCost,
                  label: 'Unit cost',
                  hint: '10.00',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Both optional. Leave them out for a row the paper gives only '
            'a total for.',
            style: AppText.caption.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 12),
          BrutTextField(
            controller: _amount,
            label: 'Amount',
            hint: '2000.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          BrutButton(
            label: 'Add',
            onPressed: _valid
                ? () => Navigator.of(context).pop(
                    SapBudgetItem(
                      particulars: _particulars.text.trim(),
                      // Kept as typed text, never re-formatted through a
                      // double, so the decimal the server compares is the
                      // one the user wrote.
                      amount: _amount.text.trim().replaceAll(',', ''),
                      // Blank means one of the thing, which is what the
                      // server defaults to as well.
                      quantity:
                          int.tryParse(_quantity.text.trim()) ?? 1,
                      unitCost: _unitCost.text.trim().isEmpty
                          ? null
                          : _unitCost.text.trim().replaceAll(',', ''),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _AffectedClassSheet extends StatefulWidget {
  const _AffectedClassSheet({required this.activityDate});

  final DateTime activityDate;

  @override
  State<_AffectedClassSheet> createState() => _AffectedClassSheetState();
}

class _AffectedClassSheetState extends State<_AffectedClassSheet> {
  final _yearLevel = TextEditingController();
  final _subject = TextEditingController();
  final _professor = TextEditingController();
  SapTime? _start;
  SapTime? _end;

  @override
  void dispose() {
    _yearLevel.dispose();
    _subject.dispose();
    _professor.dispose();
    super.dispose();
  }

  bool get _valid =>
      _yearLevel.text.trim().isNotEmpty &&
      _subject.text.trim().isNotEmpty &&
      _professor.text.trim().isNotEmpty &&
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const BrutSectionTitle('Affected class'),
            const SizedBox(height: 12),
            BrutTextField(
              controller: _yearLevel,
              label: 'Year level',
              hint: 'BSCpE 3',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            BrutTextField(
              controller: _subject,
              label: 'Subject',
              hint: 'Data & Digital',
              onChanged: (_) => setState(() {}),
            ),
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
              controller: _professor,
              label: 'Professor',
              hint: 'Engr. Glazen Perez',
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            BrutButton(
              label: 'Add',
              onPressed: _valid
                  ? () => Navigator.of(context).pop(
                      SapAffectedClass(
                        yearLevel: _yearLevel.text.trim(),
                        subject: _subject.text.trim(),
                        // The server requires the class to fall on the
                        // activity's own day, so it is taken from there
                        // rather than asked for twice.
                        classDate: widget.activityDate,
                        start: _start!,
                        end: _end!,
                        professor: _professor.text.trim(),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
