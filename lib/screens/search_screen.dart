import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
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

  List<String> get _categoryOptions => [
    'All Categories',
    ...context.read<AppState>().expenseCategories,
  ];
  List<_SearchResult> _buildResults(AppState app) {
    final results = <_SearchResult>[
      for (final e in app.events)
        _SearchResult(
          type: _ResultType.event,
          title: e.title,
          // Organization plus academic period — both real fields, unlike
          // the venue this used to show, which never round-tripped.
          subtitle: [if (e.org.isNotEmpty) e.org, e.academicLabel].join(' · '),
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
      final matchesCategory =
          _category == 'All Categories' ||
          r.type == _ResultType.event ||
          r.category == _category;
      if (!matchesType || !matchesCategory) return false;
      if (query.isEmpty) return true;
      return r.title.toLowerCase().contains(query) ||
          r.subtitle.toLowerCase().contains(query);
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
                  MaterialPageRoute(
                    builder: (_) => const NotificationsScreen(),
                  ),
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
                        BrutSectionTitle(
                          _controller.text.trim().isEmpty
                              ? 'All results'
                              : 'Results for "${_controller.text.trim()}"',
                          aside: MonoLabel('${results.length} found'),
                        ),
                        const SizedBox(height: 12),
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
                                                  builder: (_) =>
                                                      EventDetailScreen(
                                                        event: r.event!,
                                                      ),
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

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return BrutTextField(
      controller: controller,
      onChanged: onChanged,
      hint: 'Search events or transactions…',
      prefixIcon: Icons.search,
      suffix: controller.text.isEmpty
          ? null
          : IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close, size: 18),
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
    return BrutChipBar(
      children: [
        for (final label in const ['All', 'Events', 'Transactions'])
          BrutChip(
            label: label,
            selected: selected == label,
            onTap: () => onSelect(label),
          ),
      ],
    );
  }
}

class _DropdownChip extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;

  const _DropdownChip({
    required this.value,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDefault = value == options.first;

    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final o in options) PopupMenuItem(value: o, child: Text(o)),
        ],
        child: BrutSurface(
          fill: isDefault
              ? AppColors.surface
              : Theme.of(context).colorScheme.primary,
          radius: AppRadius.controlAll,
          shadow: isDefault ? AppShadows.none : AppShadows.sm,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.buttonLabel.copyWith(
                    fontSize: 12,
                    color: isDefault ? AppColors.subtle : AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: BrutEmptyState(
        icon: Icons.search_off,
        title: 'No results',
        hint: 'Try a shorter search, or clear the filters.',
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
    final tone = isEvent ? BrutTone.mint : BrutTone.sun;

    return BrutCard(
      onTap: onTap,
      radius: AppRadius.rowAll,
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The kind of record as a stripe, so a mixed list can be read by
          // colour before it is read by word.
          Container(
            width: 8,
            decoration: BoxDecoration(
              color: tone.fill(context),
              border: const Border(right: AppBorders.side),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppRadius.row - AppBorders.width),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      BrutBadge(
                        label: isEvent ? 'Event' : 'Transaction',
                        tone: tone,
                        mono: true,
                      ),
                      const Spacer(),
                      Text(result.timestamp, style: AppText.moneySmall),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(result.title, style: AppText.cardTitle),
                            const SizedBox(height: 3),
                            Text(result.subtitle, style: AppText.caption),
                          ],
                        ),
                      ),
                      if (!isEvent && result.amount != null) ...[
                        const SizedBox(width: 10),
                        Text(
                          result.amount!,
                          style: AppText.moneyLarge.copyWith(fontSize: 15),
                        ),
                      ],
                    ],
                  ),
                  if (isEvent && result.tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in result.tags)
                          BrutBadge(label: tag, tone: BrutTone.mint),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
