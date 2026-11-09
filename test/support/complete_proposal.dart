import 'package:smartevent/api/models/sap_proposal.dart';
import 'package:smartevent/state/sap_form.dart';

/// Parts 1 to 3 with everything a proposer must fill in, as the server
/// stores them. The app refuses to send a half-filled proposal, so a test
/// that sends one starts from this.
const Map<String, Object> completeDetailsJson = {
  'title': 'Hack the Future',
  'organization_name': 'ACPES',
  'school_year': '2026-2027',
  'department_type': 'College',
  'department': 'CITE',
  'proposal_date': '2026-09-26',
  'activity_date': '2026-10-28',
  'start_time': '08:00:00',
  'end_time': '11:00:00',
  'setting': 'online',
  'modality': 'online',
  'venue': 'Online conference',
  'persons_in_charge': 'ACPES officers',
  'activity_types': ['Seminar'],
  'scope': 'organizational',
  'expected_students': 145,
  'program_types': ['Academic'],
  'rationale': 'Cybersecurity awareness and responsible ethical hacking.',
  'objectives': 'Understand digital safety.',
  'core_values': ['courage'],
  'egas': [1],
  'emergency_plan': 'Contact the assigned staff.',
  'total_budget': '2500.00',
  'funding_source': 'Organization funds',
};

const Map<String, Object> completeCollectionsJson = {
  'program-flow': [
    {'start': '08:00:00', 'end': '11:00:00', 'activity': 'Seminar'},
  ],
  'budget-items': [
    {'particulars': 'Speaker', 'amount': '2500.00'},
  ],
  'support-requests': <Object>[],
  'affected-classes': <Object>[],
};

/// [form], with every part a proposer must fill in filled in.
SapForm filledIn(SapForm form) {
  form.updateDetails((_) => SapDetails.fromJson(completeDetailsJson));
  form.setProgramFlow([
    for (final row in completeCollectionsJson['program-flow']! as List)
      SapProgramFlowItem.fromJson(row as Map<String, dynamic>),
  ]);
  form.setBudgetItems([
    for (final row in completeCollectionsJson['budget-items']! as List)
      SapBudgetItem.fromJson(row as Map<String, dynamic>),
  ]);
  return form;
}
