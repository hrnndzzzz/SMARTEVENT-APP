import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps a screen out of screenshots, screen recordings and the
/// recents thumbnail.
///
/// ## What this is for
///
/// Most of the app is fine to photograph — a dashboard, a stock list,
/// a chart. A few screens are not, and they are the ones carrying
/// other people's details rather than figures:
///
/// * the roster and Accounts — real students' names and institutional
///   email addresses, the worst thing here to leak;
/// * the signature pad and a signed SAP form — a captured signature is
///   reusable, which makes it the closest thing to a credential;
/// * a receipt — vendor, amount, sometimes a card tail and who paid;
/// * the audit log — who did what, by name;
/// * the one-time code screen;
/// * an expense's remarks, which are free text about people.
///
/// ## Why it is a counter and not a switch
///
/// Android's FLAG_SECURE is a property of the window, and Flutter has
/// one window, so it is on for the whole app or off for all of it.
/// Screens push on top of each other, so turning it off in a dispose
/// would unprotect a screen still underneath. Each guarded screen
/// holds a claim; the flag clears when the last one lets go.
///
/// ## Why the demo is exempt
///
/// FLAG_SECURE blocks screen recording too. The defence demo is
/// recorded in demo mode, on seeded records that belong to nobody, so
/// protecting them protects no one and would only lose the recording.
/// [exempt] is set once at startup from the demo flag.
class ScreenPrivacy {
  ScreenPrivacy._();

  @visibleForTesting
  static const channel = MethodChannel('smartevent/secure');

  /// Set while the app is running on seeded demo records, where there
  /// is nobody to protect and a blocked recording is a real cost.
  static bool exempt = false;

  /// How many screens are asking for it right now.
  static int _claims = 0;

  @visibleForTesting
  static int get claims => _claims;

  @visibleForTesting
  static void reset() {
    _claims = 0;
  }

  /// Whether the platform can do this at all. iOS has no equivalent of
  /// FLAG_SECURE, so the call is simply not made there.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> _tell(bool on) async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('set', on);
    } on PlatformException {
      // An older build of the app shell has no such channel. Failing
      // to protect a screen must never stop it opening.
    } on MissingPluginException {
      // Same, in a test host or a platform without the channel.
    }
  }

  static Future<void> claim() async {
    if (exempt) return;
    _claims++;
    if (_claims == 1) await _tell(true);
  }

  static Future<void> release() async {
    if (exempt) return;
    if (_claims == 0) return;
    _claims--;
    if (_claims == 0) await _tell(false);
  }
}

/// Wraps a screen whose contents must not be photographed.
///
/// Claims on the way in and releases on the way out, so a stack of
/// guarded screens stays protected until the last one closes.
class PrivateScreen extends StatefulWidget {
  const PrivateScreen({super.key, required this.child});

  final Widget child;

  @override
  State<PrivateScreen> createState() => _PrivateScreenState();
}

class _PrivateScreenState extends State<PrivateScreen> {
  @override
  void initState() {
    super.initState();
    ScreenPrivacy.claim();
  }

  @override
  void dispose() {
    ScreenPrivacy.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
