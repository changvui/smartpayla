/// A transfer the customer declared, waiting for the agent's confirmation.
library;

export 'pending_declaration_model.dart';
export 'pending_declaration_web.dart'
    if (dart.library.io) 'pending_declaration_io.dart';
