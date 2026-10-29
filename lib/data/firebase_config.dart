import 'package:firebase_auth/firebase_auth.dart';
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

  /// Used only when there is no signed-in Firebase user (test-mode rules).
  static const demoUserId =
      String.fromEnvironment('APP_USER_ID', defaultValue: 'demo-agent');

  /// The real owner of the transaction data.
  ///
  /// Once the partner authentication module signs a user in, its UID wins.
  /// Until then, the standalone prototype falls back to APP_USER_ID.
  static String get userId {
    if (!FirebaseRuntime.initialized) return demoUserId;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {
      // Auth is not available yet; keep the local/demo scope.
    }
    return demoUserId;
  }

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
