import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import 'proposal_steps.dart';
import '../../theme/brut.dart';

/// Part 2 — School Support (Requests).
///
/// The paper is a grid of tick boxes, three of which take a number or a
/// detail beside them. Rather than render dead boxes, this asks for the
/// detail as each one is ticked, which is the same information with
/// fewer ways to leave it half-filled.
class SapPart2Screen extends StatefulWidget {
  const SapPart2Screen({
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
  State<SapPart2Screen> createState() => _SapPart2ScreenState();
}

class _SapPart2ScreenState extends State<SapPart2Screen> {
  late final SapForm _form = widget.form;

  bool get _editable => _form.canEditProposerParts;

  /// Which types have a number on the paper: the microphone's quantity,
  /// the pax for food, the passenger count for a vehicle, and the
  /// chairs and tables, which a real form fills in as "additional 100
  /// chairs".
  static const _withQuantity = {
    SapSupportType.microphone,
    SapSupportType.food,
    SapSupportType.vehicle,
    SapSupportType.chairs,
    SapSupportType.tables,
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

  /// Asks before leaving, and saves a draft if that is what they want.
  Future<void> _leave(BuildContext context) async {
    final navigator = Navigator.of(context);
    final leaving = await LeaveProposal.confirm(
      context,
      save: () async {
        // What this step holds is the support requests, not the details.
        final ok = await _form.saveSupportRequests();
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
        return BrutScreen(
          // One of three when it is being filled in as a run, its own
          // screen when the SDS Office opens it from their six-part
          // list.
          header: widget.step == null
              ? BrutHeader(
                  title: 'School Support',
                  eyebrow: 'Part 2',
                  onBack: () => _leave(context),
                )
              : BrutFlowHeader(
                  title: 'School Support',
                  flowName: 'Part 2 of 3',
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
              label: widget.step == null ? 'Save' : 'Next: the breakdown',
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
                  // Every ticked row on the paper has room written
                  // beside it — "St. Augustine Bldg. AVR", "Podium",
                  // "additional 100 chairs" — so none of them is only
                  // a tick.
                  takesDetail: true,
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
                SapSupportType.room => 'St. Augustine Bldg. AVR',
                SapSupportType.vehicle => 'Where to, and back when',
                SapSupportType.food => 'What, and for whom',
                SapSupportType.sound => 'Anything particular',
                SapSupportType.microphone => 'Wired, wireless, lapel',
                SapSupportType.projector => 'Anything particular',
                SapSupportType.chairs => 'Additional 100 chairs',
                SapSupportType.tables => 'How many, and where',
                SapSupportType.diverseNeeds => 'What is needed',
                SapSupportType.other => 'Podium',
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
