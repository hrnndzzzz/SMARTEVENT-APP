/// The SAS-SDS-FO-020 (001) Student Activity Proposal Form.
///
/// This models the paper form the university actually uses, which the
/// backend tracks as a six-part proposal carrying **nine physical
/// signatures**. Nothing here is an electronic signature: an SDS action is
/// an administrative record that someone inspected paper, and the uploaded
/// final scan is the authoritative evidence. The wording throughout avoids
/// calling a recorded checkpoint a signed document, because it is not one.
///
/// Field names match `app/schemas_sap.py` exactly — the backend rejects
/// unknown JSON keys, so a typo here is a 422 rather than a silently
/// dropped value.
library;

/// Where a proposal sits in its own lifecycle.
///
/// This is deliberately separate from the event's status: the backend
/// projects these onto the existing `EventStatus` for lists and dashboards
/// (`draft`/returned read as draft, department review as pending adviser
/// or admin, SDS review as pending institutional review), and does not add
/// SAP stages to that enum.
enum SapState {
  draft('draft', 'Draft'),

  /// Sent, and with the department: the Moderator first, then the Dean.
  /// The Dean's approval is what passes it to the SDS Office, and either
  /// can return it instead.
  pendingDepartmentReview('pending_department_review', 'With the department'),

  /// With the SDS Office.
  pendingReview('pending_sap_review', 'Under review'),
  revisionRequested('revision_requested', 'Returned'),

  /// The SDS Office has signed the pending revision. The revision is
  /// locked from here, and the printed copy goes out for the physical
  /// signatures before anyone marks it approved.
  sdsSigned('sds_signed', 'Signed by SDS'),
  approved('approved', 'Approved'),
  completed('completed', 'Completed'),

  /// The SDS Office's final decision (`POST /sds-reject`). Unlike a return,
  /// nothing follows it: the proposer cannot edit or resubmit, and the
  /// reason is the office's remarks.
  rejected('rejected', 'Rejected');

  const SapState(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapState? fromWire(String? value) {
    for (final state in SapState.values) {
      if (state.wireName == value) return state;
    }
    return null;
  }

  /// Parts 1–3 are the proposer's to edit only in these two states.
  bool get isProposerEditable =>
      this == SapState.draft || this == SapState.revisionRequested;
}

/// Who sent a proposal back to its proposer.
///
/// The server records this beside the return remarks, so the proposer
/// knows whose words they are reading.
enum SapReturnedBy {
  moderator('moderator', 'the Moderator'),
  dean('dean', 'the Dean'),
  sds('sds', 'the SDS Office');

  const SapReturnedBy(this.wireName, this.label);

  final String wireName;

  /// Worded to follow "Returned by", so it carries its own article.
  final String label;

  static SapReturnedBy? fromWire(String? value) {
    for (final who in SapReturnedBy.values) {
      if (who.wireName == value) return who;
    }
    return null;
  }
}

enum SapModality {
  faceToFace('face_to_face', 'Face-to-face'),
  online('online', 'Online'),
  hybrid('hybrid', 'Hybrid');

  const SapModality(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapModality? fromWire(String? v) {
    for (final m in SapModality.values) {
      if (m.wireName == v) return m;
    }
    return null;
  }
}

/// The three the paper offers.
///
/// `off_campus` was refused by the first backend slice and is accepted
/// now. It carries conditions the other two do not: an acknowledged
/// agreement, thirty days' notice, and a ROC/COC attachment on the
/// revision being submitted. The older CHED compliance workflow is a
/// separate thing and is not replaced by this.
enum SapSetting {
  onCampus('on_campus', 'In campus'),
  offCampus('off_campus', 'Off campus'),
  online('online', 'Online');

  const SapSetting(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapSetting? fromWire(String? v) {
    for (final s in SapSetting.values) {
      if (s.wireName == v) return s;
    }
    return null;
  }
}

enum SapCoreValue {
  courage('courage', 'Courage'),
  compassion('compassion', 'Compassion'),
  communityOriented('community_oriented', 'Community-Oriented'),
  humility('humility', 'Humility'),
  interiority('interiority', 'Interiority'),
  missionarySpirit('missionary_spirit', 'Missionary Spirit');

  const SapCoreValue(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapCoreValue? fromWire(String? v) {
    for (final c in SapCoreValue.values) {
      if (c.wireName == v) return c;
    }
    return null;
  }
}

/// Part 2's request types, as the backend names them.
enum SapSupportType {
  budget('budget', 'Budget'),
  vehicle('vehicle', 'Vehicle'),
  food('food', 'Food / snacks'),
  room('room', 'Room / venue'),
  sound('sound', 'Sound system'),
  microphone('microphone', 'Microphone'),
  projector('projector', 'LCD projector'),
  chairs('chairs', 'Chairs'),
  tables('tables', 'Tables'),
  diverseNeeds('diverse_needs', 'Provision for diverse needs'),
  other('other', 'Other');

