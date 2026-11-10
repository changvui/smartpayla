import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'; // 👈 THIS IS THE NEW IMPORT
import '../data/firebase_config.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  if (!FirebaseRuntime.initialized) {
    return Stream.value(null); 
  }
  return FirebaseAuth.instance.authStateChanges();
});

class AuthController {
  Future<String?> login(String email, String password) async {
    if (!FirebaseRuntime.initialized) return 'Firebase is not initialized. Did you run the script?';
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      return null; 
    } on FirebaseAuthException catch (e) {
      debugPrint("LOGIN ERROR CODE: ${e.code}"); 
      debugPrint("LOGIN ERROR MESSAGE: ${e.message}");
      return e.message; 
    } catch (e) {
      debugPrint("LOGIN ERROR: $e");
      return e.toString();
    }
  }

  Future<String?> register(String email, String password) async {
    if (!FirebaseRuntime.initialized) return 'Firebase is not initialized. Did you run the script?';
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      await FirebaseAuth.instance.signOut(); 
      return null; 
    } on FirebaseAuthException catch (e) {
      // This will print the exact error code to your terminal
      debugPrint("REGISTER ERROR CODE: ${e.code}"); 
      debugPrint("REGISTER ERROR MESSAGE: ${e.message}");
      return e.message;
    } catch (e) {
      debugPrint("REGISTER ERROR: $e");
      return e.toString();
    }
  }

  /// Sign in with a Google account.
  ///
  /// Returns `null` on success, an error message on failure, and `null` when
  /// the user simply closes the Google popup (treated as "cancelled").
  ///
  /// On the web this uses [FirebaseAuth.signInWithPopup]. On Android/iOS the
  /// Firebase plugin cannot open the popup, so the `google_sign_in` package is
  /// required — see docs/FIREBASE.md. Until that package is added, the method
  /// reports a friendly message instead of crashing.
  Future<String?> signInWithGoogle() async {
    if (!FirebaseRuntime.initialized) {
      return 'Firebase is not initialized. Did you run the script?';
    }

    if (!kIsWeb) {
      return 'Google sign-in is enabled on the web build. '
          'On Android/iOS add the google_sign_in package (see docs/FIREBASE.md).';
    }

    try {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});

      try {
        final credential =
            await FirebaseAuth.instance.signInWithPopup(provider);
        if (credential.user == null) return 'Google sign-in was cancelled.';
        return null;
      } on FirebaseAuthException catch (popupError) {
        // Mobile browsers refuse popups. Fall back to a full-page redirect;
        // when the browser comes back, authStateChanges() emits the user and
        // AuthGate moves on by itself.
        final blocked = popupError.code == 'popup-blocked' ||
            popupError.code == 'operation-not-supported-in-this-environment';
        if (!blocked) rethrow;

        debugPrint('Popup blocked (${popupError.code}); using redirect flow.');
        await FirebaseAuth.instance.signInWithRedirect(provider);
        return null;
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('GOOGLE SIGN-IN ERROR CODE: ${e.code}');
      debugPrint('GOOGLE SIGN-IN ERROR MESSAGE: ${e.message}');
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') {
        return null; // user closed the popup, not an error
      }
      return e.message;
    } catch (e) {
      debugPrint('GOOGLE SIGN-IN ERROR: $e');
      return e.toString();
    }
  }

  Future<String?> sendPasswordReset(String email) async {
    if (!FirebaseRuntime.initialized) return 'Firebase is not initialized. Did you run the script?';
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      return null; // Success
    } on FirebaseAuthException catch (e) {
      debugPrint("RESET PASSWORD ERROR CODE: ${e.code}"); 
      return e.message;
    } catch (e) {
      debugPrint("RESET PASSWORD ERROR: $e");
      return e.toString();
    }
  }
  
  Future<void> logout() async {
    if (FirebaseRuntime.initialized) {
      await FirebaseAuth.instance.signOut();
    }
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController();
});