// Platform-safe image helpers.
//
// `dart:io` does not exist on the web, so any file that imports it cannot be
// compiled by `flutter build web` / `flutter run -d chrome`. This library
// picks the right implementation at compile time:
//
//   * native (Android / iOS / desktop) -> platform_image_io.dart
//   * web (JS or WASM)                -> platform_image_web.dart
//
// Both files expose the same two functions:
//   * ImageProvider platformImageProvider(String path)
//   * Widget platformImage(String path, {BoxFit fit})
export 'platform_image_web.dart' if (dart.library.io) 'platform_image_io.dart';
