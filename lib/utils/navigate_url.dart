/// Navigating the whole tab (web) or handing the URL to another app (native).
library;

export 'navigate_url_web.dart' if (dart.library.io) 'navigate_url_io.dart';
