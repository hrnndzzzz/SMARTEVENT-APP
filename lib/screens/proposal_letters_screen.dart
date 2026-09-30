import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

/// Proposal letters — the only module SDS Staff can reach, and a scoped
/// list for Treasurer/Adviser/Admin. Officers have no access at all.
///
/// The list itself is not wired yet: it needs `GET /proposal-letters`,
/// which exists only on the September 2026 backend. This screen says that
/// plainly rather than showing invented rows, and exists now so SDS Staff
/// has somewhere to land that isn't the finance dashboard.
class ProposalLettersScreen extends StatelessWidget {
  const ProposalLettersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppState>().currentRole;

    return Scaffold(
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
                'Proposal Letters',
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                switch (role) {
                  null => 'Not signed in.',
                  final r when r.isLetterOnly =>
                    'School-wide letters submitted for SDS review.',
                  _ => 'Letters submitted by your organization.',
                },
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
              const Expanded(child: _NotConnectedYet()),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotConnectedYet extends StatelessWidget {
  const _NotConnectedYet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 44,
            color: AppColors.inkFaint,
          ),
          const SizedBox(height: 14),
          const Text('Not connected yet', style: AppText.cardTitle),
          const SizedBox(height: 6),
          const SizedBox(
            width: 280,
            child: Text(
              'This module needs the proposal-letter endpoints, which the '
              'backend this app points at does not provide yet.',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
