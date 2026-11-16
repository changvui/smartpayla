import 'dart:typed_data';

import 'image_bytes.dart';

/// Web implementation: the browser cannot read an arbitrary file path, so only
/// a `data:` URI (which is what the web build stores) can be embedded.
Future<String?> evidenceDataUri(String? path, {int maxBytes = 200000}) async {
  if (path == null || path.isEmpty) return null;
  return normaliseDataUri(path, maxBytes: maxBytes);
}

Uint8List? evidenceBytes(String? path) => null;
