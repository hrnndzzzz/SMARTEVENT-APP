import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../main.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const List<_InfoBlurb> _blurbs = [
    _InfoBlurb(
      icon: Icons.notifications_outlined,
      iconBg: AppColors.marigoldTint,
      iconColor: AppColors.marigoldText,
      title: 'Smart Alerts',
      body: 'Get notified on low-stock items, pending approvals, and upcoming event deadlines.',
    ),
    _InfoBlurb(
      icon: Icons.receipt_long_outlined,
      iconBg: AppColors.sageTealTint,
      iconColor: AppColors.sageTealText,
      title: 'Financial Tracking',
      body: 'Log expenses, monitor budgets, and generate liquidation reports in one place.',
    ),
    _InfoBlurb(
      icon: Icons.inventory_2_outlined,
      iconBg: Color(0xFFE8ECF3),
      iconColor: AppColors.indigo,
      title: 'Inventory Management',
      body: 'Track equipment and supplies across every event without a spreadsheet in sight.',
    ),
  ];

  int _index = 0;
  Timer? _timer;
  UserRole _role = UserRole.officer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      setState(() => _index = (_index + 1) % _blurbs.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _enterApp() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RootShell(role: _role)),
    );
  }

  String get _roleLabel {
    switch (_role) {
      case UserRole.officer:
        return 'Officer';
      case UserRole.adviser:
        return 'Adviser';
      case UserRole.admin:
        return 'Admin';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('SmartEvent', style: AppText.wordmark),
                  TextButton(
                    onPressed: _enterApp,
                    child: const Text(
                      'Log In',
                      style: TextStyle(
                        fontFamily: AppText.bodyFamily,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        color: AppColors.indigo,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _HeroBanner(),
              const SizedBox(height: 20),
              const Text(
                'Student orgs,\norganized.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 26,
                  height: 1.25,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Track inventory, finances, and events for your CITE student organization — all in one place.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: AppText.bodyFamily, fontSize: 13, color: AppColors.inkMuted, height: 1.5),
              ),
              const Spacer(),
              SizedBox(
                height: 108,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                  child: _BlurbCard(key: ValueKey(_index), blurb: _blurbs[_index]),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_blurbs.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active ? AppColors.indigo : AppColors.border,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 22),
              const Text('Continue as', style: AppText.caption, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _RoleChip(role: UserRole.officer, label: 'Officer', icon: Icons.person_outline, selected: _role == UserRole.officer, onTap: () => setState(() => _role = UserRole.officer))),
                  const SizedBox(width: 8),
                  Expanded(child: _RoleChip(role: UserRole.adviser, label: 'Adviser', icon: Icons.fact_check_outlined, selected: _role == UserRole.adviser, onTap: () => setState(() => _role = UserRole.adviser))),
                  const SizedBox(width: 8),
                  Expanded(child: _RoleChip(role: UserRole.admin, label: 'Admin', icon: Icons.admin_panel_settings_outlined, selected: _role == UserRole.admin, onTap: () => setState(() => _role = UserRole.admin))),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _enterApp,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: Text('Continue as $_roleLabel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final UserRole role;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleChip({
    required this.role,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.indigo : AppColors.surface,
          border: selected ? null : Border.all(color: AppColors.border, width: 0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : AppColors.inkMuted),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppText.bodyFamily,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 130,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.indigo, AppColors.sageTeal],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.groups_outlined, color: Colors.white, size: 24),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: _pill(Icons.receipt_outlined, '₱2,850.00'),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              child: _pill(Icons.calendar_today_outlined, '3 events this week'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.white)),
        ],
      ),
    );
  }
}

class _InfoBlurb {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String body;
  const _InfoBlurb({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.body,
  });
}

class _BlurbCard extends StatelessWidget {
  final _InfoBlurb blurb;
  const _BlurbCard({super.key, required this.blurb});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border, width: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: blurb.iconBg, borderRadius: BorderRadius.circular(9)),
                child: Icon(blurb.icon, size: 17, color: blurb.iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(blurb.title, style: AppText.cardTitle),
                    const SizedBox(height: 4),
                    Text(blurb.body, style: AppText.caption.copyWith(height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          top: 12,
          bottom: 12,
          child: Container(
            width: 4,
            decoration: BoxDecoration(
              color: blurb.iconColor,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }
}