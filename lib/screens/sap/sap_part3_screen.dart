import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
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
  const SapPart3Screen({super.key, required this.form});

  final SapForm form;

  @override
  State<SapPart3Screen> createState() => _SapPart3ScreenState();
}

class _SapPart3ScreenState extends State<SapPart3Screen> {
  late final SapForm _form = widget.form;

  late final _additional = TextEditingController(
    text: _form.details.additionalInformation ?? '',
  );
  late final _excuse = TextEditingController(
    text: _form.details.excuseArrangement ?? '',
  );

  bool get _editable => _form.canEditProposerParts;

  @override
  void dispose() {
    _additional.dispose();
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
      total += _centavos(item.amount);
    }
    return total;
  }

  static int _centavos(String amount) {
    final cleaned = amount.replaceAll(',', '').trim();
    final parts = cleaned.split('.');
    final whole = int.tryParse(parts.first) ?? 0;
    final frac = parts.length > 1
        ? int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0
        : 0;
    return whole * 100 + frac;
  }

  static String _peso(int centavos) =>
      '₱${(centavos ~/ 100)}.${(centavos % 100).toString().padLeft(2, '0')}';

  Future<void> _save() async {
    _form.updateDetails(
      (d) => d.copyWith(
        additionalInformation: _additional.text.trim(),
        excuseArrangement: _excuse.text.trim(),
      ),
    );

    // Three collections and the detail text, each its own endpoint. Stop
    // at the first failure rather than firing the rest at a version the
    // server has already rejected.
    for (final save in [
      _form.saveDetails,
      _form.saveBudgetItems,
      _form.saveAffectedClasses,
    ]) {
      if (!await save()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_form.error ?? 'Could not save.')),
        );
        return;
      }
    }
    if (mounted) Navigator.of(context).maybePop();
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        final declared = _form.details.totalBudget;
        final summed = _totalCentavos;
        final mismatch =
            declared != null &&
            declared.isNotEmpty &&
            _form.budgetItems.isNotEmpty &&
            _centavos(declared) != summed;

        return BrutScreen(
          header: BrutHeader(
            title: 'Additional Information',
            eyebrow: 'Part 3',
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
              BrutTextField(
                controller: _additional,
                label: 'Other details',
                hint: 'Anything the offices should know',
                enabled: _editable,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 22),

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
                  subtitle: _peso(_centavos(_form.budgetItems[i].amount)),
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
                      '${_peso(_centavos(declared))}. They have to match '
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
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 8),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text: 'Letters are not issued automatically; this is the plan '
                    'for them.',
              ),
            ],
          ),
        );
      },
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
  final _amount = TextEditingController();

  @override
  void dispose() {
    _particulars.dispose();
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
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
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
