import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _listener;

/// Keeps the customer on the statement page, whatever the browser tries.
///
/// Two layers, because one is not enough:
///
/// 1. `replaceState` overwrites the history entry that the statement was opened
///    from. When a link is pasted or opened in the same tab, that entry is the
///    agent dashboard; replacing it means the first Back can no longer land
///    there.
/// 2. A `popstate` listener answers every Back with another `pushState`, so the
///    document never changes and the customer stays on the statement - including
///    when the previous entry is the provider's checkout page.
///
/// This is not the security boundary; Firestore rules are. It removes the
/// obvious disclosure of an agent dashboard behind a shared link.
void installCustomerBackGuard() {
  if (_listener != null) return;
  try {
    final href = web.window.location.href;

    // 1. Take over the entry the statement was opened from.
    web.window.history.replaceState(null, '', href);

    // 2. Absorb every subsequent Back.
    void handler(web.Event event) {
      try {
        web.window.history.pushState(null, '', href);
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
