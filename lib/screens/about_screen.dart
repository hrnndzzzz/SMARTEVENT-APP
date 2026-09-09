import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeColor = context.watch<AppState>().themeColor;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: themeColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.event_note_outlined, color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SmartEvent',
                      style: TextStyle(
                        fontFamily: AppText.headerFamily,
                        fontWeight: FontWeight.w500,
                        fontSize: 20,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text('Version 1.0', style: AppText.caption),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const _SectionCard(
                title: 'About this app',
                body:
                'SmartEvent is a mobile-based inventory, financial management, event monitoring, and data analytics reporting system built for student organizations under the LCUP CITE Department.',
              ),
              const SizedBox(height: 12),
              const _SectionCard(
                title: 'Core modules',
                body:
                'User Management & Security, Financial Management, Inventory & Equipment Management, Event Monitoring, and Data Analytics & Reporting — covering the full lifecycle of student org budgeting and events.',
              ),
              const SizedBox(height: 12),
              const _SectionCard(
                title: 'Multi-department demo',
                body:
                'The Department selector in Sign Up and Edit Profile is a visual suggestion for how SmartEvent could scale campus-wide beyond CITE. Selecting a department retints the app header and navigation bar. This is a demo concept only — a real campus-wide rollout would need separate data per department.',
              ),
              const SizedBox(height: 12),
              const _SectionCard(
                title: 'Development team',
                body:
                'Built by BSIT students at La Consolacion University Philippines, College of Information Technology and Engineering (CITE), as a capstone project by Alexa',
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  '© 2026 SmartEvent · LCUP CITE Department',
                  style: AppText.caption.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.cardTitle),
            const SizedBox(height: 6),
            Text(body, style: AppText.body.copyWith(fontSize: 12, height: 1.5)),
          ],
        ),
      ),
    );
  }
}