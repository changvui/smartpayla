import 'dart:io';
import 'dart:typed_data';

import 'image_bytes.dart';

/// Native implementation: a bill photo is either a `data:` URI (recorded in the
/// browser earlier) or a file path in the app documents directory.
Future<String?> evidenceDataUri(String? path, {int maxBytes = 200000}) async {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('data:')) return normaliseDataUri(path, maxBytes: maxBytes);
  if (path.startsWith('http')) return null; // remote URL: keep the link only

  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    final mime = path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    return decodeToDataUri(bytes, mime, maxBytes: maxBytes);
  } catch (_) {
    return null;
  }
}

/// Unused on native, kept so the API matches the web implementation.
Uint8List? evidenceBytes(String? path) => null;
