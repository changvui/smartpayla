// Picks the receipt-scanning engine at compile time.
//
// * Android / iOS / desktop -> receipt_scanner_io.dart, on-device ML Kit
//   (offline, no key, matches the report's §2.2.5).
// * Web (JS or WASM) -> receipt_scanner_web.dart, the SmartPayLA Worker,
//   because ML Kit has no browser implementation.
//
// Both files expose the same `ReceiptScanner` API, so screens import only this
// file and never care which platform they run on.
export 'receipt_scanner_web.dart'
    if (dart.library.io) 'receipt_scanner_io.dart';
