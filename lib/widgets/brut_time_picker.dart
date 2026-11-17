import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models/sap_proposal.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../theme/palette.dart';

/// The app's time picker: an hour and a minute, in a sheet.
///
/// Material's dial is a fine picker and the wrong one here, for the
/// same reason its calendar was — it arrives with its own radii, its
/// own ripples and its own idea of an outline, so setting a time was
/// the last moment the app stopped looking like itself.
///
/// It is also the wrong shape for the question. An activity runs
/// between [earliest] and [latest]; a dial offers all twenty-four
/// hours and midnight is one careless drag away. The window was
/// enforced *after* the dial closed, so the way to find out a time was
/// refused was to pick it. Here the hours outside it are not offered
/// at all, and a minute that would push the time past the end is shown
/// and refused — the rule before the mistake rather than after it.
class BrutTimePicker extends StatefulWidget {
  const BrutTimePicker({
    super.key,
    required this.earliest,
    required this.latest,
    this.initial,
    this.title = 'Pick a time',
    this.subtitle,
  });

  final SapTime? initial;

  /// Inclusive, both ends.
  final SapTime earliest;
  final SapTime latest;

  final String title;
  final String? subtitle;

  /// What one press of a minute arrow moves. An activity is scheduled
  /// to the quarter hour, and a stepper that moves a minute at a time
  /// needs sixty presses to cross an hour.
  static const int minuteStep = 15;

  static Future<SapTime?> show(
    BuildContext context, {
    required SapTime earliest,
    required SapTime latest,
    SapTime? initial,
    String title = 'Pick a time',
    String? subtitle,
  }) {
    return BrutSheet.show<SapTime>(
      context,
      builder: (_) => BrutTimePicker(
        earliest: earliest,
        latest: latest,
        initial: initial,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  State<BrutTimePicker> createState() => _BrutTimePickerState();
}

int _asMinutes(SapTime t) => t.hour * 60 + t.minute;

class _BrutTimePickerState extends State<BrutTimePicker> {
  /// What the last press could not do, shown until it is stale.
  ///
  /// Inside the sheet, not in a snackbar. A snackbar belongs to the
  /// Scaffold, and this sheet is drawn over the bottom of it — so the
  /// message appeared underneath the thing that provoked it and was
  /// never seen. It passed its test because the test rendered the
  /// picker on a bare Scaffold rather than in a sheet, which is the
  /// shape it never has in the app.
  String? _refused;
  Timer? _fades;

  /// Minutes since midnight. One number rather than three fields,
  /// because every arrow on this sheet is the same operation on it and
  /// the window is one comparison instead of three.
  late int _at;

  int get _floor => _asMinutes(widget.earliest);
  int get _ceiling => _asMinutes(widget.latest);

  @override
  void initState() {
    super.initState();
    final start = widget.initial;
    // A time outside the window is not a starting point, however it got
    // into the record — and half of one is worse than none. Clamping
    // the hour alone turned 2:30 AM into 6:30 AM, which is a time
    // nobody chose and which looks like one somebody did.
    final at = start == null ? null : _asMinutes(start);
    _at = (at != null && at >= _floor && at <= _ceiling) ? at : _floor;
  }

  @override
  void dispose() {
    _fades?.cancel();
    super.dispose();
  }

  bool _can(int delta) {
    final next = _at + delta;
    return next >= _floor && next <= _ceiling;
  }

  /// Every arrow stays live, and the ones that cannot move say why.
  ///
  /// They were greyed, which is the ordinary thing for a stepper at its
  /// limit and was right for five of the six. It was wrong for the
  /// half-day arrows: at 12 PM *both* of them die at once, because
  /// 12 AM is before the window and the next midnight is after it. One
  /// dead arrow reads as a limit; two read as broken, and the only
  /// explanation was a caption at the foot of the sheet.
  ///
  /// So they refuse out loud, the way Next and Send for review do. A
  /// control that cannot act and will not say why is the fault this
  /// whole screen was rebuilt to stop making.
  VoidCallback _move(int delta) => () {
    if (_can(delta)) {
      setState(() {
        _at += delta;
        _refused = null;
      });
      return;
    }
    final blocked = SapTime((_at + delta) ~/ 60 % 24, (_at + delta) % 60);
    setState(() {
      _refused =
          '${blocked.label} is outside '
          '${widget.earliest.label} – ${widget.latest.label}.';
    });
    _fades?.cancel();
    _fades = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _refused = null);
    });
  };

