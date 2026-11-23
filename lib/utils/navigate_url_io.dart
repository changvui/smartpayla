import 'package:url_launcher/url_launcher.dart';

/// Native builds hand the checkout URL to the browser: the customer leaves the
/// app, pays, and returns through the success URL.
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


/// Native builds stay on the statement; there is no tab to close.
void closeCurrentTab() {}
