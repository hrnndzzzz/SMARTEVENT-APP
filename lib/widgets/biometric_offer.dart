import 'package:flutter/material.dart';

import '../api/biometric_lock.dart';

/// The offer, made once, at the one moment it is obviously worth
/// something: just after a password has been typed in full.
///
/// The switch for this has always been in Settings, four sections down
/// under "This device", which is why it was never on. Asking here is
/// not nagging — a no is remembered and never asked again, and the
/// switch stays where it was for a change of mind.
///
/// Returns true only when it ended up on, which means the device
/// actually passed the confirming prompt. [BiometricLock.setEnabled]
/// asks for the finger before storing the preference, so a switch can
/// never be left on for a check the owner cannot pass.
Future<bool> offerBiometricLogin(
  BuildContext context,
  BiometricLock lock,
) async {
  if (!await lock.shouldOffer) return false;
  final kind = await lock.kind;
  if (!context.mounted) return false;

  // Null when the platform will not say which modality is enrolled,
  // which on Android is most of the time. See BiometricLock.kind.
  final noun = kind ?? 'fingerprint or face';

  final yes = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Use your $noun next time?'),
      content: Text(
        'SmartEvent can ask for your $noun instead of your password '
        'when you come back to it on this phone.\n\n'
        'The check is done by Android against the $noun already on the '
        'phone. SmartEvent never sees or stores it, and nothing about '
        'it leaves the device.\n\n'
        'Your password still works whenever you want it, and this '
        'applies to this phone only. We will not ask again — the switch '
        'is in Settings under "This device".',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep my password'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('Use my $noun'),
        ),
      ],
    ),
  );

  if (yes != true) {
    await lock.declineOffer();
    return false;
  }
  return lock.setEnabled(true);
}
