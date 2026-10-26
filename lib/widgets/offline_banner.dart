import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';

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
    if (app.currentAccount == null || app.isDemoMode) return child;
    final sync = app.offlineSync;
    final saved = sync.lastCompleted?.toLocal();
    final message = app.isOfflineViewing
        ? 'Offline viewing • changes unavailable'
        : sync.running
        ? 'Saving for offline viewing: ${sync.completed}/${sync.total}'
        : sync.ready
        ? 'Offline copies ready'
        : 'Offline copies incomplete';
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message, style: const TextStyle(fontSize: 12)),
                        if (saved != null)
                          Text(
                            'Last complete download: ${saved.toString().split('.').first}',
                            style: const TextStyle(fontSize: 10),
                          ),
                        if (app.offlineStorageError != null)
                          Text(
                            app.offlineStorageError!,
                            style: const TextStyle(fontSize: 10),
                          ),
                        if (app.requiresOnlineSignIn)
                          const Text(
                            'Sign in to refresh saved records.',
                            style: TextStyle(fontSize: 10),
                          ),
                        if (app.offlineSavedDates.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              final dialogContext = navigatorKey.currentContext;
                              if (dialogContext == null) return;
                              showDialog<void>(
                                context: dialogContext,
                                builder: (context) => AlertDialog(
                                  title: const Text('Saved data dates'),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Oldest saved copy opened in each area. Newer server changes may be missing.',
                                        ),
                                        const SizedBox(height: 12),
                                        for (final entry
                                            in app.offlineSavedDates.entries)
                                          Text(
                                            '${entry.key}: ${entry.value.toLocal().toString().split('.').first}',
                                          ),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Close'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: const Text('Saved data dates'),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: sync.running
                        ? null
                        : () => app.requiresOnlineSignIn
                              ? _signIn(app)
                              : app.retryOfflinePreparation(),
                    child: Text(app.requiresOnlineSignIn ? 'Sign in' : 'Retry'),
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
