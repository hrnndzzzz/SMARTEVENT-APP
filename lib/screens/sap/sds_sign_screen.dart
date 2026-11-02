import 'package:flutter/material.dart';

import '../../api/models/sap_proposal.dart';
import '../../state/sap_form.dart';
import '../../theme/app_theme.dart';
import '../../theme/brut.dart';
import 'sap_form_fields.dart';
import 'signature_pad.dart';

/// The SDS Office's review of a pending revision: remarks, then one of
/// three decisions — return it, reject it, or sign it.
///
/// Remarks can be saved as often as the office likes. The decisions cannot
/// be undone — signing locks the revision and stores the signed PDF, a
/// rejection is final, and a return starts a new revision — so each
/// confirms first, and says plainly what it is about to do.
class SdsSignScreen extends StatefulWidget {
  const SdsSignScreen({super.key, required this.form});

  final SapForm form;

  @override
  State<SdsSignScreen> createState() => _SdsSignScreenState();
}

class _SdsSignScreenState extends State<SdsSignScreen> {
  SapForm get _form => widget.form;

  late final _overall = TextEditingController(text: _form.overallRemarks);
  final Map<SapRemarkSection, TextEditingController> _sections = {
    for (final s in SapRemarkSection.values) s: TextEditingController(),
  };

  SapSignature _signature = const SapSignature([]);

  @override
  void initState() {
    super.initState();
    for (final entry in _form.sectionRemarks.entries) {
      _sections[entry.key]?.text = entry.value;
    }
  }

