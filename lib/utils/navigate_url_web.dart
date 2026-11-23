import 'package:web/web.dart' as web;

/// Leaves the app and loads [url] in the same tab.
///
/// A checkout must replace the merchant page, not open a second tab: the
/// provider's success URL comes back to the statement, and that only works if
/// the statement was the page that navigated away.
Future<bool> navigateTo(String url) async {
  try {
    web.window.location.href = url;
    return true;
  } catch (_) {
    return false;
  }
}
