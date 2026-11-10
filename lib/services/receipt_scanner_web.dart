import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'scanned_bill.dart';

/// Web engine: reads the bill through the SmartPayLA Worker.
///
/// ML Kit cannot run in a browser, so the web build delegates to the Worker
/// (which holds the vision-model key). Native builds use
/// `receipt_scanner_io.dart` instead — see `receipt_scanner.dart`.
class ReceiptScanner {
  static const _proxyUrl = String.fromEnvironment('REMINDER_PROXY_URL');

  static const _maxBase64Length = 2000000;

  static bool get isConfigured => _proxyUrl.trim().isNotEmpty;

  Future<ScannedBill> scan({
    required Uint8List bytes,
    required String mimeType,
    String? path,
  }) async {
    if (!isConfigured) {
      throw const ReceiptScanException(
        'Receipt scanning is not configured. Run with '
        '--dart-define=REMINDER_PROXY_URL=<worker url>.',
      );
    }
    if (bytes.isEmpty) {
      throw const ReceiptScanException('The selected image is empty.');
    }

    final image = base64Encode(bytes);
    if (image.length > _maxBase64Length) {
      throw const ReceiptScanException(
        'That photo is too large. Try again — SmartPayLA compresses it first.',
      );
    }

    final base = _proxyUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final endpoint = base.endsWith('/scan') ? base : '$base/scan';

    late final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'image': image, 'mimeType': mimeType}),
          )
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw ReceiptScanException('Could not reach the scan service: $e');
    }

    if (response.statusCode != 200) {
      final body = response.body;
      throw ReceiptScanException(
        'Scan service error ${response.statusCode}: '
        '${body.length > 180 ? '${body.substring(0, 180)}…' : body}',
      );
    }

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw const ReceiptScanException(
        'The scan service returned invalid JSON.',
      );
    }

    final bill = decoded['bill'];
    if (bill is! Map) {
      final message = decoded['error'];
      throw ReceiptScanException(
        message is String ? message : 'The scan service returned no result.',
      );
    }

    return ScannedBill.fromMap(Map<String, dynamic>.from(bill));
  }
}
