import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Web implementation.
///
/// A freshly picked photo is a `blob:` URL; a photo that was attached on this
/// browser earlier is stored as a `data:` URI (base64) so it survives a page
/// reload. Both are handled here; no `dart:io` on purpose.
ImageProvider platformImageProvider(String path) {
  if (path.startsWith('data:')) return MemoryImage(_decodeDataUri(path));
  return NetworkImage(path);
}

Widget platformImage(String path, {BoxFit fit = BoxFit.cover}) {
  if (path.startsWith('data:')) {
    return Image.memory(_decodeDataUri(path), fit: fit);
  }
  return Image.network(path, fit: fit);
}

Uint8List _decodeDataUri(String dataUri) {
  final comma = dataUri.indexOf(',');
  final payload = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
  return base64Decode(payload);
}
