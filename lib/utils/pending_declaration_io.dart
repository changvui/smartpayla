import 'pending_declaration_model.dart';

/// Kept in memory on native: a statement is a web visit, and the app does not
/// reload while a declaration is waiting.
final Map<String, List<PendingDeclaration>> _pending = {};

void addDeclaration({
  required String token,
  required double amount,
  required List<String> billIds,
  required double expectedTotal,
}) {
  if (token.isEmpty || amount <= 0) return;
  (_pending[token] ??= []).add(
    PendingDeclaration(
      amount: amount,
      billIds: List<String>.from(billIds),
      expectedTotal: expectedTotal,
      at: DateTime.now(),
    ),
  );
}

List<PendingDeclaration> readDeclarations(String token) =>
    List<PendingDeclaration>.unmodifiable(_pending[token] ?? const []);

void clearAppliedDeclarations({
  required String token,
  required double snapshotTotal,
}) {
  final list = _pending[token];
  if (list == null) return;
  list.removeWhere((d) => snapshotTotal <= d.expectedTotal + 0.01);
  if (list.isEmpty) _pending.remove(token);
}

void clearDeclarations(String token) => _pending.remove(token);
