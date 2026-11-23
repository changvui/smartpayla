import 'package:web/web.dart' as web;

const _maxAge = Duration(hours: 6);

String _key(String token) => 'smartpayla_paid_$token';

/// Remembers a gateway payment that the ledger has not applied yet.
///
/// [expectedTotal] is what the statement should read once the agent confirms;
/// storing it lets the page tell "not applied yet" from "already applied" and
/// stop double-subtracting.
void rememberPendingPayment({
  required String token,
  required double amount,
  required double expectedTotal,
}) {
  if (token.isEmpty || amount <= 0) return;
  try {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    web.window.localStorage.setItem(
      _key(token),
      '$amount|$expectedTotal|$stamp',
    );
  } catch (_) {
    // Private mode: the page simply falls back to the snapshot.
  }
}

({double amount, double expectedTotal})? readPendingPayment(String token) {
  if (token.isEmpty) return null;
  try {
    final raw = web.window.localStorage.getItem(_key(token));
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 3) return null;
    final amount = double.tryParse(parts[0]);
    final expected = double.tryParse(parts[1]);
    final stamp = int.tryParse(parts[2]);
    if (amount == null || expected == null || stamp == null) return null;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(stamp),
    );
    if (age > _maxAge) {
      clearPendingPayment(token);
      return null;
    }
    return (amount: amount, expectedTotal: expected);
  } catch (_) {
    return null;
  }
}

void clearPendingPayment(String token) {
  if (token.isEmpty) return;
  try {
    web.window.localStorage.removeItem(_key(token));
  } catch (_) {
    // Nothing to clear.
  }
}
