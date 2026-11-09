import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// Between a stored session and the person holding the phone.
///
/// Shown only when there is something to protect: a session is saved
/// and the account asked that it not be opened without them. A refused
/// or cancelled prompt lands here rather than signing anyone out, so a
/// wet finger costs a second attempt and not the session.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _busy = false;

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    await context.read<AppState>().unlock();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signOut() async {
    final app = context.read<AppState>();
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Use your password instead?'),
        content: const Text(
          'This signs you out on this phone. You can sign back in with '
          'your email and password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay here'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (leave == true) await app.cancelUnlock();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = context.watch<AppState>().currentAccount?.name;

    return BrutScreen(
      scrollable: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.brandTint,
                shape: BoxShape.circle,
                border: Border.all(color: p.ink, width: 2),
              ),
              child: Icon(Icons.fingerprint, size: 38, color: p.ink),
            ),
          ),
          const SizedBox(height: AppLayout.section),
          Text('Locked', textAlign: TextAlign.center, style: AppText.display),
          const SizedBox(height: 6),
          Text(
            name == null
                ? 'Unlock to open your session on this phone.'
                : 'Unlock to open $name’s session on this phone.',
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(color: p.muted),
          ),
          const SizedBox(height: AppLayout.section),
          BrutButton(
            label: 'Unlock',
            icon: Icons.lock_open,
            busy: _busy,
            busyLabel: 'Waiting',
            onPressed: _busy ? null : _unlock,
          ),
          const SizedBox(height: AppLayout.between),
          BrutButton(
            label: 'Use my password instead',
            icon: Icons.password,
            tone: BrutTone.neutral,
            onPressed: _busy ? null : _signOut,
          ),
        ],
      ),
    );
  }
}
