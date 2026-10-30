import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'state/app_settings.dart';
import 'state/avatar.dart';
import 'state/app_state.dart';
import 'state/reachability.dart';
import 'widgets/connection_banner.dart';
import 'widgets/offline_banner.dart';
import 'theme/app_theme.dart';
import 'theme/brut.dart';
import 'screens/welcome_screen.dart';
import 'screens/change_password_screen.dart';
import 'screens/home_screen.dart';
import 'api/api_config.dart';
import 'state/notice_shelf.dart';
import 'state/sfx.dart';
import 'screens/proposal_letters_screen.dart';
import 'screens/signatory_screen.dart';
import 'screens/events_hub_screen.dart';
import 'screens/menu_panel.dart';
import 'theme/app_layout.dart';
import 'widgets/page_indicator.dart';
import 'widgets/record_button.dart';

void main() async {
  // Portrait only. Every screen is laid out as one column at phone
  // width — the keypad, the month grid, the three-band hub — and none of
  // them has a landscape arrangement worth turning the phone for.
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Before the first request, so a device pointed at its own backend
  // address never fires one at the build's address first.
  await ApiConfig.load();
  runApp(const SmartEventApp());
}

class SmartEventApp extends StatefulWidget {
  const SmartEventApp({super.key});

  @override
  State<SmartEventApp> createState() => _SmartEventAppState();
}

class _SmartEventAppState extends State<SmartEventApp>
    with WidgetsBindingObserver {
  // Built here rather than inside a provider factory so AppState can be
  // handed the same instance the UI watches.
  final _reachability = Reachability();
  var _navigatorKey = GlobalKey<NavigatorState>();
  int _navigationGeneration = -1;
  GlobalKey<NavigatorState> _navigatorFor(AppState app) {
    if (_navigationGeneration != app.navigationGeneration) {
      _navigationGeneration = app.navigationGeneration;
      _navigatorKey = GlobalKey<NavigatorState>();
    }
    return _navigatorKey;
  }

  late final AppState _appState = AppState(reachability: _reachability)
    // Kick off the stored-session check as soon as the state exists, so
    // the gate below has something to wait for.
    ..restoreSession().then((_) => _appState.offlineSync.prepare());
  final _settings = AppSettings()..restore();
  final _avatar = Avatar()..load();
  final _sfx = SfxPlayer()..load();
  final _shelf = NoticeShelf();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appState.offlineSync.foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _appState.retryOfflinePreparation();
    } else {
      _appState.offlineSync.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _appState.dispose();
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
        ChangeNotifierProvider.value(value: _avatar),
        ChangeNotifierProvider.value(value: _sfx),
        ChangeNotifierProvider.value(value: _shelf),
      ],
      child: Consumer2<AppState, AppSettings>(
        builder: (context, app, settings, _) => MaterialApp(
          title: 'SmartEvent',
          navigatorKey: _navigatorFor(app),
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
              child: AppColumn(
                child: OfflineBanner(
                  navigatorKey: _navigatorKey,
                  child: ConnectionBanner(child: child!),
                ),
              ),
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
      return const Scaffold(body: Center(child: BrutSpinner()));
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

/// Three screens side by side: the menu, the dashboard, events.
///
/// The dashboard is the one you land on, and the other two are a thumb
/// flick away in either direction. There is no bar and no floating
/// button, because a swipe between three screens does not need a map of
/// itself drawn on top of it.
class _RootShellState extends State<RootShell> {
  static const _dashboardPage = 1;
  final _pages = PageController(initialPage: _dashboardPage);
  int _page = _dashboardPage;

  @override
  void initState() {
    super.initState();
    // Every panel shows a count, so the counts have to arrive before the
    // panels do. Each of these fails independently and says so on its
    // own screen.
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
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _toDashboard() => _pages.animateToPage(
    _dashboardPage,
    duration: AppMotion.sheet,
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    // SDS staff have exactly one thing to do, so they get it directly
    // rather than three screens, two of which would be empty.
    if (widget.role.isLetterOnly) return const ProposalLettersScreen();
    // Signatories are kept out of operational data by the backend, so
    // the three-page shell would be three empty screens.
    if (widget.role.isInstitutionalReviewer) return const SignatoryScreen();

    return PopScope(
      // Back returns to the dashboard before it leaves the app, the same
      // way it closes a sheet first.
      canPop: _page == _dashboardPage,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toDashboard();
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  MenuPanel(onClose: _toDashboard),
                  const HomeScreen(),
                  const EventsHubScreen(),
                ],
              ),
            ),
            // The record button is docked to the bar rather than floating
            // over the dashboard. Floating, it covered the allocated and
            // spent figures whenever the screen sat at rest; here it
            // overlaps the navigation it rises out of and nothing that
            // carries a number. Only on the dashboard, and only for
            // whoever may record money.
            // Its own band between the content and the bar, so it
            // overlaps neither. Floating, it covered the allocated and
            // spent figures; docked into the bar, it punched through the
            // bar's own edge. The band costs the dashboard about eighty
            // pixels and collides with nothing.
            if (_page == 1 && context.watch<AppState>().mayRecordFinance)
              const Padding(
                // The same gutter every card above it uses, so it sits
                // on the grid rather than running edge to edge.
                padding: EdgeInsets.fromLTRB(
                  AppLayout.gutter,
                  8,
                  AppLayout.gutter,
                  0,
                ),
                child: RecordButton(),
              ),
            PageIndicator(
              current: _page,
              labels: const ['Menu', 'Dashboard', 'Events'],
              onGo: (i) => _pages.animateToPage(
                i,
                duration: AppMotion.sheet,
                curve: Curves.easeOutCubic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
