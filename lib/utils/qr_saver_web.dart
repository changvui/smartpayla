import 'package:web/web.dart' as web;

/// Downloads a `data:` URI as a file in the browser. Returns false when the
/// download could not be triggered.
bool saveDataUri(String dataUri, String fileName) {
  try {
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = dataUri;
    anchor.download = fileName;
    anchor.style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    return true;
  } catch (_) {
    return false;
  }
}
