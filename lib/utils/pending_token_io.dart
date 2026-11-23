/// Native builds never lose the statement: the checkout returns through the same
/// app, so nothing has to be remembered.
void rememberPendingToken(String token) {}

String? readPendingToken() => null;

void clearPendingToken() {}
