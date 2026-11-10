import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'scanned_bill.dart';

/// Native engine: on-device OCR with Google ML Kit.
///
/// This is the engine described in the report (§2.2.5). It runs completely
/// offline, needs no API key and no server, and the photo never leaves the
/// device. The trade-off is accuracy: ML Kit returns raw lines of text, so the
/// fields are recovered by the heuristics in `scanned_bill.dart` rather than by
/// a language model that understands the document.
///
/// The web build cannot use this — `receipt_scanner.dart` selects the Worker
/// based implementation there.
class ReceiptScanner {
  static bool get isConfigured => true;

  Future<ScannedBill> scan({
    required Uint8List bytes,
    required String mimeType,
    String? path,
  }) async {
    if (path == null || path.isEmpty) {
      throw const ReceiptScanException(
        'The picked image has no file path, so ML Kit cannot read it.',
      );
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final input = InputImage.fromFilePath(path);
      final recognised = await recognizer.processImage(input);
      final text = recognised.text.trim();
      if (text.isEmpty) {
        throw const ReceiptScanException(
          'No text was found in that photo. Try a sharper picture with the '
          'bill flat and well lit.',
        );
      }
      return parseScannedText(text);
    } catch (error) {
      if (error is ReceiptScanException) rethrow;
      throw ReceiptScanException('ML Kit could not read the image: $error');
    } finally {
      await recognizer.close();
    }
  }
}