  @override
  void dispose() {
    _overall.dispose();
    for (final c in _sections.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Only a revision that is waiting can be reviewed. A signed one is
  /// locked, and a draft has not been sent yet.
  bool get _open => _form.state == SapState.pendingReview;

  /// The server refuses to sign until Part 4 is saved, so the pad waits
  /// for it too. Remarks do not: the office may send it back instead.
  bool get _cleared => _form.proposal?.clearance != null;

  /// Returning and rejecting both owe the organization a reason, and the
  /// server refuses a blank one. They do not need Part 4: the office may
  /// send a proposal back before filling it in.
  bool get _hasReason => _overall.text.trim().isNotEmpty;

  /// Nothing is sent from a stale form: every request would carry the old
  /// version and be refused again, so the way on is to reload it first.
  bool get _canDecide =>
      _open && _hasReason && !_form.saving && !_form.isStale;

  void _collect() {
    _form.overallRemarks = _overall.text.trim();
    _form.sectionRemarks = {
      for (final entry in _sections.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };
  }

  Future<void> _saveNotes() async {
    _collect();
    final problem = await _form.saveReviewNotes();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(problem ?? 'Remarks saved.')),
    );
  }

  Future<void> _sign() async {
    final problem = _signature.problem;
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem)),
      );
      return;
    }

    await _decide(
      title: 'Sign this proposal?',
      body:
          'This locks the revision and stores the signed form. It cannot '
          'be undone: a proposal that needs changing afterwards has to be '
          'returned and signed again as a new revision.',
      action: 'Sign',
      send: () => _form.sdsSign(_signature),
      done: 'Signed. The form is locked.',
    );
  }

  /// Asks first, then sends the remarks as they stand and says how it went.
  /// A decision that went through leaves the screen; one that did not stays,
  /// with what was typed.
  Future<void> _decide({
    required String title,
    required String body,
    required String action,
    required Future<String?> Function() send,
    required String done,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _collect();
    final failure = await send();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure ?? done)),
    );
    if (failure == null) Navigator.of(context).maybePop();
  }

  Future<void> _return() => _decide(
    title: 'Return for revision?',
    body:
        'It goes back to the organization to change and send again, through '
        'the Moderator and Dean. The signatures already collected stay with '
        'this revision.',
    action: 'Return',
    send: _form.sdsReturn,
    done: 'Returned for revision.',
  );

  Future<void> _reject() => _decide(
    title: 'Reject this proposal?',
    body:
        'This is final. The organization is told it was rejected and cannot '
        'send this proposal again; they would start a new one. Your remarks '
        'print on the form.',
    action: 'Reject',
    send: _form.sdsReject,
    done: 'Rejected. The organization has been told.',
  );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _form,
      builder: (context, _) {
        return BrutScreen(
          header: BrutHeader(
            title: 'Review and decide',
            eyebrow: 'SDS Office',
            onBack: () => Navigator.of(context).maybePop(),
          ),
          // One back button, in the header, as on the three steps.
          footer: BrutFooter(
            child: BrutButton(
              label: 'Approve and sign',
              icon: Icons.draw_outlined,
              busy: _form.saving,
              busyLabel: 'Signing',
              onPressed:
                  _open && _cleared && _signature.isSendable && !_form.isStale
                  ? _sign
                  : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SapSdsOnlyNotice(),
              const SizedBox(height: 16),

              if (!_open)
                BrutInlineMessage(
                  tone: BrutTone.neutral,
                  icon: Icons.lock_outline,
                  text: _form.state == SapState.sdsSigned
                      ? 'This revision is signed. Return it to make changes.'
                      : 'Only a proposal waiting on the SDS Office can be '
                            'reviewed here.',
                ),
              if (!_open) const SizedBox(height: 16),

              // The remarks typed here stay put through a reload: they live
              // in this screen's fields, not in what the form reloads.
              if (_form.isStale) ...[
                const BrutInlineMessage(
                  tone: BrutTone.coral,
                  icon: Icons.sync_problem,
                  text:
                      'Someone else changed this proposal. Reload it to see '
                      'their version before deciding.',
                ),
                const SizedBox(height: 10),
                BrutButton(
                  label: 'Reload the proposal',
                  tone: BrutTone.neutral,
                  busy: _form.loading,
                  busyLabel: 'Reloading',
                  onPressed: _form.load,
                ),
                const SizedBox(height: 16),
              ],

              const BrutSectionTitle('Remarks'),
              const SizedBox(height: 10),
              BrutTextField(
                controller: _overall,
                label: 'Overall',
                hint: 'What the proposer should know',
                enabled: _open,
                maxLines: 4,
                maxLength: 3000,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              Text(
                'Against a section, if it belongs to one:',
                style: AppText.caption,
              ),
              const SizedBox(height: 10),
              for (final section in SapRemarkSection.values) ...[
                BrutTextField(
                  controller: _sections[section]!,
                  label: section.label,
                  enabled: _open,
                  maxLines: 2,
                  maxLength: 1000,
                ),
                const SizedBox(height: 10),
              ],

              const SizedBox(height: 6),
              BrutButton(
                label: 'Save remarks',
                tone: BrutTone.neutral,
                busy: _form.saving,
                busyLabel: 'Saving',
                onPressed: _open && !_form.isStale ? _saveNotes : null,
              ),

              const SizedBox(height: 24),
              const BrutSectionTitle('Return or reject'),
              const SizedBox(height: 10),
              if (_open && !_hasReason) ...[
                const BrutInlineMessage(
                  tone: BrutTone.neutral,
                  icon: Icons.info_outline,
                  text:
                      'Returning or rejecting needs an overall remark. It is '
                      'what the organization reads, and it prints on the form.',
                ),
                const SizedBox(height: 10),
              ],
              BrutButton(
                label: 'Return for revision',
                icon: Icons.undo,
                tone: BrutTone.coral,
                onPressed: _canDecide ? _return : null,
              ),
              const SizedBox(height: 10),
              BrutButton(
                label: 'Reject',
                icon: Icons.block,
                tone: BrutTone.coral,
                onPressed: _canDecide ? _reject : null,
              ),

              const SizedBox(height: 24),
              const BrutSectionTitle('Signature'),
              const SizedBox(height: 10),
              if (_open && !_cleared) ...[
                const BrutInlineMessage(
                  tone: BrutTone.sun,
                  icon: Icons.assignment_late_outlined,
                  text:
                      'Confirm Part 4 (SDS Office Clearance) before signing.',
                ),
                const SizedBox(height: 10),
              ],
              SapSignaturePad(
                enabled: _open && _cleared,
                onChanged: (s) => setState(() => _signature = s),
              ),
              const SizedBox(height: 10),
              const BrutInlineMessage(
                tone: BrutTone.neutral,
                icon: Icons.info_outline,
                text:
                    'This is the one electronic signature on the form. The '
                    'nine on paper stay paper.',
              ),
            ],
          ),
        );
      },
    );
  }
}
