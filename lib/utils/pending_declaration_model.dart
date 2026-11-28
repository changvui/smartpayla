/// A transfer the customer says they paid, waiting for the agent to confirm.
///
/// The statement snapshot only changes when the agent confirms, so without this
/// the page would look untouched the moment it reloads - and the customer would
/// either pay twice or assume the payment failed. It records what was declared
/// so the page can show "waiting for the agent" until the balance actually moves.
class PendingDeclaration {
  const PendingDeclaration({
    required this.amount,
    required this.billIds,
    required this.expectedTotal,
    required this.at,
  });

  final double amount;
  final List<String> billIds;

  /// What the statement total should read once the agent confirms.
  final double expectedTotal;
  final DateTime at;
}
