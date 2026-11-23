/// Remembers which statement the checkout belongs to.
///
/// A provider redirect should come back with `?s=<token>`, but a redirect can
/// lose the query (a sanitising browser, a rewritten URL, a provider that only
/// keeps the path). The token is therefore also stored in the browser before the
/// customer leaves, so the return can be rebuilt instead of guessed.
library;

export 'pending_token_web.dart' if (dart.library.io) 'pending_token_io.dart';
