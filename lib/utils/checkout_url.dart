/// Changes the browser address bar while the demo checkout is open, so the
/// customer really sees a different page - the way a hosted checkout returns to
/// the merchant after payment. Native builds have no address bar, so this is a
/// no-op there.
library;

export 'checkout_url_web.dart' if (dart.library.io) 'checkout_url_io.dart';
