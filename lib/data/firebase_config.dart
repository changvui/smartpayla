import 'package:firebase_core/firebase_core.dart';

class FirebaseRuntime {
  FirebaseRuntime._();

  static bool initialized = false;
}

/// Configuration is supplied at build/run time so no secret has to be committed.
///
/// Example:
/// flutter run -d chrome \
///   --dart-define=FIREBASE_API_KEY=... \
///   --dart-define=FIREBASE_APP_ID=... \
///   --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
///   --dart-define=FIREBASE_PROJECT_ID=...
class FirebaseConfig {
  FirebaseConfig._();

  static const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const messagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
  static const storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const userId =
      String.fromEnvironment('APP_USER_ID', defaultValue: 'demo-agent');

  static bool get configured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  static FirebaseOptions get options => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
        authDomain:
            authDomain.isEmpty ? '$projectId.firebaseapp.com' : authDomain,
        storageBucket:
            storageBucket.isEmpty ? '$projectId.appspot.com' : storageBucket,
      );
}
