import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

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
    final picked = await showDatePicker(
      context: context,
      initialDate: (paid ? _paidOn : _receivedOn) ?? now,
      firstDate: DateTime(now.year - 3),
      // Neither date may be in the future, so the picker cannot offer one.
      lastDate: now,
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
        quantities: {
          for (final e in _quantities.entries) e.key: e.value.text,
        },
        units: {
          for (final e in _units.entries) e.key: e.value.text,
        },
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

    final error =
        await context.read<AppState>().completePurchase(widget.expense, completion);

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
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Complete purchase',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Adds the asset lines of “${widget.expense.vendor}” to stock. '
                'This happens once and cannot be repeated.',
                style: AppText.caption,
              ),
              const SizedBox(height: 20),

              const _Label('Paid on'),
              const SizedBox(height: 6),
              _DateField(
                value: _paidOn,
                hint: 'Select the payment date',
                onTap: () => _pickDate(paid: true),
              ),
              const SizedBox(height: 14),

              const _Label('Received on'),
              const SizedBox(height: 6),
              _DateField(
                value: _receivedOn,
                hint: 'Select the delivery date',
                onTap: () => _pickDate(paid: false),
              ),
              const SizedBox(height: 14),

              const _Label('Amount paid'),
              const SizedBox(height: 6),
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '₱ ',
                  helperText: 'Must equal the expense total of '
                      '₱${widget.expense.amount.toStringAsFixed(2)}.',
                ),
              ),
              const SizedBox(height: 14),

              const _Label('Payment method'),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PaymentMethod>(
                    isExpanded: true,
                    value: _method,
                    items: [
                      for (final method in PaymentMethod.values)
                        DropdownMenuItem(
                          value: method,
                          child: Text(
                            method.label,
                            style: const TextStyle(
                              fontFamily: AppText.bodyFamily,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? _method),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              const _Label('Payment reference'),
              const SizedBox(height: 6),
              TextField(
                controller: _referenceController,
                decoration: const InputDecoration(hintText: 'e.g. PAY-2026-001'),
              ),
              const SizedBox(height: 14),

              const _Label('Supplier'),
              const SizedBox(height: 6),
              TextField(
                controller: _vendorController,
                decoration: const InputDecoration(hintText: 'Actual supplier'),
              ),
              const SizedBox(height: 22),

              const Text('Items received', style: AppText.cardTitle),
              const SizedBox(height: 2),
              const Text(
                'Confirm what actually arrived. Consumables are not stocked '
                'by this step and are not listed.',
                style: AppText.caption,
              ),
              const SizedBox(height: 10),
              for (final line in widget.assetLines) ...[
                _LineConfirmation(
                  line: line,
                  quantity: _quantities[line.id]!,
                  unit: _units[line.id]!,
                ),
                const SizedBox(height: 10),
              ],
              if (widget.assetLines.isEmpty)
                const Text(
                  'No asset lines on this expense — nothing would enter stock.',
                  style: AppText.caption,
                ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brick.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brick.withValues(alpha: 0.3)),
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
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Record payment and delivery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppText.caption);
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.hint,
    required this.onTap,
  });

  final DateTime? value;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? hint
        : '${value!.year}-${value!.month.toString().padLeft(2, '0')}'
            '-${value!.day.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 13,
                  color: value == null ? AppColors.inkFaint : AppColors.ink,
                ),
              ),
            ),
            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.inkFaint),
          ],
        ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.name, style: AppText.body),
          const SizedBox(height: 2),
          Text('₱${line.amount.toStringAsFixed(2)}', style: AppText.caption),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: unit,
                  decoration: const InputDecoration(labelText: 'Unit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
