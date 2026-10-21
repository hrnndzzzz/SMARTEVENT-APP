import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Points this device at a backend, and proves it before you trust it.
///
/// Development backends move: a laptop's LAN address changes with the
/// network, a hotspot hands out a different subnet, a USB cable gets
/// swapped for `adb reverse`. The address used to be fixed when the APK
/// was built, so every one of those meant a rebuild and a reinstall. This
/// card is the whole of that job now.
///
/// Testing is a real request to `/health` rather than a reachability
/// guess, because the failures worth catching here all look identical
/// from the outside: a wrong subnet, a backend that is not running, a
/// phone on a different network, a release build with no INTERNET
/// permission. The status line says which.
class BackendAddressCard extends StatefulWidget {
  const BackendAddressCard({super.key, this.httpClient});

  /// Injected by tests so they can answer without a socket.
  final http.Client? httpClient;

  @override
  State<BackendAddressCard> createState() => _BackendAddressCardState();
}

enum _Probe { idle, running, reachable, unreachable }

class _BackendAddressCardState extends State<BackendAddressCard> {
  late final TextEditingController _controller = TextEditingController(
    text: ApiConfig.baseUrl,
  );
  late final http.Client _client = widget.httpClient ?? http.Client();

  _Probe _probe = _Probe.idle;
  String? _probeDetail;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    if (widget.httpClient == null) _client.close();
    super.dispose();
  }

  /// Saves first, then probes, so the status line always describes the
  /// address the app is actually using rather than the one in the box.
  Future<void> _applyAndTest() async {
    setState(() {
      _saving = true;
      _error = null;
      _probe = _Probe.running;
      _probeDetail = null;
    });

    try {
      await ApiConfig.setOverride(_controller.text);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _probe = _Probe.idle;
        _error = e.message;
      });
      return;
    }

    final target = ApiConfig.baseUrl;
    if (mounted) {
      setState(() {
        _saving = false;
        _controller.text = target;
      });
    }

    String? detail;
    var reachable = false;
    try {
      final response = await _client
          .get(Uri.parse('$target/health'))
          .timeout(const Duration(seconds: 8));
      // Any answer at all means the address is right and something is
      // listening. A 404 still tells us that much, so it is not a failure
      // of the address — it is a backend without a /health route.
      reachable = true;
      detail = response.statusCode == 200
          ? 'The backend answered.'
          : 'Something answered with ${response.statusCode}. The address '
                'is reachable.';
    } on TimeoutException {
      detail =
          'Nothing answered within 8 seconds. The backend may be starting, '
          'or a firewall is dropping the connection.';
    } catch (_) {
      detail =
          'Could not connect. Check the backend is running, and that this '
          'phone is on the same network as it.';
    }

    if (!mounted) return;
    setState(() {
      _probe = reachable ? _Probe.reachable : _Probe.unreachable;
      _probeDetail = detail;
    });
  }

  Future<void> _useDefault() async {
    await ApiConfig.clearOverride();
    if (!mounted) return;
    setState(() {
      _controller.text = ApiConfig.baseUrl;
      _error = null;
      _probe = _Probe.idle;
      _probeDetail = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrutTextField(
            controller: _controller,
            label: 'Address',
            hint: '192.168.1.5:8000',
            errorText: _error,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _applyAndTest(),
          ),
          const SizedBox(height: 6),
          Text(
            ApiConfig.hasOverride
                ? 'Set on this device. The build itself points at '
                      '${ApiConfig.defaultBaseUrl}.'
                : 'This is the address the app was built with.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          BrutButton(
            label: 'Save and test',
            icon: Icons.wifi_tethering,
            busy: _saving || _probe == _Probe.running,
            busyLabel: _saving ? 'Saving' : 'Testing',
            onPressed: _applyAndTest,
          ),
          if (ApiConfig.hasOverride) ...[
            const SizedBox(height: 8),
            BrutButton(
              label: 'Use the build\'s address',
              tone: BrutTone.neutral,
              size: BrutSize.small,
              onPressed: _useDefault,
            ),
          ],
          if (_probe == _Probe.reachable || _probe == _Probe.unreachable) ...[
            const SizedBox(height: 12),
            BrutInlineMessage(
              tone: _probe == _Probe.reachable
                  ? BrutTone.mint
                  : BrutTone.coral,
              icon: _probe == _Probe.reachable
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              text: _probeDetail ?? '',
            ),
          ],
        ],
      ),
    );
  }
}
