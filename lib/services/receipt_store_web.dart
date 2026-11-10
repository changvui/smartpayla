import 'dart:convert';

import 'package:image_picker/image_picker.dart';

/// Web implementation: there is no writable filesystem, so the compressed bytes
/// are inlined as a `data:` URI. It is bigger than a path, but it survives a
/// page reload — a `blob:` URL does not.
class ReceiptStore {
  const ReceiptStore();

  Future<String> store(XFile file) async {
    final bytes = await file.readAsBytes();
    final mime = file.mimeType ?? 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }
}
