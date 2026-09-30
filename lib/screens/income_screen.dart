import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import '../widgets/scope_picker.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

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
    final canRecord = app.currentRole?.canRecordFinance ?? false;

    return Scaffold(
      floatingActionButton: canRecord
          ? FloatingActionButton.extended(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _RecordIncomeSheet(),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Record Income'),
            )
          : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Income',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Money received, by where it came from.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              if (app.incomes.isNotEmpty) const _Totals(),
              if (app.incomes.isNotEmpty) const SizedBox(height: 12),
              Expanded(
                child: switch (load) {
                  _ when load.isLoading && app.incomes.isEmpty =>
                    const Center(child: CircularProgressIndicator()),
                  _ when load.hasFailed && app.incomes.isEmpty => Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(load.error!,
                                style: AppText.caption,
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: app.loadIncomes,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _ when app.incomes.isEmpty => _Empty(canRecord: canRecord),
                  _ => RefreshIndicator(
                      onRefresh: app.loadIncomes,
                      child: ListView.separated(
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
        ),
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
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
                    const Text('Counted', style: AppText.caption),
                    const SizedBox(height: 2),
                    Text('₱${app.countedIncomeTotal.toStringAsFixed(2)}',
                        style: AppText.moneyLarge),
                  ],
                ),
              ),
              if (withheld > 0)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Withheld', style: AppText.caption),
                      const SizedBox(height: 2),
                      Text(
                        '₱${withheld.toStringAsFixed(2)}',
                        style: AppText.moneySmall
                            .copyWith(color: AppColors.marigoldText),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (app.incomeBySource.isNotEmpty) ...[
            const Divider(height: 20),
            for (final entry in app.incomeBySource.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(entry.key.label, style: AppText.caption),
                    ),
                    Text('₱${entry.value.toStringAsFixed(2)}',
                        style: AppText.moneySmall),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Both the actual payer and the category — the breakdown
              // needs the type, a human needs the name.
              Expanded(child: Text(income.source, style: AppText.cardTitle)),
              Text(
                '₱${income.amount.toStringAsFixed(2)}',
                style: AppText.moneySmall.copyWith(
                  color: income.isWithheld
                      ? AppColors.inkFaint
                      : AppColors.sageTealText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(income.purpose, style: AppText.caption),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.indigoLightTint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  income.sourceType.label,
                  style: const TextStyle(
                    fontFamily: AppText.bodyFamily,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.indigo,
                  ),
                ),
              ),
              Text(
                '${income.receivedOn.year}-'
                '${income.receivedOn.month.toString().padLeft(2, '0')}-'
                '${income.receivedOn.day.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
            ],
          ),
          if (income.isWithheld) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.marigoldTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                income.withheldReason,
                style: AppText.caption.copyWith(color: AppColors.marigoldText),
              ),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.savings_outlined, size: 44, color: AppColors.inkFaint),
          const SizedBox(height: 14),
          const Text('No income recorded yet', style: AppText.cardTitle),
          const SizedBox(height: 6),
          SizedBox(
            width: 280,
            child: Text(
              canRecord
                  ? 'Record money as it comes in — fees, sponsorships and '
                      'donations each count separately in reports.'
                  : 'Income appears here once a Treasurer records it.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
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

  String? _eventId;
  FundSource _sourceType = FundSource.registrationFees;
  DateTime _receivedOn = DateTime.now();

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
    if (_eventId == null) return 'Choose the event this income is for.';
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
          eventId: _eventId!,
          source: _sourceController.text.trim(),
          sourceType: _sourceType,
          purpose: _purposeController.text.trim(),
          amount: MoneyInput.normalize(_amountController.text)!,
          receivedOn: _receivedOn,
        );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Income recorded.')),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _receivedOn,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
    );
    if (picked != null) setState(() => _receivedOn = picked);
  }

  @override
  Widget build(BuildContext context) {
    final events = context.watch<AppState>().events
        .where((e) => e.remoteId != null)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Record income', style: AppText.cardTitle),
              const SizedBox(height: 16),

              const Text('Event', style: AppText.caption),
              const SizedBox(height: 6),
              LabeledDropdown<String>(
                value: _eventId,
                hint: events.isEmpty ? 'No events available' : 'Select an event',
                items: [
                  for (final e in events)
                    DropdownMenuItem(value: e.remoteId, child: Text(e.title)),
                ],
                onChanged: (v) => setState(() => _eventId = v),
              ),
              const SizedBox(height: 14),

              const Text('Source type', style: AppText.caption),
              const SizedBox(height: 6),
              LabeledDropdown<FundSource>(
                value: _sourceType,
                hint: 'Select a source type',
                items: [
                  for (final s in FundSource.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _sourceType = v ?? _sourceType),
              ),
              const SizedBox(height: 4),
              Text(
                _sourceType.hint,
                style: const TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 10,
                  color: AppColors.inkFaint,
                ),
              ),
              const SizedBox(height: 14),

              const Text('Received from', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _sourceController,
                decoration: const InputDecoration(
                  hintText: 'The actual payer, e.g. ABC Corporation',
                ),
              ),
              const SizedBox(height: 14),

              const Text('Purpose', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _purposeController,
                decoration: const InputDecoration(
                  hintText: 'What the money is for',
                ),
              ),
              const SizedBox(height: 14),

              const Text('Amount', style: AppText.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: '₱ '),
              ),
              const SizedBox(height: 14),

              const Text('Received on', style: AppText.caption),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_receivedOn.year}-'
                    '${_receivedOn.month.toString().padLeft(2, '0')}-'
                    '${_receivedOn.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontFamily: AppText.bodyFamily,
                      fontSize: 13,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brick.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _error!,
                    style: AppText.caption.copyWith(color: AppColors.brick),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                style:
                    FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Record income'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
