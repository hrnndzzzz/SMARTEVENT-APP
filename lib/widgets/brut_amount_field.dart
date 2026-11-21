import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';
import '../theme/peso.dart';

/// An amount, with the figure given the room it deserves.
///
/// Asked for with a reference image: a minus, the value, a plus, the
/// three of them the whole width of the card. The reference is soft
/// and inset; this is the app's own language — flat fills, hard
/// borders — because a transplanted control looks like a mistake next
/// to everything else here.
///
/// ## Why the field is still a field
///
/// A stepper alone cannot say 2,347.50, and a form that makes someone
/// press plus twenty-three times is worse than the one it replaced.
/// Typing stays exactly as it was; the buttons are for the amounts
/// people actually enter, which cluster on round numbers.
///
/// ## Why stepping rewrites the text and typing does not
///
/// The SAP breakdown compares its decimal against the server's
/// character for character, so what someone types is left alone. A
/// step is a different thing: the person asked for a round number, so
/// writing back a clean one is what they asked for.
class BrutAmountField extends StatefulWidget {
  const BrutAmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.hint = '0.00',
    this.required = false,
    this.enabled = true,
    this.steps = const [100, 500, 1000],
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool required;
  final bool enabled;

  /// What the quick buttons add. The first is also what the minus
  /// takes away.
  final List<int> steps;

  final ValueChanged<String>? onChanged;

  @override
  State<BrutAmountField> createState() => _BrutAmountFieldState();
}

class _BrutAmountFieldState extends State<BrutAmountField> {
  double get _value =>
      double.tryParse(widget.controller.text.trim().replaceAll(',', '')) ?? 0;

  bool get _canSubtract => widget.enabled && _value > 0;

  void _by(num delta) {
    // Never below zero: an amount owed is not an amount, and the
    // field it feeds refuses a negative anyway.
    final next = (_value + delta).clamp(0, double.maxFinite).toDouble();
    final text = next.toStringAsFixed(2);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    HapticFeedback.selectionClick();
    widget.onChanged?.call(text);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final step = widget.steps.isEmpty ? 100 : widget.steps.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RequiredLabel(widget.label, required: widget.required),
        const SizedBox(height: 6),
        // Minus, the figure, plus — the reference's shape. The two
        // buttons are square and the field takes the rest, so the
        // amount is the widest thing in the row rather than three
        // equal thirds.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Step(
                icon: Icons.remove,
                label: 'Take off ${peso(step, decimals: 0)}',
                onPressed: _canSubtract ? () => _by(-step) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BrutTextField(
                  controller: widget.controller,
                  hint: widget.hint,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    widget.onChanged?.call(v);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              _Step(
                icon: Icons.add,
                label: 'Add ${peso(step, decimals: 0)}',
                onPressed: widget.enabled ? () => _by(step) : null,
              ),
            ],
          ),
        ),
        if (widget.enabled && widget.steps.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in widget.steps.skip(1))
                BrutChip(
                  label: '+${peso(s, decimals: 0)}',
                  selected: false,
                  onTap: () => _by(s),
                ),
              if (_value > 0)
                BrutChip(
                  label: 'Clear',
                  selected: false,
                  tone: BrutTone.coral,
                  onTap: () {
                    widget.controller.clear();
                    widget.onChanged?.call('');
                    setState(() {});
                  },
                ),
            ],
          ),
        ],
        // What the figure actually comes to, spelled out. A long
        // number typed without separators is easy to get wrong by a
        // factor of ten, and this is the place that costs money.
        if (_value > 0) ...[
          const SizedBox(height: 6),
          Text(
            peso(_value),
            style: AppText.caption.copyWith(
              color: p.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return BrutIconButton(
      icon: icon,
      label: label,
      size: 46,
      tone: BrutTone.neutral,
      onPressed: onPressed,
    );
  }
}
