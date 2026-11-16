/// Saving the payment QR to the device. The browser can download a `data:` URI
/// directly; on native there is no gallery plugin in this prototype.
library;

export 'qr_saver_web.dart' if (dart.library.io) 'qr_saver_io.dart';
