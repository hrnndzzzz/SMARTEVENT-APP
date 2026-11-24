/// Models for the institutional-approval chain.
///
/// These describe the October backend's pre-activity gates: where the
/// activity happens, who signs for it, and what is still missing before
/// an Admin can hand it on.

/// On campus or off it. The distinction decides almost everything else:
/// the backend's readiness check puts participants, persons in charge,
/// vehicles and consent documents behind the off-campus branch, and asks
/// an on-campus activity for none of them.
enum ActivityLocation {
  onCampus('on_campus', 'On campus'),
  offCampus('off_campus', 'Off campus');

  const ActivityLocation(this.wireName, this.label);

  final String wireName;
  final String label;

  static ActivityLocation? fromWire(String? value) => switch (value) {
    'on_campus' => ActivityLocation.onCampus,
    'off_campus' => ActivityLocation.offCampus,
    _ => null,
  };
}

/// How everyone gets there.
///
/// On-campus activities must use [none]; the backend refuses anything
/// else outright, so the picker does too.
enum TransportMode {
  none('none', 'No vehicles'),
  institution('institution', 'Institution vehicles'),
  thirdParty('third_party', 'Third-party vehicles');

  const TransportMode(this.wireName, this.label);

  final String wireName;
  final String label;

  static TransportMode? fromWire(String? value) => switch (value) {
    'none' => TransportMode.none,
    'institution' => TransportMode.institution,
    'third_party' => TransportMode.thirdParty,
    _ => null,
  };
}

/// Where an activity happens and how people travel to it.
class EventLogistics {
  const EventLogistics({
    required this.activityLocation,
    required this.destination,
    required this.transportMode,
    required this.transportNotes,
  });

  final ActivityLocation activityLocation;
  final String destination;
  final TransportMode transportMode;
  final String? transportNotes;

  factory EventLogistics.fromJson(Map<String, dynamic> json) {
    return EventLogistics(
      activityLocation:
          ActivityLocation.fromWire(json['activity_location'] as String?) ??
          ActivityLocation.onCampus,
      destination: (json['destination'] as String?) ?? '',
      transportMode:
          TransportMode.fromWire(json['transport_mode'] as String?) ??
          TransportMode.none,
      transportNotes: json['transport_notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'activity_location': activityLocation.wireName,
    'destination': destination,
    'transport_mode': transportMode.wireName,
    'transport_notes': transportNotes,
  };
}

/// What is still in the way of approval.
///
/// The blockers are the backend's own sentences. They are shown as
/// written rather than reworded, because the same strings come back in
/// the 409 when approval is refused and two phrasings of one rule read
/// as two rules.
class EventReadiness {
  const EventReadiness({
    required this.ready,
    required this.blockers,
    required this.activityLocation,
    required this.participantCount,
    required this.picCount,
    required this.requiredPicCount,
    required this.unverifiedDocumentCount,
  });

  final bool ready;
  final List<String> blockers;
  final ActivityLocation? activityLocation;
  final int participantCount;
  final int picCount;
  final int requiredPicCount;
  final int unverifiedDocumentCount;

  factory EventReadiness.fromJson(Map<String, dynamic> json) => EventReadiness(
    ready: json['ready'] as bool? ?? false,
    blockers: [
      for (final blocker in (json['blockers'] as List? ?? const []))
        blocker.toString(),
    ],
    activityLocation: ActivityLocation.fromWire(
      json['activity_location'] as String?,
    ),
    participantCount: (json['participant_count'] as num?)?.toInt() ?? 0,
    picCount: (json['pic_count'] as num?)?.toInt() ?? 0,
    requiredPicCount: (json['required_pic_count'] as num?)?.toInt() ?? 0,
    unverifiedDocumentCount:
        (json['unverified_document_count'] as num?)?.toInt() ?? 0,
  );
}
