/// Lets the checkout tab tell the statement tab that the payment went through.
///
/// The customer pays in a second tab, so the tab that shows the statement is
/// never navigated away from and never sees the provider's return URL. Without a
/// channel between them it would keep showing an unpaid bill after the money has
/// arrived.
library;

export 'payment_bridge_web.dart' if (dart.library.io) 'payment_bridge_io.dart';
