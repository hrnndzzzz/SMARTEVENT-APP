import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          children: const [
            _SearchHeader(),
            SizedBox(height: 16),
            _SearchBar(query: 'Hackathon'),
            SizedBox(height: 12),
            _FilterChips(),
            SizedBox(height: 12),
            _QuickFilters(),
            SizedBox(height: 16),
            Text('Results for "Hackathon"', style: AppText.cardTitle),
            SizedBox(height: 10),
            _EventResultCard(),
            SizedBox(height: 10),
            _TransactionResultCard(),
          ],
        ),
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        Text('SmartEvent', style: AppText.wordmark),
        CircleAvatar(
          radius: 15,
          backgroundColor: AppColors.indigo,
          child: Text(
            'SO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              fontFamily: AppText.bodyFamily,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final String query;
  const _SearchBar({required this.query});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(query, style: AppText.body)),
          const Icon(Icons.close, size: 16, color: AppColors.inkMuted),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('All', selected: true),
          const SizedBox(width: 8),
          _chip('Events'),
          const SizedBox(width: 8),
          _chip('Transactions'),
        ],
      ),
    );
  }

  Widget _chip(String label, {bool selected = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.indigo : AppColors.surface,
        border: selected ? null : Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          color: selected ? Colors.white : AppColors.ink,
        ),
      ),
    );
  }
}

class _QuickFilters extends StatelessWidget {
  const _QuickFilters();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _dropdown('Quarter 1')),
        const SizedBox(width: 8),
        Expanded(child: _dropdown('All Depts')),
      ],
    );
  }

  Widget _dropdown(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppText.body.copyWith(fontSize: 12)),
          const Icon(Icons.keyboard_arrow_down, size: 15, color: AppColors.inkMuted),
        ],
      ),
    );
  }
}

class _EventResultCard extends StatelessWidget {
  const _EventResultCard();

  @override
  Widget build(BuildContext context) {
    return _ResultCardShell(
      tagColor: AppColors.sageTeal,
      icon: Icons.event_outlined,
      label: 'EVENT',
      labelColor: AppColors.sageTeal,
      timestamp: 'Oct 12 - 14',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Annual Fall Hackathon 2024', style: AppText.cardTitle),
          const SizedBox(height: 4),
          Text(
            'The premier engineering and computer science hackathon focusing on sustainable tech.',
            style: AppText.caption,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pill('Approved', bg: AppColors.sageTealTint, fg: AppColors.sageTealText),
              const SizedBox(width: 6),
              _pill('Engineering Soc.', bg: const Color(0xFFF4F2EC), fg: AppColors.inkMuted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

class _TransactionResultCard extends StatelessWidget {
  const _TransactionResultCard();

  @override
  Widget build(BuildContext context) {
    return _ResultCardShell(
      tagColor: AppColors.marigold,
      icon: Icons.receipt_long_outlined,
      label: 'TRANSACTION',
      labelColor: AppColors.marigoldText,
      timestamp: '2 hrs ago',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Catering Deposit — Hackathon', style: AppText.cardTitle),
                SizedBox(height: 4),
                Text('Vendor: Fresh Campus Catering', style: AppText.caption),
              ],
            ),
          ),
          const Text(
            '-₱2,500.00',
            style: TextStyle(
              fontFamily: AppText.monoFamily,
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: AppColors.brick,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCardShell extends StatelessWidget {
  final Color tagColor;
  final IconData icon;
  final String label;
  final Color labelColor;
  final String timestamp;
  final Widget child;

  const _ResultCardShell({
    required this.tagColor,
    required this.icon,
    required this.label,
    required this.labelColor,
    required this.timestamp,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border, width: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 13, color: labelColor),
                      const SizedBox(width: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: AppText.bodyFamily,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: labelColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    timestamp,
                    style: const TextStyle(
                      fontFamily: AppText.monoFamily,
                      fontSize: 11,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              child,
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
              color: tagColor,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }
}