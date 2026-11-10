import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Native implementation.
///
/// Three shapes can reach this function:
///   * `https://…`  – a Firebase Storage download URL (the normal case)
///   * `data:image/…;base64,…` – a photo attached earlier in the browser
///   * a plain file path – an older record, or a photo not uploaded yet
ImageProvider platformImageProvider(String path) {
  if (path.startsWith('http')) return NetworkImage(path);
  if (path.startsWith('data:')) return MemoryImage(_decodeDataUri(path));
  return FileImage(File(path));
}

Widget platformImage(String path, {BoxFit fit = BoxFit.cover}) {
  if (path.startsWith('http')) return Image.network(path, fit: fit);
  if (path.startsWith('data:')) {
    return Image.memory(_decodeDataUri(path), fit: fit);
  }
  return Image.file(File(path), fit: fit);
}

Uint8List _decodeDataUri(String dataUri) {
  final comma = dataUri.indexOf(',');
  final payload = comma >= 0 ? dataUri.substring(comma + 1) : dataUri;
  return base64Decode(payload);
}
