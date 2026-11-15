import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import '../widgets/brut_date_picker.dart';
import '../widgets/event_picker_items.dart';
import '../theme/peso.dart';

/// Income recorded against events, by fund source.
///
/// Two things this screen is careful about:
///
///  * Income whose receipt is pending or rejected is **withheld from
///    totals**. It stays visible and labelled rather than disappearing, so
///    the ledger and the totals can be reconciled by eye.
///  * There is no edit or delete endpoint, so there are no such buttons.
///    A control that cannot work is worse than its absence.
class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().loadIncomes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final load = app.incomesLoad;
    final canRecord = app.mayRecordFinance;

    return BrutScreen(
      floatingActionButton: canRecord
          ? FloatingActionButton.extended(
              onPressed: () => BrutSheet.show<void>(
                context,
                builder: (_) => const _RecordIncomeSheet(),
              ),
              icon: const Icon(Icons.add),
              label: Text('Record income', style: AppText.buttonLabel),
            )
          : null,
      topBar: AppHeader(onBack: () => Navigator.of(context).maybePop()),
      scrollable: false,
      bottomPadding: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Income', style: AppText.display),
          const SizedBox(height: 4),
          const Text(
            'Money received, by where it came from.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          if (app.incomes.isNotEmpty) const _Totals(),
          if (app.incomes.isNotEmpty) const SizedBox(height: 12),
          Expanded(
            child: switch (load) {
              _ when load.isLoading && app.incomes.isEmpty => const Center(
                child: BrutSpinner(),
              ),
              _ when load.hasFailed && app.incomes.isEmpty => BrutRetry(
                title: 'Could not load income',
                message: load.error,
                sessionExpired: load.sessionExpired,
                onRetry: app.loadIncomes,
              ),
              _ when app.incomes.isEmpty => _Empty(canRecord: canRecord),
              _ => RefreshIndicator(
                onRefresh: () => app.refreshList(app.loadIncomes),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: app.incomes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _IncomeCard(income: app.incomes[i]),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// Counted and withheld shown side by side, never summed together.
class _Totals extends StatelessWidget {
  const _Totals();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final withheld = app.withheldIncomeTotal;

    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const MonoLabel('Counted'),
                    const SizedBox(height: 4),
                    Text(
                      '${peso(app.countedIncomeTotal)}',
                      style: AppText.moneyLarge,
                    ),
                  ],
                ),
              ),
              // Never summed with the counted figure: withheld money has
              // not been accepted into the ledger.
              if (withheld > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MonoLabel('Withheld'),
                      const SizedBox(height: 4),
                      Text(
                        '${peso(withheld)}',
                        style: AppText.moneyLarge.copyWith(
                          fontSize: 16,
                          color: context.palette.subtle,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (app.incomeBySource.isNotEmpty) ...[
            const Divider(height: 22),
            for (final entry in app.incomeBySource.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(child: MonoLabel(entry.key.label)),
                    Text('${peso(entry.value)}', style: AppText.number),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.income});

  final Income income;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Both the actual payer and the category — the breakdown
              // needs the type, a human needs the name.
              Expanded(child: Text(income.source, style: AppText.cardTitle)),
              const SizedBox(width: 10),
              Text(
                '${peso(income.amount)}',
                style: AppText.moneyLarge.copyWith(
                  fontSize: 16,
                  color: income.isWithheld
                      ? context.palette.muted
                      : context.palette.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(income.purpose, style: AppText.caption),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              BrutBadge(label: income.sourceType.label, tone: BrutTone.brand),
              if (income.isGeneralFund)
                BrutBadge(
                  label: [
                    'General fund',
                    ?income.schoolYear,
                    if (semesterFromWire(income.semester) case final s?)
                      s.shortLabel,
                  ].join(' · '),
                ),
              MonoLabel(
                '${income.receivedOn.year}-'
                '${income.receivedOn.month.toString().padLeft(2, '0')}-'
                '${income.receivedOn.day.toString().padLeft(2, '0')}',
              ),
            ],
          ),
          if (income.isWithheld) ...[
            const SizedBox(height: 12),
            BrutInlineMessage(
              text: income.withheldReason,
              tone: BrutTone.sun,
              icon: Icons.pause_circle_outline,
            ),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.canRecord});

  final bool canRecord;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BrutEmptyState(
        icon: Icons.savings_outlined,
        title: 'No income recorded yet',
        hint: canRecord
            ? 'Record money as it comes in — fees, sponsorships and '
                  'donations each count separately in reports.'
            : 'Income appears here once an officer or the Treasurer '
                  'records it.',
      ),
    );
  }
}

/// Recording form.
///
/// Every field here is required by the backend. Note what is absent: there
/// is no way to derive income from an event's allocated budget, because a
/// budget is a plan and income is money that actually arrived.
class _RecordIncomeSheet extends StatefulWidget {
  const _RecordIncomeSheet();

  @override
  State<_RecordIncomeSheet> createState() => _RecordIncomeSheetState();
}

class _RecordIncomeSheetState extends State<_RecordIncomeSheet> {
  final _sourceController = TextEditingController();
  final _purposeController = TextEditingController();
  final _amountController = TextEditingController();

  /// The chosen event, or [_generalFund] for money that belongs to none.
  String? _eventId;
  FundSource _sourceType = FundSource.registrationFees;
  DateTime _receivedOn = DateTime.now();

  // A dropdown value null is not, since null means nothing chosen yet.
  static const _generalFund = '';
  bool get _isGeneral => _eventId == _generalFund;
  String _schoolYear = SchoolYear.current(DateTime.now());
  Semester? _semester;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _sourceController.dispose();
    _purposeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_eventId == null) {
      return 'Choose the event this income is for, or the general fund.';
    }
    if (_isGeneral && _semester == null) {
      return 'Choose the semester this general-fund income belongs to.';
    }
    if (_sourceController.text.trim().isEmpty) {
      return 'Enter who or what the money came from.';
    }
    if (_purposeController.text.trim().isEmpty) {
      return 'Enter what this income is for.';
    }
    return MoneyInput.validate(_amountController.text);
  }

  Future<void> _submit() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final error = await context.read<AppState>().recordIncome(
      eventId: _isGeneral ? null : _eventId!,
      source: _sourceController.text.trim(),
      sourceType: _sourceType,
      purpose: _purposeController.text.trim(),
      amount: MoneyInput.normalize(_amountController.text)!,
      receivedOn: _receivedOn,
      schoolYear: _isGeneral ? _schoolYear : null,
      semester: _isGeneral ? _semester : null,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Income recorded.')));
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await BrutDatePicker.show(
      context,
      initial: _receivedOn,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      title: 'When did it come in?',
    );
    if (picked != null) setState(() => _receivedOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = [
      const DropdownMenuItem(
        value: _generalFund,
        child: Text('General fund (no event)'),
      ),
      ...eventPickerItems(app.events, keep: _eventId),
    ];

    return BrutSheet(
      title: 'Record income',
      footer: BrutButton(
        label: 'Record income',
        size: BrutSize.large,
        busy: _submitting,
        busyLabel: 'Recording…',
        onPressed: _submit,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutDropdown<String>(
            label: 'Event',
            value: _eventId,
            hint: 'Select an event or the general fund',
            items: items,
            onChanged: (v) => setState(() {
              _eventId = v;
              // Dues are what the general fund mostly holds.
              if (_isGeneral && _sourceType == FundSource.registrationFees) {
                _sourceType = FundSource.membershipDues;
              }
            }),
          ),
          if (_isGeneral) ...[
            const SizedBox(height: 6),
            const Text(
              'Money for the organization itself, such as membership dues. '
              'It has no event, so it is labelled with a school year and '
              'semester instead, and cannot carry a receipt here.',
              style: AppText.caption,
            ),
            const SizedBox(height: 14),
            BrutDropdown<String>(
              label: 'School year',
              value: _schoolYear,
              hint: 'Select a school year',
              items: [
                for (final year in SchoolYear.mergeOptions(
                  app.knownSchoolYears,
                  DateTime.now(),
                ))
                  DropdownMenuItem(value: year, child: Text(year)),
              ],
              onChanged: (v) => setState(() => _schoolYear = v ?? _schoolYear),
            ),
            const SizedBox(height: 14),
            BrutDropdown<Semester>(
              label: 'Semester',
              value: _semester,
              hint: 'Select a semester',
              items: [
                for (final s in Semester.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _semester = v),
            ),
          ],
          const SizedBox(height: 14),
          BrutDropdown<FundSource>(
            label: 'Source type',
            value: _sourceType,
            hint: 'Select a source type',
            items: [
              for (final s in FundSource.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) => setState(() => _sourceType = v ?? _sourceType),
          ),
          const SizedBox(height: 6),
          Text(_sourceType.hint, style: AppText.caption),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Received from',
            controller: _sourceController,
            hint: 'The actual payer, e.g. ABC Corporation',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Purpose',
            controller: _purposeController,
            hint: 'What the money is for',
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Amount',
            controller: _amountController,
            prefixIcon: Icons.payments_outlined,
            hint: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 14),
          BrutDateField(
            label: 'Received on',
            value: _receivedOn,
            hint: 'Select a date',
            onTap: _pickDate,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            BrutInlineMessage(text: _error!, tone: BrutTone.coral),
          ],
        ],
      ),
    );
  }
}
