import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_header.dart';
import 'account_screen.dart';
import 'notifications_screen.dart';
import 'event_detail_screen.dart';

enum _ResultType { event, transaction }

class _SearchResult {
  final _ResultType type;
  final String title;
  final String subtitle;
  final String timestamp;
  final String? amount;
  final String? category;
  final List<String> tags;
  final EventItem? event;

  _SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.amount,
    this.category,
    this.tags = const [],
    this.event,
  });
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _filter = 'All';
  String _category = 'All Categories';

  List<String> get _categoryOptions => ['All Categories', ...AppState.expenseCategories];

  List<_SearchResult> _buildResults(AppState app) {
    final results = <_SearchResult>[
      for (final e in app.events)
        _SearchResult(
          type: _ResultType.event,
          title: e.title,
          subtitle: '${e.org} · ${e.venue}',
          timestamp: e.date,
          tags: [e.statusLabel],
          event: e,
        ),
      for (final ex in app.expenses)
        _SearchResult(
          type: _ResultType.transaction,
          title: ex.vendor,
          subtitle: ex.category,
          timestamp: switch (ex.status) {
            ExpenseStatus.pending => 'Pending',
            ExpenseStatus.approved => 'Approved',
            ExpenseStatus.rejected => 'Rejected',
          },
          amount: '-₱${ex.amount.toStringAsFixed(2)}',
          category: ex.category,
        ),
    ];

    final query = _controller.text.trim().toLowerCase();

    return results.where((r) {
      final matchesType = switch (_filter) {
        'Events' => r.type == _ResultType.event,
        'Transactions' => r.type == _ResultType.transaction,
        _ => true,
      };
      // Category filter only narrows transactions — events don't carry
      // a category dimension in this app's data model.
      final matchesCategory = _category == 'All Categories' ||
          r.type == _ResultType.event ||
          r.category == _category;
      if (!matchesType || !matchesCategory) return false;
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                onAvatarTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
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
              _DropdownChip(
                value: _category,
                options: _categoryOptions,
                onSelected: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Consumer<AppState>(
                  builder: (context, app, _) {
                    final results = _buildResults(app);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                                _ResultCard(
                                  result: r,
                                  onTap: r.event == null
                                      ? null
                                      : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => EventDetailScreen(event: r.event!),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
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
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Search events or transactions...',
              ),
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
          mainAxisSize: MainAxisSize.min,
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
  final VoidCallback? onTap;
  const _ResultCard({required this.result, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isEvent = result.type == _ResultType.event;
    final tagColor = isEvent ? AppColors.sageTeal : AppColors.marigold;
    final labelColor = isEvent ? AppColors.sageTeal : AppColors.marigoldText;
    final icon = isEvent ? Icons.event_outlined : Icons.receipt_long_outlined;
    final label = isEvent ? 'EVENT' : 'TRANSACTION';

    return GestureDetector(
      onTap: onTap,
      child: Stack(
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
                              _pill(result.tags[i]),
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
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.sageTealTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppText.bodyFamily,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.sageTealText,
        ),
      ),
    );
  }
}