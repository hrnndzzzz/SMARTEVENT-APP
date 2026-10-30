import 'package:flutter/material.dart';

import '../screens/scanner_screen.dart';
import '../theme/brut.dart';

/// Record an expense: the one thing the dashboard is for doing rather
/// than reading.
///
/// It is a full-width action in a band of its own, between the dashboard
/// and the navigation bar, overlapping neither.
///
/// It was a circle, and went through three positions before this one.
/// Floating over the dashboard it covered the allocated and spent
/// figures whenever the screen sat at rest, and padding could not fix
/// that: a button floating over a scrolling list covers whatever is
/// under it, and the bottom padding only clears the last card at full
/// scroll. Docked into the navigation bar it punched through the bar's
/// own edge. Given a band to itself it collided with nothing but left
/// most of a full-width strip empty, which reads as a gap in the layout
/// rather than a deliberate space. Filling that strip is what it is
/// for, so it says what it does as well.
class RecordButton extends StatelessWidget {
  const RecordButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BrutButton(
      label: 'Record an expense',
      icon: Icons.document_scanner_outlined,
      tone: BrutTone.orange,
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ScannerScreen())),
    );
  }
}