  const SapSupportType(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapSupportType? fromWire(String? v) {
    for (final t in SapSupportType.values) {
      if (t.wireName == v) return t;
    }
    return null;
  }
}

/// Part 4's three-state answers. "Not applicable" always owes a reason,
/// which the backend enforces and the form should ask for inline rather
/// than failing at submission.
enum SapClearanceAnswer {
  yes('yes', 'Yes'),
  notApplicable('not_applicable', 'Not applicable'),
  none('none', 'None');

  const SapClearanceAnswer(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapClearanceAnswer? fromWire(String? v) {
    for (final a in SapClearanceAnswer.values) {
      if (a.wireName == v) return a;
    }
    return null;
  }
}

enum SapEvaluationOutcome {
  conducted('conducted', 'Conducted'),
  canceled('canceled', 'Canceled');

  const SapEvaluationOutcome(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapEvaluationOutcome? fromWire(String? v) {
    for (final o in SapEvaluationOutcome.values) {
      if (o.wireName == v) return o;
    }
    return null;
  }
}

/// A local time of day, as the backend wants it: `HH:MM:SS`, Asia/Manila,
/// no offset. Activities are same-day.
class SapTime implements Comparable<SapTime> {
  const SapTime(this.hour, this.minute, [this.second = 0]);

  final int hour;
  final int minute;
  final int second;

  static SapTime? fromWire(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return SapTime(h, m, s);
  }

  String get wire =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}';

  /// 12-hour, the way the form reads: `8:00 AM`.
  String get label {
    final suffix = hour < 12 ? 'AM' : 'PM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} $suffix';
  }

  @override
  int compareTo(SapTime other) {
    final a = hour * 3600 + minute * 60 + second;
    final b = other.hour * 3600 + other.minute * 60 + other.second;
    return a.compareTo(b);
  }

  @override
  bool operator ==(Object other) =>
      other is SapTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);

