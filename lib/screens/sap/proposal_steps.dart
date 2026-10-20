/// The whole job of proposing an activity, as five steps.
///
/// Creating the event and filling its form were two flows with two
/// progress bars, which made the second look like a different task
/// someone could skip. It is not: the event record is not what the
/// university wants, the filled SAS-SDS-FO-020 is.
///
/// So one bar runs across both. The first two steps are done the moment
/// the event exists, which is true whether you have just made it or are
/// coming back to one from last week.
abstract final class ProposalSteps {
  /// In order. Short, because five labels have to fit a phone's width.
  static const List<String> labels = [
    'Budget',
    'Event',
    'Activity',
    'Support',
    'Breakdown',
  ];

  /// Where the create-event screen's own two steps sit.
  static const int budget = 0;
  static const int event = 1;

  /// Where the three parts of the form sit. Part 1 is step three of
  /// five, not step one of three.
  static const int firstPart = 2;

  static int forPart(int partIndex) => firstPart + partIndex;

  static int get count => labels.length;
}
