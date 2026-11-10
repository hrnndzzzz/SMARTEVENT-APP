import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'apk_file.dart';

/// What a manual check found. See [AppUpdate.check].
enum UpdateCheck {
  /// A later release exists, and its tag came back with this.
  available,

  /// GitHub answered, and this build is the latest.
  upToDate,

  /// GitHub did not answer, or answered something unreadable. Not the
  /// same as being up to date, and must never be reported as it.
  unreachable,

  /// This build carries no release tag — a `flutter run`, or a build
  /// made without --dart-define=SMARTEVENT_RELEASE_TAG. There is
  /// nothing to compare against, so no answer is possible.
  untagged,

  /// Not Android. Nothing here can install anything anywhere else.
  unsupported,
}

/// Keeps the installed app on the latest GitHub release.
///
/// An app installed from a download cannot replace itself silently: Android
/// always shows its own install screen. So this finds a newer release,
/// downloads it, and opens that screen, and until then the app is blocked.
class AppUpdate {
  const AppUpdate._();

  /// The release this build was made for, such as `v1.0.4`, set with
  /// `--dart-define=SMARTEVENT_RELEASE_TAG=v1.0.4`. It must match the tag
  /// of the GitHub release the APK is attached to. A build without it (any
  /// `flutter run`) never checks.
  static const currentTag = String.fromEnvironment('SMARTEVENT_RELEASE_TAG');

  /// How a build names itself on the About screen.
  ///
  /// A separate function because [currentTag] is a compile-time
  /// constant: a widget test cannot set it, so the tagged case would
  /// otherwise go untested — which is how "Version 1.0" sat in About
  /// through seven releases without anyone noticing.
  /// The leading `v` is dropped because the label already says
  /// "Version", and the screen uppercases it: the tag as written gave
  /// "VERSION V1.0.7".
  static String versionLabel([String tag = currentTag]) => tag.isEmpty
      ? 'Development build'
      : 'Version ${tag.startsWith('v') ? tag.substring(1) : tag}';

  static const _repo = 'https://github.com/hrnndzzzz/SMARTEVENT-APP';
  static const _channel = MethodChannel('smartevent/update');

  /// The tag of a release newer than [current], or null when this build is
  /// up to date, is a dev build, or GitHub could not be reached. Offline is
  /// never a reason to block the app.
  static Future<String?> newerRelease({
    String current = currentTag,
    http.Client? client,
  }) async {
    final found = await check(current: current, client: client);
    return found.state == UpdateCheck.available ? found.tag : null;
  }

  /// The same question, with the answers kept apart.
  ///
  /// [newerRelease] collapses "up to date", "cannot check" and "did not
  /// reach GitHub" into null, which is right at launch: nobody asked, and
  /// a bad connection must never block the app. It is wrong for a button.
  /// Someone who pressed Check for updates and is told they are up to
  /// date has been told something nobody verified, and will go on
  /// believing it. So the manual path gets the difference.
  static Future<({UpdateCheck state, String? tag})> check({
    String current = currentTag,
    http.Client? client,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return (state: UpdateCheck.unsupported, tag: null);
    }
    if (current.isEmpty) {
      return (state: UpdateCheck.untagged, tag: null);
    }
    final c = client ?? http.Client();
    try {
      // The page's redirect, not api.github.com: the API allows 60
      // anonymous calls an hour per IP, and a campus network is one IP.
      final request = http.Request('GET', Uri.parse('$_repo/releases/latest'))
        ..followRedirects = false;
      final response = await c
          .send(request)
          .timeout(const Duration(seconds: 10));
      final latest = tagFromLocation(response.headers['location']);
      if (latest == null) return (state: UpdateCheck.unreachable, tag: null);
      return isNewer(latest, current)
          ? (state: UpdateCheck.available, tag: latest)
          : (state: UpdateCheck.upToDate, tag: latest);
    } catch (_) {
      return (state: UpdateCheck.unreachable, tag: null);
    } finally {
      if (client == null) c.close();
    }
  }

  /// `v1.0.4` from `…/releases/tag/v1.0.4`.
  static String? tagFromLocation(String? location) =>
      RegExp(r'/releases/tag/([^/?#]+)$').firstMatch(location ?? '')?.group(1);

  /// Whether [latest] is a later `vX.Y.Z` than [current]. Anything that is
  /// not three numbers is never newer, so a mistyped tag cannot lock every
  /// phone behind an update it can never satisfy.
  static bool isNewer(String latest, String current) {
    final a = _numbers(latest);
    final b = _numbers(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int>? _numbers(String tag) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(tag.trim());
    return match == null
        ? null
        : [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
  }

  /// Downloads the release's APK and returns where it was saved.
  static Future<String> download(
    String tag,
    void Function(double progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final response = await client
          .send(
            http.Request(
              'GET',
              Uri.parse(
                '$_repo/releases/download/$tag/SMARTEVENT-arm64-v8a.apk',
              ),
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw http.ClientException('GitHub answered ${response.statusCode}');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      return await saveApk(
        response.stream
            // A connection that stalls mid-file fails rather than hangs.
            .timeout(const Duration(seconds: 30))
            .map((chunk) {
              received += chunk.length;
              if (total > 0) onProgress(received / total);
              return chunk;
            }),
      );
    } finally {
      client.close();
    }
  }

  /// Opens Android's install screen for the APK at [path]. See
  /// `MainActivity.kt`.
  static Future<void> install(String path) =>
      _channel.invokeMethod('install', path);

  /// The blocking prompt. It cannot be dismissed: the only way past it is
  /// the update.
  static Future<void> promptRequired(BuildContext context, String tag) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RequiredUpdate(tag: tag),
      );
}

class _RequiredUpdate extends StatefulWidget {
  const _RequiredUpdate({required this.tag});

  final String tag;

  @override
  State<_RequiredUpdate> createState() => _RequiredUpdateState();
}

class _RequiredUpdateState extends State<_RequiredUpdate> {
  bool _busy = false;
  double? _progress;
  String? _error;

  /// Kept so backing out of Android's install screen does not mean
  /// downloading the whole file again.
  String? _apk;

  Future<void> _update() async {
    setState(() {
      _busy = true;
      _progress = null;
      _error = null;
    });
    try {
      _apk ??= await AppUpdate.download(widget.tag, (progress) {
        if (mounted) setState(() => _progress = progress);
      });
      await AppUpdate.install(_apk!);
    } catch (_) {
      _error = _apk == null
          ? 'The download did not finish. Check your connection and try again.'
          : 'The installer did not open. Try again.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Update required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SMARTEVENT ${widget.tag} is out. Install it to keep using '
              'the app.',
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
            ],
            if (_error != null) ...[const SizedBox(height: 12), Text(_error!)],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _update,
            child: Text(_apk == null ? 'Update' : 'Install'),
          ),
        ],
      ),
    );
  }
}
