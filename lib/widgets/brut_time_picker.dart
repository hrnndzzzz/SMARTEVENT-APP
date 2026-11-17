import 'package:flutter/material.dart';

import '../api/models/sap_proposal.dart';
import '../theme/app_layout.dart';
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

  /// The minutes offered. Quarters, because a student activity is
  /// scheduled to the quarter hour and a field that offers sixty
  /// choices makes you read all of them to find the four you wanted.
  /// A time already set to something else keeps it — see [_minutes].
  static const List<int> quarters = [0, 15, 30, 45];

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

class _BrutTimePickerState extends State<BrutTimePicker> {
  late int _hour;
  late int _minute;

  @override
  void initState() {
    super.initState();
    final start = widget.initial;
    // A time outside the window is not a starting point, however it got
    // into the record — and half of one is worse than none. Clamping
    // the hour alone turned 2:30 AM into 6:30 AM, which is a time
    // nobody chose and which looks like one somebody did. Out of the
    // window opens at the start of it.
    final usable = start != null && _allows(start.hour, start.minute);
    _hour = usable ? start.hour : widget.earliest.hour;
    _minute = usable ? start.minute : widget.earliest.minute;
  }

  bool _allows(int hour, int minute) {
    final at = SapTime(hour, minute);
    return at.compareTo(widget.earliest) >= 0 &&
        at.compareTo(widget.latest) <= 0;
  }

  /// The quarters, plus whatever the record already held if it is not
  /// one of them — a time saved as 8:05 must still be shown as 8:05,
  /// not silently rounded by the thing that is supposed to display it.
  List<int> get _minutes {
    final odd = widget.initial?.minute;
    final all = {
      ...BrutTimePicker.quarters,
      if (odd != null && _hour == widget.initial!.hour) odd,
    }.toList()..sort();
    return all;
  }

  SapTime get _chosen => SapTime(_hour, _minute);

  /// `8 AM`, `12 PM`, `10 PM`.
  String _hourLabel(int hour) {
    final suffix = hour < 12 ? 'AM' : 'PM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final hours = [
      for (var h = widget.earliest.hour; h <= widget.latest.hour; h++) h,
    ];

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
          const MonoLabel('Hour'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in hours)
                IntrinsicWidth(
                  child: BrutChip(
                    label: _hourLabel(h),
                    selected: h == _hour,
                    onTap: () => setState(() {
                      _hour = h;
                      // The last hour has only its first minutes, so a
                      // minute carried into it can be one the window
                      // does not reach.
                      if (!_allows(h, _minute)) _minute = 0;
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppLayout.section),
          const MonoLabel('Minutes'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in _minutes)
                IntrinsicWidth(
                  child: BrutChip(
                    label: ':${m.toString().padLeft(2, '0')}',
                    selected: m == _minute,
                    // Shown and refused, so the end of the window is
                    // visible rather than a chip that does nothing.
                    onTap: _allows(_hour, m)
                        ? () => setState(() => _minute = m)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppLayout.between),
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
