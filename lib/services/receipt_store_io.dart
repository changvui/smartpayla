import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Native implementation: copy the picked photo into `<documents>/receipts/`.
///
/// `image_picker` hands back a file in the cache/temp directory, which the OS is
/// free to delete at any time. Copying it into the documents directory gives it
/// the same lifetime as the app's own data.
class ReceiptStore {
  const ReceiptStore();

  Future<String> store(XFile file) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory('${documents.path}/receipts');
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }

    final extension = _extensionOf(file.path);
    final name = 'bill_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final target = '${folder.path}/$name';

    final copied = await File(file.path).copy(target);
    return copied.path;
  }

  String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    if (ext.length > 5) return 'jpg';
    return ext == 'jpeg' ? 'jpg' : ext;
  }
}
