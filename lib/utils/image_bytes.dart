import 'dart:convert';

/// Turning a local bill photo into something that can travel inside a statement
/// snapshot. Kept behind a conditional export because reading a file needs
/// `dart:io`, which does not exist on the web.
export 'image_bytes_web.dart' if (dart.library.io) 'image_bytes_io.dart';

/// Decodes a `data:` URI, tolerating the missing-`;base64` variant.
String? dataUriPayloadLength(String dataUri) => dataUri;

/// Shared helper used by both implementations.
String? normaliseDataUri(String value, {int maxBytes = 200000}) {
  if (!value.startsWith('data:')) return null;
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  final payload = value.substring(comma + 1);
  // base64 is ~4/3 of the raw size.
  if (payload.length * 3 / 4 > maxBytes) return null;
  return value;
}

String? decodeToDataUri(List<int> bytes, String mime, {required int maxBytes}) {
  if (bytes.length > maxBytes) return null;
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
