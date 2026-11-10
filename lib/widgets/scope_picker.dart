import 'package:flutter/material.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/brut.dart';

/// Department and organization pickers, for accounts that have to choose.
///
/// Only a Super Admin sees this: every other role's scope comes from its own
/// profile and the backend applies it server-side, so offering a chooser
/// would invite picking something the API then refuses. Show it behind
/// `AppState.mustChooseScope`.
///
/// An organization belongs to one department or to none, so changing the
/// department has to clear the organization — that is the caller's job via
/// [onDepartmentChanged], since the caller owns the state. What is sent is
/// the chosen organization's own department
/// (`AppState.departmentOfOrganization`), never this picker's value, so the
/// two cannot disagree.
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
    this.allowNoDepartment = true,
  });

  /// Offers "No department" ([kNoDepartment]) for the organizations outside
  /// any. Off where a department is required, such as for an Admin.
  final bool allowNoDepartment;

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
    return BrutCard(
      tone: BrutTone.brand,
      tinted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BrutSectionTitle('Scope'),
          const SizedBox(height: 4),
          Text(
            explanation ??
                'Your account is not tied to a department, so choose where '
                    'this belongs.',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          BrutDropdown<String>(
            label: 'Department',
            value: departmentId,
            hint: departments.isEmpty
                ? 'No departments available'
                : 'Select a department',
            items: [
              for (final d in departments)
                DropdownMenuItem(value: d.id, child: Text(d.label)),
              if (allowNoDepartment)
                const DropdownMenuItem(
                  value: kNoDepartment,
                  child: Text('No department'),
                ),
            ],
            onChanged: onDepartmentChanged,
          ),
          const SizedBox(height: 12),
          BrutDropdown<String>(
            label: 'Organization',
            value: organizationId,
            hint: departmentId == null
                ? 'Choose a department first'
                : organizations.isEmpty
                ? (departmentId == kNoDepartment
                      ? 'No organizations outside a department'
                      : 'No organizations in that department')
                : 'Select an organization',
            items: [
              for (final o in organizations)
                DropdownMenuItem(value: o.id, child: Text(o.label)),
            ],
            // Disabled until a department narrows the list.
            enabled: departmentId != null,
            onChanged: onOrganizationChanged,
          ),
        ],
      ),
    );
  }
}
