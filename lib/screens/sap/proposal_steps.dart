/// Filling in the proposal, as its three parts.
///
/// They are the form's own parts and nothing else. An earlier version
/// put the create-event screen's two steps in front of these, which
/// made the bar describe the app's plumbing rather than the paper the
/// person is filling in.
///
/// Parts 4 to 6 are the SDS Office's and are not steps here: a bar a
/// proposer cannot finish is worse than no bar.
abstract final class ProposalSteps {
  static const List<String> labels = ['Activity', 'Support', 'Breakdown'];

  static const int activity = 0;
  static const int support = 1;
  static const int breakdown = 2;

  static int get count => labels.length;
}
