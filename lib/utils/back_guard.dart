/// Keeps a customer on the statement page.
///
/// The statement and the agent application are the same web bundle, so the
/// browser's Back button can walk from a customer's link back into whatever the
/// device opened before it - which, on an agent's own phone, is the agent
/// dashboard. Least privilege means the customer page must not be a doorway into
/// that view, so while the statement is open each Back is absorbed and the
/// history entry is pushed again.
library;

export 'back_guard_web.dart' if (dart.library.io) 'back_guard_io.dart';
