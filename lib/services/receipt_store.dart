// Persists an attached bill photo and returns the string to store in
// `Transaction.receiptImagePath`.
//
// * Android / iOS -> `receipt_store_io.dart`: the picked file is copied into the
//   app's documents folder, so clearing the cache cannot delete it.
// * Web -> `receipt_store_web.dart`: there is no filesystem, so the bytes are
//   inlined as a small JPEG `data:` URI, which survives a page reload.
export 'receipt_store_web.dart' if (dart.library.io) 'receipt_store_io.dart';
