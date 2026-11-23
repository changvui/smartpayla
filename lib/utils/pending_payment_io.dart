/// Kept in memory on native: the app stays running, so a reload is rare.
final Map<String, ({double amount, double expectedTotal})> _pending = {};

void rememberPendingPayment({
  required String token,
  required double amount,
  required double expectedTotal,
}) {
  if (token.isEmpty || amount <= 0) return;
  _pending[token] = (amount: amount, expectedTotal: expectedTotal);
}

({double amount, double expectedTotal})? readPendingPayment(String token) =>
    _pending[token];

void clearPendingPayment(String token) {
  _pending.remove(token);
}
