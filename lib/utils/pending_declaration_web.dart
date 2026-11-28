import 'package:web/web.dart' as web;

import 'pending_declaration_model.dart';

const _maxAge = Duration(hours: 48);

String _key(String token) => 'smartpayla_declared_$token';

void rememberDeclaration({
  required String token,
  required double amount,
  required List<String> billIds,
  required double expectedTotal,
}) {
  if (token.isEmpty || amount <= 0) return;
  try {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    web.window.localStorage.setItem(
      _key(token),
      '$amount|${billIds.join(',')}|$expectedTotal|$stamp',
    );
  } catch (_) {
    // Private mode: the page simply falls back to the snapshot.
  }
}

PendingDeclaration? readDeclaration(String token) {
  if (token.isEmpty) return null;
  try {
    final raw = web.window.localStorage.getItem(_key(token));
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.length != 4) return null;
    final amount = double.tryParse(parts[0]);
    final expected = double.tryParse(parts[2]);
    final stamp = int.tryParse(parts[3]);
    if (amount == null || expected == null || stamp == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(stamp);
    if (DateTime.now().difference(at) > _maxAge) {
      clearDeclaration(token);
      return null;
    }
    final ids = parts[1].isEmpty ? <String>[] : parts[1].split(',');
    return PendingDeclaration(
      amount: amount,
      billIds: ids,
      expectedTotal: expected,
      at: at,
    );
  } catch (_) {
    return null;
  }
}

void clearDeclaration(String token) {
  if (token.isEmpty) return;
  try {
    web.window.localStorage.removeItem(_key(token));
  } catch (_) {
    // Nothing to clear.
  }
}
