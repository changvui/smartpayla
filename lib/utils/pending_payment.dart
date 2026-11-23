/// A payment the gateway confirmed but the ledger has not written yet.
///
/// The published statement is a snapshot that only the agent can rewrite, so a
/// customer who pays while the agent is offline would otherwise see the old
/// balance again after any reload. This remembers the amount locally until the
/// snapshot catches up.
library;

export 'pending_payment_web.dart' if (dart.library.io) 'pending_payment_io.dart';
