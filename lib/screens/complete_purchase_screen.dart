import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/brut_date_picker.dart';
import '../theme/peso.dart';

/// Record Payment and Delivery — the step that turns approved asset lines
/// into stock.
///
/// Rules enforced here so the user finds out before a round trip, and
/// re-enforced by the backend regardless:
///   * neither date may be in the future
///   * the full paid amount must equal the expense total
///   * every asset line appears exactly once, with the quantity actually
///     received; consumable and foreign lines are never included
///
/// It runs once. A second attempt on the same expense is refused.
class CompletePurchaseScreen extends StatefulWidget {
  const CompletePurchaseScreen({
    super.key,
    required this.expense,
    required this.assetLines,
  });

  final ExpenseEntry expense;
  final List<ExpenseLine> assetLines;

  @override
  State<CompletePurchaseScreen> createState() => _CompletePurchaseScreenState();
}

class _CompletePurchaseScreenState extends State<CompletePurchaseScreen> {
  late final TextEditingController _amountController = TextEditingController(
    // Pre-filled with the expense total, since it has to match exactly.
    text: MoneyInput.fromDouble(widget.expense.amount),
  );
  final _referenceController = TextEditingController();
  final _vendorController = TextEditingController();

  /// Quantity and unit actually received, per asset line.
  late final Map<String, TextEditingController> _quantities = {
    for (final line in widget.assetLines)
      line.id: TextEditingController(text: line.quantity.toString()),
  };
  late final Map<String, TextEditingController> _units = {
    for (final line in widget.assetLines)
      line.id: TextEditingController(text: line.unit),
  };

  DateTime? _paidOn;
  DateTime? _receivedOn;
  PaymentMethod _method = PaymentMethod.cash;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _vendorController.dispose();
    for (final c in _quantities.values) {
      c.dispose();
    }
    for (final c in _units.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool paid}) async {
    final now = DateTime.now();
    final picked = await BrutDatePicker.show(
      context,
      initial: (paid ? _paidOn : _receivedOn) ?? now,
      firstDate: DateTime(now.year - 3),
      // Neither date may be in the future, so the picker cannot offer one.
      lastDate: now,
      title: paid ? 'When was it paid?' : 'When did it arrive?',
    );
    if (picked == null) return;
    setState(() {
      if (paid) {
        _paidOn = picked;
      } else {
        _receivedOn = picked;
      }
    });
  }

  String? _validate() => purchaseCompletionProblem(
    assetLines: widget.assetLines,
    paidOn: _paidOn,
    receivedOn: _receivedOn,
    rawPaidAmount: _amountController.text,
    expenseTotal: widget.expense.amount,
    reference: _referenceController.text,
    vendor: _vendorController.text,
    quantities: {for (final e in _quantities.entries) e.key: e.value.text},
    units: {for (final e in _units.entries) e.key: e.value.text},
  );

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

    final completion = PurchaseCompletionInput(
      paidOn: _paidOn!,
      receivedOn: _receivedOn!,
      paidAmount: MoneyInput.normalize(_amountController.text)!,
      paymentMethod: _method,
      paymentReference: _referenceController.text.trim(),
      vendor: _vendorController.text.trim(),
      items: [
        for (final line in widget.assetLines)
          PurchaseLineConfirmation(
            expenseItemId: line.id,
            quantity: int.parse(_quantities[line.id]!.text.trim()),
            unit: _units[line.id]!.text.trim(),
          ),
      ],
    );

    final error = await context.read<AppState>().completePurchase(
      widget.expense,
      completion,
    );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });

    if (error == null) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase recorded. Stock updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      header: BrutHeader(
        eyebrow: 'Step 2 of 2 · Payment and delivery',
        title: 'Complete purchase',
        tone: BrutTone.mint,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      footer: BrutFooter(
        child: BrutButton(
          label: 'Record payment and delivery',
          tone: BrutTone.mint,
          size: BrutSize.large,
          busy: _submitting,
          busyLabel: 'Recording…',
          onPressed: _submit,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Adds the asset lines of “${widget.expense.vendor}” to '
            'stock. This happens once and cannot be repeated.',
            style: AppText.caption,
          ),
          const SizedBox(height: 20),
          BrutDateField(
            label: 'Paid on',
            value: _paidOn,
            hint: 'Select the payment date',
            onTap: () => _pickDate(paid: true),
          ),
          const SizedBox(height: 14),
          BrutDateField(
            label: 'Received on',
            value: _receivedOn,
            hint: 'Select the delivery date',
            onTap: () => _pickDate(paid: false),
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Amount paid',
            controller: _amountController,
            prefixIcon: Icons.payments_outlined,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 6),
          Text(
            'Must equal the expense total of '
            '${peso(widget.expense.amount)}.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          BrutDropdown<PaymentMethod>(
            label: 'Payment method',
            value: _method,
            hint: 'How it was paid',
            items: [
              for (final method in PaymentMethod.values)
                DropdownMenuItem(value: method, child: Text(method.label)),
            ],
            onChanged: (v) => setState(() => _method = v ?? _method),
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Payment reference',
            controller: _referenceController,
            hint: 'e.g. PAY-2026-001',
          ),
          const SizedBox(height: 14),
          BrutTextField(
            label: 'Supplier',
            controller: _vendorController,
            hint: 'Actual supplier',
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 24),
          const BrutSectionTitle('Items received'),
          const SizedBox(height: 4),
          const Text(
            'Confirm what actually arrived. Consumables are not '
            'stocked by this step and are not listed.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          for (final line in widget.assetLines) ...[
            _LineConfirmation(
              line: line,
              quantity: _quantities[line.id]!,
              unit: _units[line.id]!,
            ),
            const SizedBox(height: 10),
          ],
          if (widget.assetLines.isEmpty)
            const BrutEmptyState(
              title: 'No asset lines on this expense',
              hint: 'Nothing would enter stock.',
              icon: Icons.inventory_2_outlined,
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

class _LineConfirmation extends StatelessWidget {
  const _LineConfirmation({
    required this.line,
    required this.quantity,
    required this.unit,
  });

  final ExpenseLine line;
  final TextEditingController quantity;
  final TextEditingController unit;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Text('${peso(line.amount)}', style: AppText.number),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BrutTextField(
                  label: 'Quantity',
                  controller: quantity,
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BrutTextField(label: 'Unit', controller: unit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