  /// Whether the arrow should look available. Still drawn in full ink
  /// when it is not — it is pressable, and a muted control that
  /// responds is a worse lie than a lively one that refuses.
  bool _open(int delta) => _can(delta);

  SapTime get _chosen => SapTime(_at ~/ 60, _at % 60);

  @override
  Widget build(BuildContext context) {
    final hour = _at ~/ 60;
    final shownHour = hour % 12 == 0 ? 12 : hour % 12;

    return BrutSheet(
      title: widget.title,
      subtitle: widget.subtitle,
      footer: BrutButton(
        label: 'Use ${_chosen.label}',
        size: BrutSize.large,
        onPressed: () => Navigator.of(context).pop(_chosen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Spin(
                label: 'Hour',
                value: '$shownHour',
                // An hour is sixty minutes whichever way you go, so
                // the arrows are the same operation as the others.
                up: _move(60),
                down: _move(-60),
                upOpen: _open(60),
                downOpen: _open(-60),
              ),
              const _Colon(),
              _Spin(
                label: 'Minutes',
                value: (_at % 60).toString().padLeft(2, '0'),
                up: _move(BrutTimePicker.minuteStep),
                down: _move(-BrutTimePicker.minuteStep),
                upOpen: _open(BrutTimePicker.minuteStep),
                downOpen: _open(-BrutTimePicker.minuteStep),
              ),
              const SizedBox(width: AppLayout.between),
              _Spin(
                label: 'AM or PM',
                value: hour < 12 ? 'AM' : 'PM',
                // Half a day either way. At noon neither lands inside
                // the window, which is the case that made all of these
                // speak up instead of going grey.
                up: _move(-720),
                down: _move(720),
                upOpen: _open(-720),
                downOpen: _open(720),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.section),
          // The window, and — when an arrow has just refused — what it
          // refused. In the same place, because they are the same
          // fact said twice: once standing, once because you pushed.
          if (_refused case final said?)
            BrutInlineMessage(
              tone: BrutTone.sun,
              icon: Icons.schedule,
              text: said,
            )
          else
            Center(
              child: MonoLabel(
                'Between ${widget.earliest.label} and ${widget.latest.label}',
                color: context.palette.muted,
              ),
            ),
        ],
      ),
    );
  }
}

/// One column: an arrow, a value, an arrow.
class _Spin extends StatelessWidget {
  const _Spin({
    required this.label,
    required this.value,
    required this.up,
    required this.down,
    required this.upOpen,
    required this.downOpen,
  });

  final String label;
  final String value;
  final VoidCallback up;
  final VoidCallback down;

  /// Whether pressing it moves the time. False still presses — it says
  /// what is in the way instead.
  final bool upOpen;
  final bool downOpen;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: value,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            // Dimmed, not disabled: it still answers, and the dimming
            // says the answer will be no before the press.
            opacity: upOpen ? 1 : 0.45,
            child: BrutIconButton(
              icon: Icons.keyboard_arrow_up,
              label: '$label up',
              size: 38,
              onPressed: up,
            ),
          ),
          const SizedBox(height: 6),
          BrutSurface(
            radius: AppRadius.controlAll,
            fill: context.palette.surface,
            shadow: AppShadows.none,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            alignment: Alignment.center,
            child: SizedBox(
              width: 34,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: AppText.moneyLarge.copyWith(fontSize: 20),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Opacity(
            opacity: downOpen ? 1 : 0.45,
            child: BrutIconButton(
              icon: Icons.keyboard_arrow_down,
              label: '$label down',
              size: 38,
              onPressed: down,
            ),
          ),
        ],
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(':', style: AppText.moneyLarge.copyWith(fontSize: 20)),
    );
  }
}
