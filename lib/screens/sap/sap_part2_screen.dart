import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/brut.dart';

/// Part 2 — School Support (Requests).
///
/// The paper is a grid of tick boxes, three of which take a number or a
/// detail beside them. Rather than render dead boxes, this asks for the
/// detail as each one is ticked, which is the same information with
/// fewer ways to leave it half-filled.
class SapPart2Screen extends StatefulWidget {
  const SapPart2Screen({super.key, required this.form});

  final SapForm form;

  @override
  State<SapPart2Screen> createState() => _SapPart2ScreenState();
}

class _SapPart2ScreenState extends State<SapPart2Screen> {
  late final SapForm _form = widget.form;

  bool get _editable => _form.canEditProposerParts;

  /// Which types take a count, and which take free text. The rest are a
  /// plain tick.
  static const _withQuantity = {
    SapSupportType.microphone,
    SapSupportType.food,
  };
  static const _withDetail = {
    SapSupportType.budget,
    SapSupportType.room,
    SapSupportType.vehicle,
    SapSupportType.diverseNeeds,
    SapSupportType.other,
  };

  SapSupportRequest? _requestFor(SapSupportType type) {
    for (final r in _form.supportRequests) {
      if (r.type == type) return r;
    }
    return null;
  }

  void _toggle(SapSupportType type) {
    final existing = _requestFor(type);
    final next = [..._form.supportRequests];
    if (existing != null) {
      next.removeWhere((r) => r.type == type);
    } else {
      next.add(SapSupportRequest(type: type));
    }
    _form.setSupportRequests(next);
  }

  /// The backend requires a quantity of at least one on every row, so an
  /// emptied box means one rather than none — a ticked row with no number
  /// beside it is still a request for the thing.
  void _amend(SapSupportType type, {int? quantity, String? specify}) {
    final next = [
      for (final r in _form.supportRequests)
        if (r.type == type)
          SapSupportRequest(
            type: type,
            quantity: quantity ?? r.quantity,
            specify: specify ?? r.specify,
          )
        else
          r,
    ];
    _form.setSupportRequests(next);
  }

  Future<void> _save() async {
    final ok = await _form.saveSupportRequests();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_form.error ?? 'Could not save.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        return BrutScreen(
          header: BrutHeader(
            title: 'School Support',
            eyebrow: 'Part 2',
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
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text:
                    'Anything ticked here still needs its own requisition '
                    'form sent to the office concerned.',
              ),
              const SizedBox(height: 14),
              for (final type in SapSupportType.values) ...[
                _SupportTile(
                  type: type,
                  request: _requestFor(type),
                  enabled: _editable,
                  takesQuantity: _withQuantity.contains(type),
                  takesDetail: _withDetail.contains(type),
                  onToggle: () => _toggle(type),
                  onQuantity: (q) => _amend(type, quantity: q),
                  onDetail: (s) => _amend(type, specify: s),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One tick box, with the number or detail the paper prints beside it.
///
/// Stateful for its controllers: building them in `build` would rebuild
/// them on every keystroke and send the cursor back to the start.
class _SupportTile extends StatefulWidget {
  const _SupportTile({
    required this.type,
    required this.request,
    required this.enabled,
    required this.takesQuantity,
    required this.takesDetail,
    required this.onToggle,
    required this.onQuantity,
    required this.onDetail,
  });

  final SapSupportType type;
  final SapSupportRequest? request;
  final bool enabled;
  final bool takesQuantity;
  final bool takesDetail;
  final VoidCallback onToggle;
  final ValueChanged<int?> onQuantity;
  final ValueChanged<String> onDetail;

  @override
  State<_SupportTile> createState() => _SupportTileState();
}

class _SupportTileState extends State<_SupportTile> {
  late final _quantity = TextEditingController(
    text: widget.request?.quantity.toString() ?? '',
  );
  late final _detail = TextEditingController(
    text: widget.request?.specify ?? '',
  );

  @override
  void dispose() {
    _quantity.dispose();
    _detail.dispose();
    super.dispose();
  }

  bool get _ticked => widget.request != null;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutChip(
            label: widget.type.label,
            selected: _ticked,
            onTap: widget.enabled ? widget.onToggle : () {},
          ),
          if (_ticked && widget.takesQuantity) ...[
            const SizedBox(height: 10),
            BrutTextField(
              label: 'How many',
              hint: '2',
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              controller: _quantity,
              onChanged: (v) => widget.onQuantity(int.tryParse(v.trim()) ?? 1),
            ),
          ],
          if (_ticked && widget.takesDetail) ...[
            const SizedBox(height: 10),
            BrutTextField(
              label: 'Please specify',
              hint: switch (widget.type) {
                SapSupportType.budget => 'How much, and what for',
                SapSupportType.room => 'Which room or venue',
                SapSupportType.vehicle => 'Number of passengers',
                SapSupportType.diverseNeeds => 'What is needed',
                _ => 'Details',
              },
              enabled: widget.enabled,
              controller: _detail,
              onChanged: widget.onDetail,
            ),
          ],
        ],
      ),
    );
  }
}
