import 'package:web/web.dart' as web;

const _key = 'smartpayla_pending_statement';
const _maxAge = Duration(hours: 2);

/// Called before the customer leaves for the provider.
///
/// The value also carries a timestamp: a stale token must never pull an agent
/// into a customer's statement days later.
void rememberPendingToken(String token) {
  if (token.isEmpty) return;
  try {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    web.window.localStorage.setItem(_key, '$token|$stamp');
  } catch (_) {
    // Private mode can refuse storage; the query string still carries the token.
  }
}

/// The token of the statement that started a checkout, if it is still recent.
String? readPendingToken() {
  try {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null || raw.isEmpty) return null;
    final separator = raw.lastIndexOf('|');
    if (separator <= 0) return null;
    final token = raw.substring(0, separator);
    final stamp = int.tryParse(raw.substring(separator + 1));
    if (stamp == null) return null;
    final age = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(stamp),
    );
    if (age > _maxAge) {
      clearPendingToken();
      return null;
    }
    return token;
  } catch (_) {
    return null;
  }
}

void clearPendingToken() {
  try {
    web.window.localStorage.removeItem(_key);
  } catch (_) {
    // Nothing to clear.
  }
}
