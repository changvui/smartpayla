import 'package:url_launcher/url_launcher.dart';

/// Native builds hand the checkout URL to the browser: the customer leaves the
/// app, pays, and returns through the success URL.

/// Native has no tabs, so nothing is prepared and the URL opens in the browser.
Object? prepareCheckoutTab() => null;

/// Native cannot load into a prepared tab.
bool loadInCheckoutTab(Object? tab, String url) => false;

Future<bool> navigateTo(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Native has no address bar to rewrite.
void ensureStatementUrl(String token) {}

/// Native builds stay on the statement; there is no tab to close.
void closeCurrentTab() {}

/// Native builds are never a popup window.
bool wasOpenedAsPopup() => false;

/// Native builds have no tab to close; the back gesture returns to the app.
void cancelAndCloseTab() {}
