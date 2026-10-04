import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AppState>().themeColor;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            BrutHeader(
              title: 'About',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          BrutSurface(
                            fill: themeColor,
                            radius: AppRadius.cardAll,
                            width: 68,
                            height: 68,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.event_note_outlined,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text('SmartEvent', style: AppText.titleBig),
                          const SizedBox(height: 6),
                          const MonoLabel('Version 1.0'),
                        ],
                      ),
                    ),
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
                      child: MonoLabel(
                        '© 2026 SmartEvent · LCUP CITE Department',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
