import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../api/api_config.dart';

enum Reachable {
  /// Nothing has been asked of the backend yet, so nothing is known.
  ///
  /// This is where every session starts, and where the demo stays: it
  /// talks to nothing, so there is never an outcome to report. Treating
  /// it as online was a claim about a server that had not been contacted.
  unknown,

  /// The backend answered the last request. A 403 still counts: the
  /// server is there, it just said no.
  online,

  /// A request could not reach it at all.
  offline,

  /// Offline, and a quiet retry is in flight.
  reconnecting,
}

/// Whether the backend is answering.
///
/// Every value here comes from a request that actually happened — the
/// client reports the outcome of each one — rather than from the phone's
/// own idea of connectivity, which says nothing about whether a laptop
/// running the API on the other end of a USB cable is up. That matters
/// here: the usual failure is `adb reverse` dropping, where the phone has
/// perfect signal and the backend is unreachable anyway.
///
/// While offline it probes `/health` every 30 seconds so recovery shows up
/// without the user having to go and tap something. `/health` needs no
/// token, so the probe can never be the thing that logs anyone out.
class Reachability extends ChangeNotifier {
  Reachability({
    http.Client? httpClient,
    this.probeEvery = const Duration(seconds: 30),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final Duration probeEvery;

  Reachable _state = Reachable.unknown;
  DateTime? _offlineSince;
  Timer? _timer;
  bool _probing = false;
  bool _disposed = false;

  Reachable get state => _state;
  bool get isOnline => _state == Reachable.online;

  /// How long the backend has been unreachable, for the status pill.
  Duration? get offlineFor =>
      _offlineSince == null ? null : DateTime.now().difference(_offlineSince!);

  /// Called by [ApiClient] after every request.
  void report({required bool reachable}) {
    // A probe still in flight when the app closes lands here afterwards.
    if (_disposed) return;
    if (reachable) {
      _timer?.cancel();
      _timer = null;
      _offlineSince = null;
      _set(Reachable.online);
    } else {
      _offlineSince ??= DateTime.now();
      _set(Reachable.offline);
      _scheduleProbe();
    }
  }

  void _set(Reachable next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  void _scheduleProbe() {
    if (_timer != null) return;
    _timer = Timer.periodic(probeEvery, (_) => _probe());
  }

  /// Asks the backend right now, whatever the last answer was.
  ///
  /// Called each time the app opens or comes back to the front. The hosted
  /// server sleeps after 15 idle minutes, so "online" from before the app
  /// was put away says nothing, and the Welcome screen asks it nothing at
  /// all. This request is what wakes it, before anyone taps Sign in.
  Future<void> wake() => _probe(force: true);

  Future<void> _probe({bool force = false}) async {
    if (_probing || (!force && _state == Reachable.online)) return;
    _probing = true;
    // Quiet from a standing start: the app opening is not a reconnection.
    if (_state == Reachable.offline) _set(Reachable.reconnecting);
    try {
      final response = await _httpClient
          .get(Uri.parse('${ApiConfig.baseUrl}/health'))
          // A sleeping server takes about a minute to answer its first
          // request, so a shorter wait gives up on one that is starting.
          .timeout(const Duration(seconds: 90));
      // Any answer at all means it is up. The body is not this class's
      // business.
      if (response.statusCode > 0) {
        report(reachable: true);
        return;
      }
    } catch (_) {
      // Still down. Offline, and the timer keeps asking.
    } finally {
      _probing = false;
    }
    report(reachable: false);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _httpClient.close();
    super.dispose();
  }
}

extension ReachabilityOf on BuildContext {
  /// The current state, or null where nothing is watching the backend.
  ///
  /// A widget test that renders one screen has no reason to wire up
  /// connectivity, and a decoration like the presence dot must not be the
  /// thing that brings a screen down. So this answers "nobody is
  /// watching" instead of throwing, and the dot hides itself.
  Reachable? get reachable {
    try {
      return watch<Reachability>().state;
    } on ProviderNotFoundException {
      return null;
    }
  }
}
