import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class EventDetailScreen extends StatelessWidget {
  final String title;
  final String org;
  final String date;
  final String venue;
  final String budget;
  final String attendees;
  final int approvalStep;

  const EventDetailScreen({
    super.key,
    required this.title,
    required this.org,
    required this.date,
    required this.venue,
    required this.budget,
    required this.attendees,
    required this.approvalStep,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.ink),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: AppText.headerFamily,
                  fontWeight: FontWeight.w500,
                  fontSize: 19,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text('$org · $date', style: AppText.caption),
              const SizedBox(height: 18),
              _ApprovalTimeline(currentStep: approvalStep),
              const SizedBox(height: 14),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Event details', style: AppText.cardTitle),
                      const SizedBox(height: 10),
                      _detailRow('Venue', venue),
                      const SizedBox(height: 6),
                      _detailRow('Requested budget', budget, mono: true),
                      const SizedBox(height: 6),
                      _detailRow('Attendees', attendees),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit Proposal'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool mono = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.caption),
        Text(
          value,
          style: TextStyle(
            fontFamily: mono ? AppText.monoFamily : AppText.bodyFamily,
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _ApprovalTimeline extends StatelessWidget {
  final int currentStep;
  const _ApprovalTimeline({required this.currentStep});

  static const _steps = ['Submitted', 'Review', 'Budget OK', 'Active'];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Approval progress', style: AppText.caption),
            const SizedBox(height: 14),
            Row(
              children: List.generate(_steps.length * 2 - 1, (i) {
                if (i.isOdd) {
                  final leftDone = (i - 1) ~/ 2 < currentStep;
                  return Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 15),
                      color: leftDone ? AppColors.indigo : AppColors.border,
                    ),
                  );
                }
                final stepIndex = i ~/ 2;
                final isDone = stepIndex < currentStep;
                final isCurrent = stepIndex == currentStep;
                return Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isDone
                            ? AppColors.indigo
                            : isCurrent
                            ? AppColors.marigold
                            : const Color(0xFFF4F2EC),
                        shape: BoxShape.circle,
                      ),
                      child: isDone
                          ? const Icon(Icons.check, size: 12, color: Colors.white)
                          : isCurrent
                          ? Center(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                      )
                          : null,
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 52,
                      child: Text(
                        _steps[stepIndex],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppText.bodyFamily,
                          fontSize: 9,
                          color: isDone || isCurrent ? AppColors.ink : AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}