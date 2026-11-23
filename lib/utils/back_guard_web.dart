import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _listener;

/// Absorbs Back while the customer statement is on screen.
///
/// Each popstate is answered with another pushState, so the visible page never
/// changes: the customer cannot reach a page that was open before the link.
/// This is a guard, not a security boundary - the agent's data is still
/// protected by Firestore rules - but it stops the obvious disclosure of an
/// agent dashboard behind a shared link.
void installCustomerBackGuard() {
  if (_listener != null) return;
  try {
    web.window.history.pushState(null, '', web.window.location.href);
    void handler(web.Event event) {
      try {
        web.window.history.pushState(null, '', web.window.location.href);
      } catch (_) {
        // Nothing to push: the guard simply does not apply.
      }
    }

    final listener = handler.toJS;
    _listener = listener;
    web.window.addEventListener('popstate', listener);
  } catch (_) {
    _listener = null;
  }
}

void removeCustomerBackGuard() {
  final listener = _listener;
  if (listener == null) return;
  try {
    web.window.removeEventListener('popstate', listener);
  } catch (_) {
    // The page is going away anyway.
  }
  _listener = null;
}
