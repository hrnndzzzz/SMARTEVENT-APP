import 'package:flutter/material.dart';
import '../state/app_update.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/brand_mark.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BrutScreen(
      header: BrutHeader(
        title: 'About',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                const BrandMark(size: 68),
                const SizedBox(height: 14),
                const Text('SmartEvent', style: AppText.titleBig),
                const SizedBox(height: 6),
                // The tag this build was made for, not a number typed
                // into the file. "Version 1.0" was written here once and
                // then stayed through every release, so the one screen
                // whose job is to say which build this is was the one
                // place guaranteed to be wrong.
                MonoLabel(AppUpdate.versionLabel()),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const _UpdateCheck(),
          const SizedBox(height: 28),
          const _SectionCard(
            title: 'About this app',
            body:
                'SmartEvent is a mobile inventory, financial '
                'management, event monitoring and reporting system '
                'for student organizations under the LCUP CITE '
                'Department.',
          ),
          const SizedBox(height: 12),
          const _SectionCard(
            title: 'Core modules',
            body:
                'User management and access control, financial '
                'management, inventory and equipment, event '
                'monitoring, and reporting — covering the lifecycle '
                'of student organization budgeting and events.',
          ),
          const SizedBox(height: 12),
          const _SectionCard(
            title: 'Separation of duties',
            body:
                'Money is recorded by one person, approved by '
                'another, and only becomes stock when someone '
                'confirms the purchase actually happened. Nobody '
                'reviews their own work — the API enforces it, and '
                'the app does not offer the control.',
          ),
          const SizedBox(height: 12),
          const _SectionCard(
            title: 'Departments',
            body:
                'The app takes its accent colour from the '
                'department your account belongs to, which is set '
                'on the roster rather than chosen here. A real '
                'campus-wide rollout would need its own data per '
                'department.',
          ),
          const SizedBox(height: 12),
          const _SectionCard(
            title: 'Development team',
            body:
                'Built by BSIT students at La Consolacion '
                'University Philippines, College of Information '
                'Technology and Engineering, as a capstone project.',
          ),
          const SizedBox(height: 22),
          const Center(
            child: MonoLabel('© 2026 SmartEvent · LCUP CITE Department'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String body;

  const _SectionCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BrutSectionTitle(title),
          const SizedBox(height: 8),
          Text(body, style: AppText.body.copyWith(fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }
}

/// Check for updates, and say what was actually found.
///
/// The app already blocks on a newer release at launch, so this is not
/// how anyone normally updates. It is here because a launch check is
/// invisible: it runs before the app is yours to look at, it stays
/// silent when there is nothing to say, and it is skipped entirely when
/// the phone is offline. Someone who wants to know now, or who was
/// offline when it mattered, has had nowhere to ask.
///
/// What it must not do is say "up to date" after failing to reach
/// GitHub. That is the one answer a person acts on by not looking
/// again.
class _UpdateCheck extends StatefulWidget {
  const _UpdateCheck();

  @override
  State<_UpdateCheck> createState() => _UpdateCheckState();
}

class _UpdateCheckState extends State<_UpdateCheck> {
  bool _busy = false;
  String? _message;
  BrutTone _tone = BrutTone.neutral;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _message = null;
    });

    final found = await AppUpdate.check();
    if (!mounted) return;

    // An available release hands straight over to the prompt that the
    // launch path uses, rather than describing the update and leaving
    // the person to find it. Same dialog, same download, same install.
    if (found.state == UpdateCheck.available) {
      setState(() => _busy = false);
      await AppUpdate.promptRequired(context, found.tag!);
      return;
    }

    final (message, tone) = switch (found.state) {
      UpdateCheck.upToDate => (
        'You have the latest release${found.tag == null ? '' : ', ${found.tag}'}.',
        BrutTone.mint,
      ),
      UpdateCheck.unreachable => (
        'Could not reach GitHub, so this is not an answer either way. '
            'Try again when you are back online.',
        BrutTone.sun,
      ),
      UpdateCheck.untagged => (
        'This build carries no release tag, so there is nothing to '
            'compare it against.',
        BrutTone.neutral,
      ),
      UpdateCheck.unsupported => (
        'Updates install from here on Android only.',
        BrutTone.neutral,
      ),
      UpdateCheck.available => ('', BrutTone.neutral),
    };

    setState(() {
      _busy = false;
      _message = message;
      _tone = tone;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutButton(
          label: 'Check for updates',
          icon: Icons.system_update,
          tone: BrutTone.neutral,
          busy: _busy,
          busyLabel: 'Checking',
          onPressed: _busy ? null : _check,
        ),
        if (_message case final message?) ...[
          const SizedBox(height: 10),
          BrutInlineMessage(
            text: message,
            tone: _tone,
            icon: switch (_tone) {
              BrutTone.mint => Icons.check_circle_outline,
              BrutTone.sun => Icons.cloud_off,
              _ => Icons.info_outline,
            },
          ),
        ],
      ],
    );
  }
}
