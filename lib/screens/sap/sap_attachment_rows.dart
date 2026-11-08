import 'package:flutter/material.dart';

import '../../api/export_saver.dart';
import '../../state/sap_form.dart';
import '../../theme/brut.dart';

/// The proposal's supporting files, one named row each; a tap opens it.
///
/// Every attachment used to read "Open supporting file", so three of them
/// gave three identical buttons and no way to tell the ROC/COC from an
/// appendix. Shared by the proposer's hub and the SDS Office's summary.
class SapAttachmentRows extends StatelessWidget {
  const SapAttachmentRows({super.key, required this.form});

  final SapForm form;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in form.attachments) ...[
          BrutListRow(
            title: attachment.category?.label ?? 'Supporting file',
            meta: attachment.filename,
            marker: const BrutIconTile(
              size: 32,
              icon: Icons.attach_file,
              tone: BrutTone.brand,
            ),
            onTap: () async {
              try {
                await ExportSaver.share(
                  await form.attachmentFile(attachment.id),
                  subject: 'Proposal attachment',
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$error')));
              }
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
