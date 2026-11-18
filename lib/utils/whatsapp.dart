import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

typedef CountryDialCode = Map<String, String>;

const List<CountryDialCode> kCountryDialCodes = [
  {'code': '+60', 'label': '🇲🇾 +60 (MY)'},
  {'code': '+65', 'label': '🇸🇬 +65 (SG)'},
  {'code': '+62', 'label': '🇮🇩 +62 (ID)'},
  {'code': '+66', 'label': '🇹🇭 +66 (TH)'},
  {'code': '+673', 'label': '🇧🇳 +673 (BN)'},
  {'code': '+84', 'label': '🇻🇳 +84 (VN)'},
  {'code': '+63', 'label': '🇵🇭 +63 (PH)'},
  {'code': '+86', 'label': '🇨🇳 +86 (CN)'},
  {'code': '+852', 'label': '🇭🇰 +852 (HK)'},
  {'code': '+886', 'label': '🇹🇼 +886 (TW)'},
  {'code': '+91', 'label': '🇮🇳 +91 (IN)'},
  {'code': '+44', 'label': '🇬🇧 +44 (UK)'},
  {'code': '+1', 'label': '🇺🇸 +1 (US)'},
];

({String dialCode, String localNumber}) splitPhoneForDropdown(String rawPhone) {
  final trimmed = rawPhone.trim();
  if (trimmed.isEmpty) {
    return (dialCode: '+60', localNumber: '');
  }

  final sortedCodes = kCountryDialCodes.map((e) => e['code']!).toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  for (final code in sortedCodes) {
    final digitsOnlyCode = code.replaceAll('+', '');
    if (trimmed.startsWith(code)) {
      return (
        dialCode: code,
        localNumber: trimmed.substring(code.length).trim(),
      );
    }
    if (trimmed.startsWith(digitsOnlyCode) && trimmed.length > 9) {
      return (
        dialCode: code,
        localNumber: trimmed.substring(digitsOnlyCode.length).trim(),
      );
    }
  }

  return (dialCode: '+60', localNumber: trimmed);
}

String formatPhoneWithCountryCode(String dialCode, String localInput) {
  var digits = localInput.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';

  if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return '$dialCode$digits';
}

String normalizePhoneForWhatsApp(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  if (trimmed.startsWith('+')) {
    return trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  }

  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';

  if (digits.startsWith('0')) {
    return '6$digits';
  }
  return digits;
}

/// Valid Dart signature that works with BOTH:
/// - openWhatsApp('0123456789', text: 'Hi')
/// - openWhatsApp(phone: '0123456789', text: 'Hi')
Future<bool> openWhatsApp(
  String text, {
  String? phone,
}) async {
  final rawPhone = phone ?? '';
  final cleanPhone = normalizePhoneForWhatsApp(rawPhone);
  final encodedText = text.trim().isNotEmpty
      ? '?text=${Uri.encodeComponent(text.trim())}'
      : '';

  final uri = cleanPhone.isNotEmpty
      ? Uri.parse('https://wa.me/$cleanPhone$encodedText')
      : Uri.parse('https://wa.me/$encodedText');

  try {
    return await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

Future<bool> openPhoneDialer(String phone) async {
  final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (clean.isEmpty) return false;

  final uri = Uri(scheme: 'tel', path: clean);

  try {
    return await launchUrl(
      uri,
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}