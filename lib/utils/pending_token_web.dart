import 'package:web/web.dart' as web;

const _key = 'smartpayla_pending_statement';

/// Called before the customer leaves for the provider.
void rememberPendingToken(String token) {
  if (token.isEmpty) return;
  try {
    web.window.localStorage.setItem(_key, token);
  } catch (_) {
    // Private mode can refuse storage; the query string still carries the token.
  }
}

/// The token of the statement that started a checkout, if one is pending.
String? readPendingToken() {
  try {
    return web.window.localStorage.getItem(_key);
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
