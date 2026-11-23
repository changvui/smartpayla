import 'package:web/web.dart' as web;

/// Opens the checkout in a new tab instead of replacing the current page.
///
/// A same-tab navigation destroys the page it came from, so the browser's Back
/// button then lands on whatever was there before - the application, or its
/// login screen. A new tab starts with no history at all.

/// Opens an empty tab *inside the click*, before any network call.
///
/// `window.open` is only honoured while the browser still considers the click to
/// be in progress. Creating the Stripe session takes a moment, so the tab has to
/// be opened first and pointed at the URL afterwards; opening it after the await
/// is silently blocked, which is why the earlier version fell back to the same
/// tab.
Object? prepareCheckoutTab() {
  try {
    return web.window.open('about:blank', '_blank');
  } catch (_) {
    return null;
  }
}

/// Points a tab opened by [prepareCheckoutTab] at the checkout URL.
bool loadInCheckoutTab(Object? tab, String url) {
  try {
    final window = tab as web.Window?;
    if (window == null) return false;
    window.location.href = url;
    return true;
  } catch (_) {
    return false;
  }
}

/// Leaves the app and loads [url] in the same tab, used when a popup is blocked.
Future<bool> navigateTo(String url) async {
  try {
    web.window.location.href = url;
    return true;
  } catch (_) {
    return false;
  }
}

/// Makes the *current* history entry the statement URL.
///
/// The statement is often opened inside the application, where the address bar
/// still says `?tab=0`. Navigating to the provider from there leaves the app (or
/// its login screen) one Back away. Rewriting the entry first means the page
/// behind the checkout is the statement itself.
void ensureStatementUrl(String token) {
  if (token.isEmpty) return;
  try {
    web.window.history.replaceState(null, '', '?s=$token');
  } catch (_) {
    // A sandboxed iframe may forbid it; the customer still pays.
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

/// True when this window was opened by script (window.open), which is how the
/// checkout tab is created. A tab that was opened by us may also be closed by us.
bool wasOpenedAsPopup() {
  try {
    return web.window.opener != null;
  } catch (_) {
    return false;
  }
}

/// Sends the tab back to the page that opened it and closes it, used when the
/// customer cancels. `history.back` first, so a browser that refuses to close a
/// tab still shows something sensible instead of a blank page.
void cancelAndCloseTab() {
  try {
    if (web.window.history.length > 1) web.window.history.back();
  } catch (_) {
    // Ignore: closing below is what matters.
  }
  try {
    web.window.close();
  } catch (_) {
    // Staying on the statement is an acceptable outcome.
  }
}

/// Closes a tab that this page opened. Script-opened tabs may be closed by their
/// opener, which is how the checkout tab goes away once the payment is seen.
void closeTabHandle(Object? tab) {
  try {
    (tab as web.Window?)?.close();
  } catch (_) {
    // The tab stays open; the customer can close it.
  }
}
