import 'pending_declaration_model.dart';

/// Kept in memory on native: a statement is a web visit, and the app does not
/// reload while a declaration is waiting.
final Map<String, PendingDeclaration> _pending = {};

void rememberDeclaration({
  required String token,
  required double amount,
  required List<String> billIds,
  required double expectedTotal,
}) {
  if (token.isEmpty || amount <= 0) return;
  _pending[token] = PendingDeclaration(
    amount: amount,
    billIds: List<String>.from(billIds),
    expectedTotal: expectedTotal,
    at: DateTime.now(),
  );
}

PendingDeclaration? readDeclaration(String token) => _pending[token];

void clearDeclaration(String token) => _pending.remove(token);
