import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// A dropdown styled like the app's text inputs.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  final T? value;
  final String hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(
              fontFamily: AppText.bodyFamily,
              fontSize: 13,
              color: AppColors.inkFaint,
            ),
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Department and organization pickers, for accounts that have to choose.
///
/// Only a Super Admin sees this: every other role's scope comes from its own
/// profile and the backend applies it server-side, so offering a chooser
/// would invite picking something the API then refuses. Show it behind
/// `AppState.mustChooseScope`.
///
/// An organization belongs to exactly one department, so changing the
/// department has to clear the organization — that is the caller's job via
/// [onDepartmentChanged], since the caller owns the state.
class ScopePicker extends StatelessWidget {
  const ScopePicker({
    super.key,
    required this.departments,
    required this.departmentId,
    required this.onDepartmentChanged,
    required this.organizations,
    required this.organizationId,
    required this.onOrganizationChanged,
    this.explanation,
  });

  final List<RemoteDepartment> departments;
  final String? departmentId;
  final ValueChanged<String?> onDepartmentChanged;

  /// Already narrowed to the chosen department — use
  /// `AppState.organizationsIn(departmentId)`.
  final List<RemoteOrganization> organizations;
  final String? organizationId;
  final ValueChanged<String?> onOrganizationChanged;

  /// Overrides the default sentence describing why this is being asked.
  final String? explanation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Scope', style: AppText.cardTitle),
          const SizedBox(height: 2),
          Text(
            explanation ??
                'Your account is not tied to a department, so choose where '
                    'this belongs.',
            style: AppText.caption,
          ),
          const SizedBox(height: 12),
          const Text('Department', style: AppText.caption),
          const SizedBox(height: 6),
          LabeledDropdown<String>(
            value: departmentId,
            hint: departments.isEmpty
                ? 'No departments available'
                : 'Select a department',
            items: [
              for (final d in departments)
                DropdownMenuItem(value: d.id, child: Text(d.label)),
            ],
            onChanged: onDepartmentChanged,
          ),
          const SizedBox(height: 12),
          const Text('Organization', style: AppText.caption),
          const SizedBox(height: 6),
          LabeledDropdown<String>(
            value: organizationId,
            hint: departmentId == null
                ? 'Choose a department first'
                : organizations.isEmpty
                    ? 'No organizations in that department'
                    : 'Select an organization',
            items: [
              for (final o in organizations)
                DropdownMenuItem(value: o.id, child: Text(o.label)),
            ],
            // Disabled until a department narrows the list.
            onChanged: departmentId == null ? null : onOrganizationChanged,
          ),
        ],
      ),
    );
  }
}
