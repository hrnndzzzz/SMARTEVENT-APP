import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_areas.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_layout.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';
import '../widgets/app_header.dart';
import 'events_screen.dart';
import 'expenses_screen.dart';
import 'notifications_screen.dart';
import 'scanner_screen.dart';
import '../theme/peso.dart';

/// The dashboard: where you stand, what needs you, and the one thing you
/// are most likely to have opened the app to do.
///
/// It carries four figures and nothing else. The charts and the review
/// queues are a tap away at the bottom, because someone who wants to
/// study a chart goes looking for it, and someone opening the app at a
/// supplier's counter does not.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  static String _greeting(int hour) => switch (hour) {
    < 12 => 'Good morning',
    < 18 => 'Good afternoon',
    _ => 'Good evening',
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = DateTime.now();
    final name = app.currentAccount?.name.split(' ').first ?? 'there';
    final canRecord = app.currentRole?.canRecordFinance ?? false;

    final allocated = app.totalAllocated;
    final remaining = app.remainingBalance;
    final spent = app.totalExpended;
    final used = allocated == 0 ? 0.0 : (spent / allocated).clamp(0.0, 1.0);

    return BrutScreen(
      topBar: AppHeader(
        onBellTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      ),
      bottomPadding: AppLayout.section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppLayout.section),
          MonoLabel(
            '${_days[now.weekday - 1]} / ${_months[now.month - 1]} ${now.day}',
          ),
          const SizedBox(height: 6),
          Text(
            '${_greeting(now.hour)},\n$name.',
            style: AppText.display.copyWith(height: 1.1),
          ),
          if (AppHeader.scopeLineFor(app) case final scope?) ...[
            const SizedBox(height: 6),
            MonoLabel(scope),
          ],
          const SizedBox(height: AppLayout.section),

          // First thing under the greeting, because it is the first
          // question anyone opening the app has.
          const AlertWidget(),
          const SizedBox(height: AppLayout.section),

          // The hero: what is left, beside the two numbers that explain it.
          //
          // No fixed height. It used to be pinned at 168, which fitted at
          // 100% text and overflowed by three pixels on a phone with
          // larger system type — a bug nobody sees until it is on someone
          // else's device. IntrinsicHeight lets the tiles size themselves
          // and the card match them.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: BrutCard(
                    onTap: () => _open(context, 'money'),
                    // Blue, not black. The figure people open the app for
                    // should wear one of the department's two colours
                    // rather than a neutral that belongs to neither.
                    tone: BrutTone.brand,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${peso(remaining, decimals: 0)}',
                            style: AppText.heroNumber.copyWith(fontSize: 40),
                          ),
                        ),
                        const SizedBox(height: AppLayout.section),
                        const MonoLabel('Remaining budget'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppLayout.between),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Tile(
                        value: '${app.pendingExpenses.length}',
                        label: 'Awaiting review',
                        tone: app.pendingExpenses.isEmpty
                            ? BrutTone.neutral
                            : BrutTone.orange,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ExpensesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.between),

          Row(
            children: [
              Expanded(
                child: _Stat(
                  value: '${peso(allocated, decimals: 0)}',
                  label: 'Allocated',
                  onTap: () => _open(context, 'money'),
                ),
              ),
              const SizedBox(width: AppLayout.between),
              Expanded(
                child: _Stat(
                  value: '${peso(spent, decimals: 0)}',
                  label: 'Approved spending',
                  onTap: () => _open(context, 'money'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppLayout.between),

          BrutCard(
            onTap: () => _open(context, 'money'),
            radius: AppRadius.rowAll,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: MonoLabel('Budget used')),
                    Text(
                      '${(used * 100).round()}%',
                      style: AppText.number.copyWith(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                BrutProgressBar(
                  value: used,
                  tone: used >= 1 ? BrutTone.coral : BrutTone.orange,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppLayout.section),

          if (canRecord) ...[
            BrutButton(
              label: 'Record an expense',
              icon: Icons.document_scanner_outlined,
              tone: BrutTone.orange,
              size: BrutSize.large,
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ScannerScreen())),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.value,
    required this.label,
    required this.tone,
    this.onTap,
  });

  final String value;
  final String label;
  final BrutTone tone;

  /// Where the figure came from. A number with no way through to the
  /// records behind it is a dead end on the screen people open most.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: onTap,
      tone: tone,
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.moneyLarge.copyWith(fontSize: 24),
            ),
          ),
          const SizedBox(height: 6),
          MonoLabel(label, fontSize: 9),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return BrutCard(
      onTap: onTap,
      radius: AppRadius.rowAll,
      padding: const EdgeInsets.all(12),
      shadow: AppShadows.sm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppText.moneyLarge.copyWith(fontSize: 19),
            ),
          ),
          const SizedBox(height: 4),
          MonoLabel(label, fontSize: 9),
        ],
      ),
    );
  }
}

/// Where an alert row goes when tapped.
///
/// Most rows name an area, but the two review queues are screens inside
/// one — Money owns expenses, Events owns approvals — so they are named
/// directly rather than being given an area each.
void _open(BuildContext context, String where) {
  final WidgetBuilder? builder = switch (where) {
    'expenses' => (_) => const ExpensesScreen(),
    'events' => (_) => const EventsScreen(),
    _ => areaById(where)?.builder,
  };
  if (builder != null) {
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }
}

/// What is actually waiting on this account, and nothing else.
///
/// Only things this role can act on, and only when there are any — an
/// empty alert is noise, so it says the useful thing instead.
class AlertWidget extends StatelessWidget {
  const AlertWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final role = app.currentRole;
    final items = <({String label, String where, BrutTone tone})>[];

    if (role?.canReview ?? false) {
      final events = app.events.where((e) => e.status.isPending).length;
      if (events > 0) {
        items.add((
          label: '$events event${events == 1 ? '' : 's'} awaiting a decision',
          where: 'events',
          tone: BrutTone.sun,
        ));
      }
      final expenses = app.pendingExpenses.length;
      if (expenses > 0) {
        items.add((
          label: '$expenses expense${expenses == 1 ? '' : 's'} to review',
          where: 'expenses',
          tone: BrutTone.sun,
        ));
      }
    }

    final flagged = app.flaggedExpenses.length;
    if (flagged > 0) {
      items.add((
        label: '$flagged flagged for a second look',
        where: 'risk',
        tone: BrutTone.coral,
      ));
    }

    final low = app.catalog.where((i) => i.isLowStock).length;
    if (low > 0) {
      items.add((
        label: '$low item${low == 1 ? '' : 's'} low on stock',
        where: 'inventory',
        tone: BrutTone.sun,
      ));
    }

    if (items.isEmpty) {
      return BrutCard(
        tone: BrutTone.mint,
        radius: AppRadius.rowAll,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 20),
            const SizedBox(width: AppLayout.between),
            Expanded(
              child: Text(
                'Nothing waiting on you.',
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final shown = items.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutFoldable(
          title: 'Needs you',
          count: items.length,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              BrutListRow(
                title: shown[i].label,
                marker: BrutIconTile(
                  icon: Icons.priority_high,
                  tone: shown[i].tone,
                  size: 32,
                ),
                onTap: () => _open(context, shown[i].where),
              ),
              if (i != shown.length - 1)
                const SizedBox(height: AppLayout.tight),
            ],
          ],
        ),
      ],
    );
  }
}
