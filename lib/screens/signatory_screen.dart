import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';

/// Where an institutional signatory lands.
///
/// The role arrived with the October backend, which routes an approved
/// proposal through one to twenty signatories in order before it is
/// finally approved. This build does not implement that queue, and the
/// backend keeps signatories out of operational data entirely — so there
/// is nothing else in the app to show them.
///
/// It says so plainly rather than dropping them into a shell where every
/// screen would come back 403. The account menu still works, so they can
/// sign out from here.
class SignatoryScreen extends StatelessWidget {
  const SignatoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final name = context.watch<AppState>().currentAccount?.name;

    return BrutScreen(
      topBar: AppHeader(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          const MonoLabel('Institutional signatory'),
          const SizedBox(height: 4),
          Text(
            name == null ? 'Signed in' : 'Signed in as $name',
            style: AppText.display,
          ),
          const SizedBox(height: AppLayout.section),
          const BrutInlineMessage(
            text:
                'Institutional review is not available in this version of '
                'the app yet. Proposals routed to you for signature have '
                'to be reviewed on the web for now.',
            icon: Icons.draw_outlined,
          ),
          const SizedBox(height: AppLayout.section),
          BrutCard(
            radius: AppRadius.rowAll,
            padding: const EdgeInsets.all(AppLayout.contentPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What this role does',
                  style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppLayout.tight),
                Text(
                  'A proposal that clears the adviser and the admin is '
                  'routed to each assigned signatory in order. Yours is '
                  'the last word before it is approved.',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