  @override
  String toString() => wire;
}

/// A date with no time, sent as `YYYY-MM-DD`.
String? _dateToWire(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

DateTime? _dateFromWire(String? v) => v == null ? null : DateTime.tryParse(v);

/// One row of Part 1's timed programme.
class SapProgramFlowItem {
  const SapProgramFlowItem({
    required this.start,
    required this.end,
    required this.activity,
  });

  final SapTime start;
  final SapTime end;
  final String activity;

  factory SapProgramFlowItem.fromJson(Map<String, dynamic> json) =>
      SapProgramFlowItem(
        start:
            SapTime.fromWire(json['start'] as String?) ?? const SapTime(0, 0),
        end: SapTime.fromWire(json['end'] as String?) ?? const SapTime(0, 0),
        activity: (json['activity'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
    'start': start.wire,
    'end': end.wire,
    'activity': activity,
  };
}

/// One line of the Part 3 budget breakdown.
///
/// [amount] stays a string all the way to the wire. The backend wants
/// exact decimals and checks the lines against the total, so rounding a
/// sum through a Dart `double` is how you get a 422 that nobody can
/// explain.
class SapBudgetItem {
  const SapBudgetItem({
    required this.particulars,
    required this.amount,
    this.quantity = 1,
    this.unitCost,
  });

  final String particulars;

  /// What the row sums to, and the figure the server checks against the
  /// total. It is authoritative: the backend does not work it out from
  /// quantity and unit cost, so a row can state all three and they are
  /// not required to agree arithmetically — the paper sometimes rounds.
  final String amount;

  /// How many. The paper's breakdown reads "Snacks · 150 · 10.00 ·
  /// 1,500.00"; before this existed the 150 and the 10.00 were flattened
  /// into the particulars text and the printed form stopped matching.
  final int quantity;

  /// Cost of one, as a decimal string. Null where the paper gives only a
  /// total, which is most rows.
  final String? unitCost;

  factory SapBudgetItem.fromJson(Map<String, dynamic> json) => SapBudgetItem(
    particulars: (json['particulars'] as String?) ?? '',
    amount: (json['amount'] ?? '0').toString(),
    // Rows saved before these existed come back without them, and the
    // server does not backfill: a missing quantity means one.
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
    unitCost: json['unit_cost'] == null ? null : json['unit_cost'].toString(),
  );

  Map<String, dynamic> toJson() => {
    'particulars': particulars,
    'quantity': quantity,
    if (unitCost != null) 'unit_cost': unitCost,
    'amount': amount,
  };

  SapBudgetItem copyWith({
    String? particulars,
    String? amount,
    int? quantity,
    String? unitCost,
  }) => SapBudgetItem(
    particulars: particulars ?? this.particulars,
    amount: amount ?? this.amount,
    quantity: quantity ?? this.quantity,
    unitCost: unitCost ?? this.unitCost,
  );
}

/// One Part 2 request.
class SapSupportRequest {
  const SapSupportRequest({
    required this.type,
    this.quantity = 1,
    this.specify,
  });

  final SapSupportType type;

  /// Required by the backend, and at least 1. Most rows on the paper are
  /// a bare tick with no number beside them, so a ticked row without a
  /// stated count means one of the thing.
  final int quantity;

  final String? specify;

  factory SapSupportRequest.fromJson(Map<String, dynamic> json) =>
      SapSupportRequest(
        type:
            SapSupportType.fromWire(json['type'] as String?) ??
            SapSupportType.other,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        specify: json['specify'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'type': type.wireName,
    'quantity': quantity < 1 ? 1 : quantity,
    if (specify != null && specify!.isNotEmpty) 'specify': specify,
  };
}

/// One class the activity interrupts.
///
/// These are declared by hand. The backend infers nothing from a
/// timetable, and requires each row to overlap the activity on the same
/// date.
class SapAffectedClass {
  const SapAffectedClass({
    required this.yearLevel,
    required this.subject,
    required this.classDate,
    required this.start,
    required this.end,
    required this.professor,
  });

  final String yearLevel;
  final String subject;
  final DateTime classDate;
  final SapTime start;
  final SapTime end;
  final String professor;

  factory SapAffectedClass.fromJson(
    Map<String, dynamic> json,
  ) => SapAffectedClass(
    yearLevel: (json['year_level'] as String?) ?? '',
    subject: (json['subject'] as String?) ?? '',
    classDate: _dateFromWire(json['class_date'] as String?) ?? DateTime(1970),
    start: SapTime.fromWire(json['start'] as String?) ?? const SapTime(0, 0),
    end: SapTime.fromWire(json['end'] as String?) ?? const SapTime(0, 0),
    professor: (json['professor'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'year_level': yearLevel,
    'subject': subject,
    'class_date': _dateToWire(classDate),
    'start': start.wire,
    'end': end.wire,
    'professor': professor,
  };
}

/// Part 4, which only SDS fills in.
class SapClearance {
  const SapClearance({
    required this.parentsConsent,
    this.parentsConsentReason,
    required this.attachments,
    required this.classInterruption,
    this.classInterruptionRemarks,
    required this.medicalExam,
    this.medicalExamReason,
    required this.reportOfCompliance,
    this.reportOfComplianceReason,
    required this.studentPersonnelRatio,
  });

  final SapClearanceAnswer parentsConsent;
  final String? parentsConsentReason;
  final String attachments;
  final SapClearanceAnswer classInterruption;
  final String? classInterruptionRemarks;
  final SapClearanceAnswer medicalExam;
  final String? medicalExamReason;
  final SapClearanceAnswer reportOfCompliance;
  final String? reportOfComplianceReason;
  final String studentPersonnelRatio;

  factory SapClearance.fromJson(Map<String, dynamic> json) => SapClearance(
    parentsConsent:
        SapClearanceAnswer.fromWire(json['parents_consent'] as String?) ??
        SapClearanceAnswer.notApplicable,
    parentsConsentReason: json['parents_consent_reason'] as String?,
    attachments: (json['attachments'] as String?) ?? '',
    classInterruption:
        SapClearanceAnswer.fromWire(json['class_interruption'] as String?) ??
        SapClearanceAnswer.none,
    classInterruptionRemarks: json['class_interruption_remarks'] as String?,
    medicalExam:
        SapClearanceAnswer.fromWire(json['medical_exam'] as String?) ??
        SapClearanceAnswer.notApplicable,
    medicalExamReason: json['medical_exam_reason'] as String?,
    reportOfCompliance:
        SapClearanceAnswer.fromWire(json['report_of_compliance'] as String?) ??
        SapClearanceAnswer.notApplicable,
    reportOfComplianceReason: json['report_of_compliance_reason'] as String?,
    studentPersonnelRatio: (json['student_personnel_ratio'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'parents_consent': parentsConsent.wireName,
    if (parentsConsentReason != null)
      'parents_consent_reason': parentsConsentReason,
    'attachments': attachments,
    'class_interruption': classInterruption.wireName,
    if (classInterruptionRemarks != null)
      'class_interruption_remarks': classInterruptionRemarks,
    'medical_exam': medicalExam.wireName,
    if (medicalExamReason != null) 'medical_exam_reason': medicalExamReason,
    'report_of_compliance': reportOfCompliance.wireName,
    if (reportOfComplianceReason != null)
      'report_of_compliance_reason': reportOfComplianceReason,
    'student_personnel_ratio': studentPersonnelRatio,
  };
}

/// What SDS recorded about one physical signature.
class SapCheckpointEvidence {
  const SapCheckpointEvidence({
    required this.signerName,
    required this.signerReference,
    this.assignedUserId,
    required this.physicalSignatureDate,
    this.remarks,
    required this.recordedOnBehalf,
  });

  final String signerName;
  final String signerReference;
  final String? assignedUserId;
  final DateTime physicalSignatureDate;
  final String? remarks;
  final bool recordedOnBehalf;

  factory SapCheckpointEvidence.fromJson(Map<String, dynamic> json) =>
      SapCheckpointEvidence(
        signerName: (json['signer_name'] as String?) ?? '',
        signerReference: (json['signer_reference'] as String?) ?? '',
        assignedUserId: json['assigned_user_id'] as String?,
        physicalSignatureDate:
            _dateFromWire(json['physical_signature_date'] as String?) ??
            DateTime(1970),
        remarks: json['remarks'] as String?,
        recordedOnBehalf: (json['recorded_on_behalf'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
    'signer_name': signerName,
    'signer_reference': signerReference,
    'assigned_user_id': assignedUserId,
    'physical_signature_date': _dateToWire(physicalSignatureDate),
    if (remarks != null) 'remarks': remarks,
    'recorded_on_behalf': recordedOnBehalf,
  };
}

/// One of the nine slots on Part 5.
class SapWorkflowStep {
  const SapWorkflowStep({
    required this.id,
    required this.slot,
    required this.position,
    required this.displayLabel,
    required this.revisionNo,
    required this.status,
    required this.actionable,
    this.evidence,
    this.recordedBy,
    this.recordedAt,
  });

  final String id;

  /// 1–9, in the order they appear on the paper.
  final int slot;

  /// The role as the form prints it — "ACPES Moderator", "CITE Dean".
  /// Driven by organization and department labels, never hardcoded.
  final String position;

  /// "Prepared by", "Reviewed by", "Noted by", and so on.
  final String displayLabel;

  final int revisionNo;

  /// `pending` or `recorded`.
  final String status;

  /// Whether this step is the one SDS can record next.
  final bool actionable;

  final SapCheckpointEvidence? evidence;
  final String? recordedBy;
  final DateTime? recordedAt;

  bool get isRecorded => status == 'recorded';

  factory SapWorkflowStep.fromJson(Map<String, dynamic> json) =>
      SapWorkflowStep(
        id: json['id'] as String,
        slot: (json['slot'] as num?)?.toInt() ?? 0,
        position: (json['position'] as String?) ?? '',
        displayLabel: (json['display_label'] as String?) ?? '',
        revisionNo: (json['revision_no'] as num?)?.toInt() ?? 0,
        status: (json['status'] as String?) ?? 'pending',
        actionable: (json['actionable'] as bool?) ?? false,
        evidence: json['evidence'] == null
            ? null
            : SapCheckpointEvidence.fromJson(
                Map<String, dynamic>.from(json['evidence'] as Map),
              ),
        recordedBy: json['recorded_by'] as String?,
        recordedAt: json['recorded_at'] == null
            ? null
            : DateTime.tryParse(json['recorded_at'] as String),
      );
}

/// `GET /workflow` — the current revision's nine-step progress.
class SapWorkflow {
  const SapWorkflow({
    required this.state,
    required this.revisionNo,
    required this.version,
    required this.completedCount,
    required this.totalCount,
    required this.steps,
  });

  final SapState? state;
  final int revisionNo;
  final int version;
  final int completedCount;
  final int totalCount;
  final List<SapWorkflowStep> steps;

  /// No steps exist until the first submission.
  bool get hasStarted => steps.isNotEmpty;

  SapWorkflowStep? get nextActionable {
    for (final s in steps) {
      if (s.actionable && !s.isRecorded) return s;
    }
    return null;
  }

  factory SapWorkflow.fromJson(Map<String, dynamic> json) => SapWorkflow(
    state: SapState.fromWire(json['state'] as String?),
    revisionNo: (json['revision_no'] as num?)?.toInt() ?? 0,
    version: (json['version'] as num?)?.toInt() ?? 0,
    completedCount: (json['completed_count'] as num?)?.toInt() ?? 0,
    totalCount: (json['total_count'] as num?)?.toInt() ?? 9,
    steps: [
      for (final row in (json['steps'] as List? ?? const []))
        SapWorkflowStep.fromJson(Map<String, dynamic>.from(row as Map)),
    ],
  );
}

/// Part 6, recorded once by SDS after the activity.
class SapEvaluation {
  const SapEvaluation({
    required this.outcome,
    required this.remarks,
    this.evaluatedBy,
    this.evaluatedAt,
  });

  final SapEvaluationOutcome outcome;
  final String remarks;
  final String? evaluatedBy;
  final DateTime? evaluatedAt;

  factory SapEvaluation.fromJson(Map<String, dynamic> json) => SapEvaluation(
    outcome:
        SapEvaluationOutcome.fromWire(json['outcome'] as String?) ??
        SapEvaluationOutcome.conducted,
    remarks: (json['remarks'] as String?) ?? '',
    evaluatedBy: json['evaluated_by'] as String?,
    evaluatedAt: json['evaluated_at'] == null
        ? null
        : DateTime.tryParse(json['evaluated_at'] as String),
  );
}

/// Parts 1–3: everything the proposing organization fills in.
class SapDetails {
  const SapDetails({
    this.schoolYear,
    this.departmentType,
    this.department,
    this.proposalDate,
    this.title,
    this.organizationName,
    this.course,
    this.activityDate,
    this.startTime,
    this.endTime,
    this.modality,
    this.setting,
    this.offCampusAgreement = false,
    this.venue,
    this.personsInCharge,
    this.attire,
    this.activityTypes = const [],
    this.scope,
    this.programTypes = const [],
    this.expectedStudents,
    this.rationale,
    this.objectives,
    this.coreValues = const [],
    this.egas = const [],
    this.emergencyPlan,
    this.totalBudget,
    this.fundingSource,
    this.additionalInformation,
    this.excuseArrangement,
  });

  final String? schoolYear;
  final String? departmentType;
  final String? department;
  final DateTime? proposalDate;
  final String? title;
  final String? organizationName;
  final String? course;
  final DateTime? activityDate;
  final SapTime? startTime;
  final SapTime? endTime;
  final SapModality? modality;
  final SapSetting? setting;

  /// The proposer's acknowledgement of the off-campus conditions. The
  /// server requires this to be true for `off_campus` and false for
  /// everything else, and refuses the pair when they disagree.
  final bool offCampusAgreement;
  final String? venue;
  final String? personsInCharge;
  final String? attire;
  final List<String> activityTypes;
  final String? scope;
  final List<String> programTypes;
  final int? expectedStudents;
  final String? rationale;
  final String? objectives;
  final List<SapCoreValue> coreValues;
  final List<int> egas;
  final String? emergencyPlan;

  /// A decimal string, for the same reason as [SapBudgetItem.amount].
  final String? totalBudget;

  final String? fundingSource;
  final String? additionalInformation;
  final String? excuseArrangement;

  factory SapDetails.fromJson(Map<String, dynamic> json) => SapDetails(
    schoolYear: json['school_year'] as String?,
    departmentType: json['department_type'] as String?,
    department: json['department'] as String?,
    proposalDate: _dateFromWire(json['proposal_date'] as String?),
    title: json['title'] as String?,
    organizationName: json['organization_name'] as String?,
    course: json['course'] as String?,
    activityDate: _dateFromWire(json['activity_date'] as String?),
    startTime: SapTime.fromWire(json['start_time'] as String?),
    endTime: SapTime.fromWire(json['end_time'] as String?),
    modality: SapModality.fromWire(json['modality'] as String?),
    setting: SapSetting.fromWire(json['setting'] as String?),
    offCampusAgreement: (json['off_campus_agreement'] as bool?) ?? false,
    venue: json['venue'] as String?,
    personsInCharge: json['persons_in_charge'] as String?,
    attire: json['attire'] as String?,
    activityTypes: [
      for (final v in (json['activity_types'] as List? ?? const []))
        v.toString(),
    ],
    scope: json['scope'] as String?,
    programTypes: [
      for (final v in (json['program_types'] as List? ?? const []))
        v.toString(),
    ],
    expectedStudents: (json['expected_students'] as num?)?.toInt(),
    rationale: json['rationale'] as String?,
    objectives: json['objectives'] as String?,
    coreValues: [
      for (final v in (json['core_values'] as List? ?? const []))
        ?SapCoreValue.fromWire(v.toString()),
    ],
    egas: [
      for (final v in (json['egas'] as List? ?? const []))
        ?int.tryParse(v.toString()),
    ],
    emergencyPlan: json['emergency_plan'] as String?,
    totalBudget: json['total_budget']?.toString(),
    fundingSource: json['funding_source'] as String?,
    additionalInformation: json['additional_information'] as String?,
    excuseArrangement: json['excuse_arrangement'] as String?,
  );

  /// Replaces named fields, leaving the rest alone.
  ///
  /// [clearVenue] and friends exist because a plain `null` argument means
  /// "unchanged" here; clearing a field has to be asked for explicitly.
  SapDetails copyWith({
    String? schoolYear,
    String? departmentType,
    String? department,
    DateTime? proposalDate,
    String? title,
    String? organizationName,
    String? course,
    DateTime? activityDate,
    SapTime? startTime,
    SapTime? endTime,
    SapModality? modality,
    SapSetting? setting,
    bool? offCampusAgreement,
    String? venue,
    String? personsInCharge,
    String? attire,
    List<String>? activityTypes,
    String? scope,
    List<String>? programTypes,
    int? expectedStudents,
    String? rationale,
    String? objectives,
    List<SapCoreValue>? coreValues,
    List<int>? egas,
    String? emergencyPlan,
    String? totalBudget,
    String? fundingSource,
    String? additionalInformation,
    String? excuseArrangement,
  }) {
    return SapDetails(
      schoolYear: schoolYear ?? this.schoolYear,
      departmentType: departmentType ?? this.departmentType,
      department: department ?? this.department,
      proposalDate: proposalDate ?? this.proposalDate,
      title: title ?? this.title,
      organizationName: organizationName ?? this.organizationName,
      course: course ?? this.course,
      activityDate: activityDate ?? this.activityDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      modality: modality ?? this.modality,
      setting: setting ?? this.setting,
      offCampusAgreement: offCampusAgreement ?? this.offCampusAgreement,
      venue: venue ?? this.venue,
      personsInCharge: personsInCharge ?? this.personsInCharge,
      attire: attire ?? this.attire,
      activityTypes: activityTypes ?? this.activityTypes,
      scope: scope ?? this.scope,
      programTypes: programTypes ?? this.programTypes,
      expectedStudents: expectedStudents ?? this.expectedStudents,
      rationale: rationale ?? this.rationale,
      objectives: objectives ?? this.objectives,
      coreValues: coreValues ?? this.coreValues,
      egas: egas ?? this.egas,
      emergencyPlan: emergencyPlan ?? this.emergencyPlan,
      totalBudget: totalBudget ?? this.totalBudget,
      fundingSource: fundingSource ?? this.fundingSource,
      additionalInformation:
          additionalInformation ?? this.additionalInformation,
      excuseArrangement: excuseArrangement ?? this.excuseArrangement,
    );
  }

  /// Only the keys that were actually set.
  ///
  /// `PATCH` takes a partial object, and the backend rejects unknown keys,
  /// so sending explicit nulls for untouched fields would either wipe them
  /// or be refused. Drafts are saved field by field as they are filled in.
  Map<String, dynamic> toPatchJson() => {
    if (schoolYear != null) 'school_year': schoolYear,
    if (departmentType != null) 'department_type': departmentType,
    if (department != null) 'department': department,
    if (proposalDate != null) 'proposal_date': _dateToWire(proposalDate),
    if (title != null) 'title': title,
    if (organizationName != null) 'organization_name': organizationName,
    if (course != null) 'course': course,
    if (activityDate != null) 'activity_date': _dateToWire(activityDate),
    if (startTime != null) 'start_time': startTime!.wire,
    if (endTime != null) 'end_time': endTime!.wire,
    if (modality != null) 'modality': modality!.wireName,
    if (setting != null) 'setting': setting!.wireName,
    // Sent whenever a setting is, because the server compares the two
    // and rejects a true that is not off-campus as readily as a missing
    // one that is.
    if (setting != null) 'off_campus_agreement': offCampusAgreement,
    if (venue != null) 'venue': venue,
    if (personsInCharge != null) 'persons_in_charge': personsInCharge,
    if (attire != null) 'attire': attire,
    if (activityTypes.isNotEmpty) 'activity_types': activityTypes,
    if (scope != null) 'scope': scope,
    if (programTypes.isNotEmpty) 'program_types': programTypes,
    if (expectedStudents != null) 'expected_students': expectedStudents,
    if (rationale != null) 'rationale': rationale,
    if (objectives != null) 'objectives': objectives,
    if (coreValues.isNotEmpty)
      'core_values': [for (final c in coreValues) c.wireName],
    if (egas.isNotEmpty) 'egas': egas,
    if (emergencyPlan != null) 'emergency_plan': emergencyPlan,
    if (totalBudget != null) 'total_budget': totalBudget,
    if (fundingSource != null) 'funding_source': fundingSource,
    if (additionalInformation != null)
      'additional_information': additionalInformation,
    if (excuseArrangement != null) 'excuse_arrangement': excuseArrangement,
  };
}

/// The whole working proposal, as every endpoint under the base returns it.
class SapProposal {
  const SapProposal({
    required this.id,
    required this.eventId,
    required this.state,
    required this.version,
    required this.revisionNo,
    required this.formCode,
    required this.formVersion,
    required this.details,
    required this.programFlow,
    required this.budgetItems,
    required this.supportRequests,
    required this.affectedClasses,
    this.clearance,
    this.evaluation,
    this.returnRemarks,
    this.returnedBy,
    this.sdsRemarks = '',
    this.sdsSectionRemarks = const {},
  });

  final String id;
  final String eventId;
  final SapState? state;

  /// The optimistic edit version. Every mutation except creation must send
  /// this back as `expected_version`; a 409 means someone else moved
  /// first and the screen must reload rather than retry.
  final int version;

  /// The submitted revision, 0 until first submission.
  final int revisionNo;

  final String formCode;
  final String formVersion;

  final SapDetails details;
  final List<SapProgramFlowItem> programFlow;
  final List<SapBudgetItem> budgetItems;
  final List<SapSupportRequest> supportRequests;
  final List<SapAffectedClass> affectedClasses;

  /// Null until SDS has confirmed Part 4. Cleared whenever Parts 1–3 or a
  /// collection change, which is why the form warns before such an edit.
  final SapClearance? clearance;

  final SapEvaluation? evaluation;
  final String? returnRemarks;

  /// Who returned it, alongside [returnRemarks]. Null unless the proposal
  /// is currently returned: the server clears it when the proposal is sent
  /// again, and a rejection is not a return.
  final SapReturnedBy? returnedBy;

  /// What the SDS Office last saved against the current revision, signed
  /// or not. Empty until it saves something.
  final String sdsRemarks;
  final Map<SapRemarkSection, String> sdsSectionRemarks;

  bool get isProposerEditable => state?.isProposerEditable ?? false;

  /// Collections are replaced wholesale and capped by the backend, subject
  /// to the printed form still fitting on six pages.
  static const int maxCollectionItems = 16;

  factory SapProposal.fromJson(Map<String, dynamic> json) => SapProposal(
    id: json['id'] as String,
    eventId: (json['event_id'] as String?) ?? '',
    state: SapState.fromWire(json['state'] as String?),
    version: (json['version'] as num?)?.toInt() ?? 0,
    revisionNo: (json['revision_no'] as num?)?.toInt() ?? 0,
    formCode: (json['form_code'] as String?) ?? '020',
    formVersion: (json['form_version'] as String?) ?? '001',
    details: SapDetails.fromJson(
      Map<String, dynamic>.from((json['details'] as Map?) ?? const {}),
    ),
    // The server nests these under `collections`, keyed exactly as the
    // endpoints are named — hyphens and all. Reading them from the top
    // level silently yielded four empty lists, so anything saved came
    // back blank on the next load.
    programFlow: [
      for (final row in _rows(json, 'program-flow'))
        SapProgramFlowItem.fromJson(row),
    ],
    budgetItems: [
      for (final row in _rows(json, 'budget-items'))
        SapBudgetItem.fromJson(row),
    ],
    supportRequests: [
      for (final row in _rows(json, 'support-requests'))
        SapSupportRequest.fromJson(row),
    ],
    affectedClasses: [
      for (final row in _rows(json, 'affected-classes'))
        SapAffectedClass.fromJson(row),
    ],
    clearance: json['clearance'] == null
        ? null
        : SapClearance.fromJson(
            Map<String, dynamic>.from(json['clearance'] as Map),
          ),
    evaluation: json['evaluation'] == null
        ? null
        : SapEvaluation.fromJson(
            Map<String, dynamic>.from(json['evaluation'] as Map),
          ),
    returnRemarks: json['return_remarks'] as String?,
    returnedBy: SapReturnedBy.fromWire(json['returned_by'] as String?),
    sdsRemarks: (_review(json)['overall_remarks'] as String?) ?? '',
    sdsSectionRemarks: {
      for (final MapEntry(:key, :value)
          in ((_review(json)['section_remarks'] as Map?) ?? const {}).entries)
        ?SapRemarkSection.fromWire(key as String): value as String,
    },
  );

  /// The server's `sds_review`, empty until the office has saved one.
  static Map _review(Map<String, dynamic> json) =>
      json['sds_review'] is Map ? json['sds_review'] as Map : const {};

  /// One collection out of the nested `collections` object.
  static List<Map<String, dynamic>> _rows(
    Map<String, dynamic> json,
    String key,
  ) {
    final collections = json['collections'];
    if (collections is! Map) return const [];
    final rows = collections[key];
    if (rows is! List) return const [];
    return [for (final row in rows) Map<String, dynamic>.from(row as Map)];
  }
}

/// A section of the form the SDS Office can pin a remark to.
///
/// The server keeps a fixed set and rejects anything outside it, so the
/// app offers these and no free-text keys.
enum SapRemarkSection {
  activityDetails('activity_details', 'Activity details'),
  budget('budget', 'Budget'),
  supportRequests('support_requests', 'School support'),
  additionalInformation('additional_information', 'Additional information'),
  clearance('clearance', 'Clearance'),
  other('other', 'Other');

  const SapRemarkSection(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapRemarkSection? fromWire(String? value) {
    for (final s in SapRemarkSection.values) {
      if (s.wireName == value) return s;
    }
    return null;
  }
}

/// One point of a drawn signature, normalised to the signing box.
///
/// Both coordinates run 0 to 1 so the drawing survives a different
/// screen size; the server rejects anything outside that range.
class SapSignaturePoint {
  const SapSignaturePoint(this.x, this.y);

  final double x;
  final double y;

  bool get isNormalised => x >= 0 && x <= 1 && y >= 0 && y <= 1;

  Map<String, double> toJson() => {'x': x, 'y': y};
}

/// A drawn SDS signature: one list of points per stroke of the pen.
///
/// The limits here are the server's own. They are checked before sending
/// because a rejected signature means the signer has to draw it again,
/// and a 422 does not say which rule was broken.
class SapSignature {
  const SapSignature(this.strokes);

  final List<List<SapSignaturePoint>> strokes;

  static const int maxStrokes = 80;
  static const int maxPoints = 5000;

  int get pointCount =>
      strokes.fold(0, (total, stroke) => total + stroke.length);

  /// Why the server would refuse this, or null if it would take it.
  String? get problem {
    if (strokes.isEmpty) return 'Nothing has been drawn yet.';
    if (strokes.any((s) => s.isEmpty)) return 'Nothing has been drawn yet.';
    if (strokes.length > maxStrokes) {
      return 'That is more than $maxStrokes separate strokes.';
    }
    if (pointCount > maxPoints) {
      return 'The drawing is too detailed to send.';
    }
    if (strokes.any((s) => s.any((p) => !p.isNormalised))) {
      return 'Part of the drawing fell outside the signing box.';
    }
    return null;
  }

  bool get isSendable => problem == null;

  List<List<Map<String, double>>> toJson() => [
    for (final stroke in strokes) [for (final point in stroke) point.toJson()],
  ];
}

/// What a supporting file is for.
///
/// The server keeps this list closed. `rocCoc` is the one with a rule
/// attached: an off-campus proposal cannot be submitted without one on
/// the revision being sent.
enum SapAttachmentCategory {
  apf('apf', 'Activity Proposal Form'),
  pcf('pcf', 'Parent Consent Form'),
  appendix('appendix', 'Appendix'),
  rocCoc('roc_coc', 'ROC / COC'),
  other('other', 'Supporting document');

  const SapAttachmentCategory(this.wireName, this.label);

  final String wireName;
  final String label;

  static SapAttachmentCategory? fromWire(String? value) {
    for (final c in SapAttachmentCategory.values) {
      if (c.wireName == value) return c;
    }
    return null;
  }
}

/// One supporting file, as the server lists it.
///
/// Files belong to the revision they were uploaded for. They are listed
/// by name on the printed form but never merged into it, so each one is
/// downloaded separately.
class SapAttachment {
  const SapAttachment({
    required this.id,
    required this.category,
    required this.filename,
  });

  final String id;
  final SapAttachmentCategory? category;
  final String filename;

  /// Keys as `SAPAttachmentOut` sends them.
  factory SapAttachment.fromJson(Map<String, dynamic> json) => SapAttachment(
    id: (json['id'] as String?) ?? '',
    category: SapAttachmentCategory.fromWire(json['category'] as String?),
    filename:
        (json['display_name'] as String?) ??
        (json['file_name'] as String?) ??
        '',
  );
}

/// What the server will take as a supporting file.
///
/// Checked before sending: an upload refused for its type or size costs
/// the proposer the whole transfer before it says so.
class SapUploadLimits {
  const SapUploadLimits._();

  static const int maxBytes = 10 * 1024 * 1024;

  static const Map<String, String> _byExtension = {
    'pdf': 'application/pdf',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
  };

  /// The media type to send for [filename], or null if the server would
  /// refuse it. The extension decides, because the server validates the
  /// part's declared type and does not sniff the bytes.
  static String? contentTypeFor(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return null;
    return _byExtension[filename.substring(dot + 1).toLowerCase()];
  }

  /// Why this file would be refused, or null if it would be taken.
  static String? problemWith(String filename, int sizeBytes) {
    if (contentTypeFor(filename) == null) {
      return 'Only PDF, PNG and JPEG files can be attached.';
    }
    if (sizeBytes > maxBytes) {
      return 'That file is over the 10 MB limit.';
    }
    if (sizeBytes <= 0) return 'That file is empty.';
    return null;
  }
}
