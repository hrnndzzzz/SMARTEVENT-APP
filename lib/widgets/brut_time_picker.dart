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

  bool _can(int delta) {
    final next = _at + delta;
    return next >= _floor && next <= _ceiling;
  }

  /// Null when it would leave the window, which is what greys the arrow
  /// out. The end of the window is a thing to see rather than an arrow
  /// that quietly does nothing.
  VoidCallback? _move(int delta) =>
      _can(delta) ? () => setState(() => _at += delta) : null;

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
              ),
              const _Colon(),
              _Spin(
                label: 'Minutes',
                value: (_at % 60).toString().padLeft(2, '0'),
                up: _move(BrutTimePicker.minuteStep),
                down: _move(-BrutTimePicker.minuteStep),
              ),
              const SizedBox(width: AppLayout.between),
              _Spin(
                label: 'AM or PM',
                value: hour < 12 ? 'AM' : 'PM',
                // Half a day either way. Only one of the two is ever
                // available, since the window does not span enough of
                // the clock for both.
                up: _move(-720),
                down: _move(720),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.section),
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
  });

  final String label;
  final String value;
  final VoidCallback? up;
  final VoidCallback? down;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: value,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BrutIconButton(
            icon: Icons.keyboard_arrow_up,
            label: '$label up',
            size: 38,
            onPressed: up,
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
          BrutIconButton(
            icon: Icons.keyboard_arrow_down,
            label: '$label down',
            size: 38,
            onPressed: down,
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
