import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../state/reachability.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.child,
    required this.navigatorKey,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  Future<void> _signIn(AppState app) async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final password = TextEditingController();
    String? error;
    var busy = false;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Reconnect your account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(app.currentAccount?.email ?? ''),
              TextField(
                controller: password,
                obscureText: true,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              if (error != null) Text(error!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Keep viewing'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final result = await app.signIn(
                        email: app.currentAccount!.email,
                        password: password.text,
                      );
                      if (!context.mounted) return;
                      if (result == null) {
                        Navigator.pop(context);
                      } else {
                        setState(() {
                          error = result;
                          busy = false;
                        });
                      }
                    },
              child: Text(busy ? 'Signing in…' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
    password.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Being offline is said by the connection pill and the avatar dot, so
    // there is no bar for it. What nothing else covers: the server answers
    // again, but this saved session needs the password before it can save.
    final needsSignIn =
        app.currentAccount != null &&
        !app.isDemoMode &&
        app.requiresOnlineSignIn &&
        context.reachable == Reachable.online;
    if (!needsSignIn) return child;
    return Column(
      children: [
        // The app's own tone, not Material's secondaryContainer: this strip
        // sits above every screen, so a Material-3 tint would be the one
        // surface on screen that never matches the rest.
        Material(
          color: BrutTone.sun.tint(context),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Sign in again to save changes.',
                      style: AppText.caption,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _signIn(app),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
