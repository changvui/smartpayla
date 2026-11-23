import 'package:web/web.dart' as web;

/// Rewrites the address bar to look like a hosted checkout page.
///
/// `replaceState` is used rather than `pushState` so the customer's back button
/// does not walk through the checkout twice, and nothing is loaded from the
/// network: the statement is a single-page app, and this only changes the label
/// the customer reads.
/// Removes `paid` and `session_id` once the return has been handled, so a
/// refresh does not try to confirm the same payment twice.
void clearPaymentParams({required String token}) {
  if (token.isEmpty) return;
  try {
    web.window.history.replaceState(null, '', '?s=$token');
  } catch (_) {
    // Non-critical: the guard in the page also prevents a second confirmation.
  }
}

void setCheckoutUrl({required String token, required bool inCheckout}) {
  if (token.isEmpty) return;
  try {
    final query = inCheckout ? '?s=$token&checkout=1' : '?s=$token';
    web.window.history.replaceState(null, '', query);
  } catch (_) {
    // An embedded webview can refuse history changes; the page still works.
  }
}
