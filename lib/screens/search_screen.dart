import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';

enum _ResultType { event, transaction }

class _SearchResult {
  final _ResultType type;
  final String title;
  final String subtitle;
  final String timestamp;
  final String? amount;
  final List<String> tags;
  final String quarter;
  final String department;

  _SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.quarter,
    required this.department,
    this.amount,
    this.tags = const [],
  });
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController(text: 'Hackathon');
  String _filter = 'All';
  String _quarter = 'All Quarters';
  String _department = 'All Depts';

  static const _quarters = ['All Quarters', 'Quarter 1', 'Quarter 2', 'Quarter 3', 'Quarter 4'];
  static const _departments = ['All Depts', 'CITHM', 'CBEA', 'CAMP', 'CASE', 'CITE'];

  final List<_SearchResult> _dataset = [
    _SearchResult(
      type: _ResultType.event,
      title: 'Annual Fall Hackathon 2024',
      subtitle: 'The premier engineering and computer science hackathon focusing on sustainable tech.',
      timestamp: 'Oct 12 - 14',
      quarter: 'Quarter 2',
      department: 'Engineering Soc.',
      tags: ['Approved', 'Engineering Soc.'],
    ),
    _SearchResult(
      type: _ResultType.transaction,
      title: 'Catering Deposit — Hackathon',
      subtitle: 'Vendor: Fresh Campus Catering',
      timestamp: '2 hrs ago',
      quarter: 'Quarter 2',
      department: 'Engineering Soc.',
      amount: '-₱2,500.00',
    ),
    _SearchResult(
      type: _ResultType.event,
      title: 'Leadership Summit 2026',
      subtitle: 'Full-day leadership training for incoming officers across CITE orgs.',
      timestamp: 'Nov 20',
      quarter: 'Quarter 2',
      department: 'CITE Student Council',
      tags: ['Under Review', 'CITE Student Council'],
    ),
    _SearchResult(
      type: _ResultType.transaction,
      title: 'Venue Rental — Auditorium',
      subtitle: 'Vendor: LCUP Facilities Office',
      timestamp: 'Yesterday',
      quarter: 'Quarter 2',
      department: 'CITE Student Council',
      amount: '-₱3,000.00',
    ),
    _SearchResult(
      type: _ResultType.event,
      title: 'CITE Sports Fest',
      subtitle: 'Intramurals across all CITE student organizations.',
      timestamp: 'Aug 5 - 7',
      quarter: 'Quarter 1',
      department: 'CITE Student Council',
      tags: ['Active', 'CITE Student Council'],
    ),
    _SearchResult(
      type: _ResultType.transaction,
      title: 'Workshop Materials Purchase',
      subtitle: 'Vendor: National Bookstore',
      timestamp: '3 days ago',
      quarter: 'Quarter 1',
      department: 'IT Society',
      amount: '-₱1,180.00',
    ),
  ];

  List<_SearchResult> get _results {
    final query = _controller.text.trim().toLowerCase();
    return _dataset.where((r) {
      final matchesType = switch (_filter) {
        'Events' => r.type == _ResultType.event,
        'Transactions' => r.type == _ResultType.transaction,
        _ => true,
      };
      final matchesQuarter = _quarter == 'All Quarters' || r.quarter == _quarter;
      final matchesDept = _department == 'All Depts' || r.department == _department;
      if (!matchesType || !matchesQuarter || !matchesDept) return false;
      if (query.isEmpty) return true;
      return r.title.toLowerCase().contains(query) || r.subtitle.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                initials: 'SO',
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AccountScreen(
                      initials: 'SO',
                      name: 'Juan Dela Cruz',
                      role: 'CITE Dept Officer',
                    ),
                  ),
                ),
                onBellTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                ),
              ),
              const SizedBox(height: 16),
              _SearchBar(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                onClear: () => setState(() => _controller.clear()),
              ),
              const SizedBox(height: 12),
              _FilterChips(
                selected: _filter,
                onSelect: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DropdownChip(
                      value: _quarter,
                      options: _quarters,
                      onSelected: (v) => setState(() => _quarter = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DropdownChip(
                      value: _department,
                      options: _departments,
                      onSelected: (v) => setState(() => _department = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _controller.text.trim().isEmpty
                    ? 'All results (${results.length})'
                    : 'Results for "${_controller.text.trim()}" (${results.length})',
                style: AppText.cardTitle,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: results.isEmpty
                    ? const _EmptyResults()
                    : ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final r in results) ...[
                      _ResultCard(result: r),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({required this.controller, required this.onChanged, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: AppText.body,
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: const Icon(Icons.close, size: 16, color: AppColors.inkMuted),
            ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _FilterChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip('All'),
          const SizedBox(width: 8),
          _chip('Events'),
          const SizedBox(width: 8),
          _chip('Transactions'),
        ],
      ),
    );
  }

  Widget _chip(String label) {
    final isSelected = selected == label;
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.indigo : AppColors.surface,
          border: isSelected ? null : Border.all(color: AppColors.border, width: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppText.bodyFamily,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            color: isSelected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

class _DropdownChip extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  const _DropdownChip({required this.value, required this.options, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final isDefault = value == options.first;
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final o in options)
          PopupMenuItem(value: o, child: Text(o, style: AppText.body.copyWith(fontSize: 13))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDefault ? AppColors.surface : AppColors.indigoLightTint,
          border: Border.all(color: AppColors.border, width: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppText.bodyFamily,
                  fontSize: 12,
                  fontWeight: isDefault ? FontWeight.w400 : FontWeight.w500,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 15, color: AppColors.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.search_off, size: 34, color: AppColors.inkFaint),
          SizedBox(height: 10),
          Text('No results found.', style: AppText.caption),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final _SearchResult result;
  const _ResultCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final isEvent = result.type == _ResultType.event;
    final tagColor = isEvent ? AppColors.sageTeal : AppColors.marigold;
    final labelColor = isEvent ? AppColors.sageTeal : AppColors.marigoldText;
    final icon = isEvent ? Icons.event_outlined : Icons.receipt_long_outlined;
    final label = isEvent ? 'EVENT' : 'TRANSACTION';

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
                    result.timestamp,
                    style: const TextStyle(
                      fontFamily: AppText.monoFamily,
                      fontSize: 11,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (isEvent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.title, style: AppText.cardTitle),
                    const SizedBox(height: 4),
                    Text(result.subtitle, style: AppText.caption),
                    if (result.tags.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (int i = 0; i < result.tags.length; i++) ...[
                            _pill(result.tags[i], i == 0),
                            if (i != result.tags.length - 1) const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ],
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(result.title, style: AppText.cardTitle),
                          const SizedBox(height: 4),
                          Text(result.subtitle, style: AppText.caption),
                        ],
                      ),
                    ),
                    Text(
                      result.amount ?? '',
                      style: const TextStyle(
                        fontFamily: AppText.monoFamily,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                        color: AppColors.brick,
                      ),
                    ),
                  ],
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
              color: tagColor,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text, bool primary) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: primary ? AppColors.sageTealTint : const Color(0xFFF4F2EC),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: primary ? AppColors.sageTealText : AppColors.inkMuted,
        ),
      ),
    );
  }
}