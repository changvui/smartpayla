import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

/// Opens WhatsApp with a prefilled message.
///
/// The `whatsapp://` scheme does not exist in a browser, so `canLaunchUrl` always
/// returns false there and the old code wrongly reported "not installed". On the
/// web the click-to-chat URL is used instead: the browser hands it to the
/// installed app, and it degrades to WhatsApp Web on a desktop.
Future<bool> openWhatsApp(String text, {String? phone}) async {
  final encoded = Uri.encodeComponent(text);
  final digits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  final webUri = Uri.parse(
    digits.isEmpty
        ? 'https://wa.me/?text=$encoded'
        : 'https://wa.me/$digits?text=$encoded',
  );

  if (kIsWeb) {
    try {
      return await launchUrl(webUri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }

  final appUri = Uri.parse(
    digits.isEmpty
        ? 'whatsapp://send?text=$encoded'
        : 'whatsapp://send?phone=$digits&text=$encoded',
  );
  try {
    if (await canLaunchUrl(appUri)) {
      return await launchUrl(appUri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // Fall through to the https URL, which also opens the app on Android.
  }

  try {
    return await launchUrl(webUri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
