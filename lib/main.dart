import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'state/app_settings.dart';
import 'state/app_state.dart';
import 'state/reachability.dart';
import 'widgets/connection_banner.dart';
import 'theme/app_theme.dart';
import 'theme/brut.dart';
import 'screens/welcome_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/proposal_letters_screen.dart';
import 'widgets/app_dock.dart';

void main() {
  runApp(const SmartEventApp());
}

class SmartEventApp extends StatefulWidget {
  const SmartEventApp({super.key});

  @override
  State<SmartEventApp> createState() => _SmartEventAppState();
}

class _SmartEventAppState extends State<SmartEventApp> {
  // Built here rather than inside a provider factory so AppState can be
  // handed the same instance the UI watches.
  final _reachability = Reachability();
  late final _appState = AppState(reachability: _reachability)
    // Kick off the stored-session check as soon as the state exists, so
    // the gate below has something to wait for.
    ..restoreSession();
  final _settings = AppSettings()..restore();

  @override
  void dispose() {
    _reachability.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _appState),
        // Outside AppState on purpose: signing out must not reset the
        // theme, and a dark screen turning white on log out reads as a bug.
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _reachability),
      ],
      child: Consumer2<AppState, AppSettings>(
        builder: (context, app, settings, _) => MaterialApp(
          title: 'SmartEvent',
          debugShowCheckedModeBanner: false,
          // Primary actions are blue in every department — that is the
          // one rule the palette is built on. The department shows itself
          // in the brand pill, the avatar and the active nav tab, so a
          // CITE account reads as orange and blue rather than either one
          // on its own.
          theme: AppTheme.light(accent: app.themeColor),
          darkTheme: AppTheme.dark(accent: app.themeColor),
          themeMode: settings.themeMode,
          builder: (context, child) {
            // Reduce motion is applied here rather than per widget, so it
            // reaches screen transitions and Material's own animations as
            // well as the press effect. The OS setting still wins on its
            // own; this only ever adds.
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: settings.reduceMotion
                  ? media.copyWith(disableAnimations: true)
                  : media,
              // One-hand layout, so it stays a phone-width column on a
              // tablet or a desktop window instead of stretching across it.
              child: AppColumn(child: ConnectionBanner(child: child!)),
            );
          },
          home: const _StartupGate(),
        ),
      ),
    );
  }
}

/// Decides the first screen once the stored-token check has finished:
/// straight into the app for a session that is still valid, otherwise the
/// welcome flow. Without this, a securely stored token would never be used.
class _StartupGate extends StatelessWidget {
  const _StartupGate();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.sessionChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Checked before the role, not after: an account that still owes a
    // password change has no readable profile, so its role is null even
    // though it is signed in. Testing the role first would send it back to
    // the welcome screen in a loop.
    if (app.mustSetPassword) {
      return const ChangePasswordScreen(mandatory: true);
    }

    final role = app.currentRole;
    if (role == null) return const WelcomeScreen();

    return RootShell(role: role);
  }
}

class RootShell extends StatefulWidget {
  final UserRole role;
  const RootShell({super.key, this.role = UserRole.officer});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  @override
  void initState() {
    super.initState();
    // The home grid shows a count per area, so the counts have to be
    // there before the grid is. Each of these fails independently and
    // says so on its own screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      app.loadEvents();
      app.loadExpenses();
      app.loadCatalog();
      app.loadFlaggedExpenses();
    });
  }

  @override
  Widget build(BuildContext context) {
    // SDS staff have exactly one thing to do, so they get it directly
    // rather than a directory with one card in it.
    if (widget.role.isLetterOnly) return const ProposalLettersScreen();

    return Scaffold(
      body: Stack(children: [const HomeScreen(), const AppDock()]),
    );
  }
}
