import 'package:web/web.dart' as web;

/// Opens the checkout in a new tab instead of replacing the current page.
///
/// A same-tab navigation destroys the page it came from: if the statement was
/// being previewed inside the application, the browser's Back button then
/// returns to the agent dashboard, which is exactly what a customer must never
/// see. A new tab starts with an empty history, so Back there has nowhere to go;
/// Stripe's success URL brings that tab back to the statement.
///
/// A blocked popup falls back to the same tab, because a checkout the customer
/// cannot open is worse than a Back button that needs care.
Future<bool> navigateTo(String url) async {
  try {
    final opened = web.window.open(url, '_blank');
    if (opened != null) return true;
  } catch (_) {
    // Fall through to the same-tab navigation.
  }
  try {
    web.window.location.href = url;
    return true;
  } catch (_) {
    return false;
  }
}


/// Closes the tab that the app opened for the checkout. Only a tab opened by a
/// script may close itself, which is exactly the case here.
void closeCurrentTab() {
  try {
    web.window.close();
  } catch (_) {
    // Some browsers refuse; the page then stays on "payment confirmed".
  }
}
