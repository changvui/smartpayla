import 'dart:convert';

import 'package:web/web.dart' as web;

import 'pending_declaration_model.dart';

const _maxAge = Duration(hours: 48);

String _key(String token) => 'smartpayla_declared_$token';

/// Declarations kept as a list: a customer may pay the same bill in several
/// parts, and each declaration has to survive until the agent confirms it.
void addDeclaration({
  required String token,
  required double amount,
  required List<String> billIds,
  required double expectedTotal,
}) {
  if (token.isEmpty || amount <= 0) return;
  try {
    final entries = _read(token)..add(<String, dynamic>{
        'amount': amount,
        'billIds': billIds,
        'expected': expectedTotal,
        'stamp': DateTime.now().millisecondsSinceEpoch,
      });
    web.window.localStorage.setItem(_key(token), jsonEncode(entries));
  } catch (_) {
    // Private mode: the page simply falls back to the snapshot.
  }
}

List<PendingDeclaration> readDeclarations(String token) {
  if (token.isEmpty) return const [];
  try {
    final raw = web.window.localStorage.getItem(_key(token));
    if (raw == null || raw.isEmpty) return const [];
    final list = (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((entry) {
          return PendingDeclaration(
            amount: (entry['amount'] as num?)?.toDouble() ?? 0,
            billIds: (entry['billIds'] as List? ?? const [])
                .map((e) => e.toString())
                .toList(),
            expectedTotal: (entry['expected'] as num?)?.toDouble() ?? 0,
            at: DateTime.fromMillisecondsSinceEpoch(
              (entry['stamp'] as num?)?.toInt() ?? 0,
            ),
          );
        })
        .where((d) => d.amount > 0 && DateTime.now().difference(d.at) < _maxAge)
        .toList();
    return list;
  } catch (_) {
    return const [];
  }
}

/// Drops the declarations the snapshot has caught up with: once the total is at
/// or below what the customer expected after paying, that money reached the
/// ledger and the notice should disappear.
void clearAppliedDeclarations({
  required String token,
  required double snapshotTotal,
}) {
  if (token.isEmpty) return;
  try {
    final entries = _read(token);
    final kept = entries.where((entry) {
      final expected = (entry['expected'] as num?)?.toDouble() ?? 0;
      return snapshotTotal > expected + 0.01;
    }).toList();
    if (kept.length == entries.length) return;
    if (kept.isEmpty) {
      web.window.localStorage.removeItem(_key(token));
    } else {
      web.window.localStorage.setItem(_key(token), jsonEncode(kept));
    }
  } catch (_) {
    // Nothing to clear.
  }
}

void clearDeclarations(String token) {
  if (token.isEmpty) return;
  try {
    web.window.localStorage.removeItem(_key(token));
  } catch (_) {
    // Nothing to clear.
  }
}

List<Map<String, dynamic>> _read(String token) {
  try {
    final raw = web.window.localStorage.getItem(_key(token));
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List).whereType<Map>().map((e) {
      return <String, dynamic>{
        'amount': (e['amount'] as num?)?.toDouble() ?? 0,
        'billIds': (e['billIds'] as List? ?? const []).map((x) => x.toString()).toList(),
        'expected': (e['expected'] as num?)?.toDouble() ?? 0,
        'stamp': (e['stamp'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  } catch (_) {
    return [];
  }
}
