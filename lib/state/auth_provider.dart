import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart'; // kIsWeb + debugPrint
import 'package:google_sign_in/google_sign_in.dart';
import '../data/firebase_config.dart';

final authStateProvider = StreamProvider<User?>((ref) {
  if (!FirebaseRuntime.initialized) {
    return Stream.value(null); 
  }
  // userChanges() also fires after reload(), which is how a freshly verified
  // e-mail address reaches the UI without restarting the app.
  return FirebaseAuth.instance.userChanges();
});

/// Returned by [AuthController.login] when the password is correct but the
/// account has not clicked the verification link yet.
const emailNotVerified = 'EMAIL_NOT_VERIFIED';

class AuthController {
  Future<String?> login(String email, String password) async {
    if (!FirebaseRuntime.initialized) return 'Firebase is not initialized. Did you run the script?';
    try {
      final credential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);

      // Pull the latest emailVerified flag from Firebase before deciding.
      await credential.user?.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      if (refreshed != null && !refreshed.emailVerified) {
        return emailNotVerified;
      }
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
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      // Send the verification link immediately, then sign out so the address
      // must be confirmed before the first login.
      await credential.user?.sendEmailVerification();
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

  /// Re-sends the verification link to a signed-in but unverified account.
  Future<String?> resendVerificationEmail() async {
    if (!FirebaseRuntime.initialized) {
      return 'Firebase is not initialized. Did you run the script?';
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 'Sign in first, then request a new link.';
      if (user.emailVerified) return 'This e-mail is already verified.';
      await user.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint("RESEND VERIFICATION ERROR: ${e.code}");
      return e.message;
    } catch (e) {
      debugPrint("RESEND VERIFICATION ERROR: $e");
      return e.toString();
    }
  }

  /// Sign in with a Google account.
  ///
  /// Returns `null` on success and an error message on failure.
  ///
  /// * Web  -> `signInWithPopup`, falling back to a full-page redirect when the
  ///   browser blocks the popup (always the case on phones).
  /// * Android / iOS -> the native `google_sign_in` sheet, then a Firebase
  ///   credential. Needs the OAuth *Web* client id and a registered SHA-1.
  Future<String?> signInWithGoogle() async {
    if (!FirebaseRuntime.initialized) {
      return 'Firebase is not initialized. Did you run the script?';
    }

    if (kIsWeb) {
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

    // ---- Native (Android / iOS) -------------------------------------------
    final serverClientId = FirebaseConfig.googleServerClientId.trim();
    if (serverClientId.isEmpty) {
      return 'Google sign-in on Android needs the OAuth Web client id. '
          'Run with --dart-define=GOOGLE_SERVER_CLIENT_ID=…apps.googleusercontent.com';
    }

    try {
      final googleSignIn = GoogleSignIn(
        serverClientId: serverClientId,
        scopes: const ['email'],
      );

      // google_sign_in remembers the last account and would sign straight back
      // in. Clearing the cached session first forces the account chooser, so
      // the agent can pick a different Gmail account each time.
      try {
        await googleSignIn.signOut();
      } catch (error) {
        debugPrint('Google pre-sign-out skipped: $error');
      }

      final account = await googleSignIn.signIn();
      if (account == null) return null; // user closed the sheet

      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: auth.idToken,
        accessToken: auth.accessToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      return null;
    } on FirebaseAuthException catch (e) {
      debugPrint('GOOGLE NATIVE ERROR CODE: ${e.code}');
      debugPrint('GOOGLE NATIVE ERROR MESSAGE: ${e.message}');
      return e.message;
    } catch (e) {
      debugPrint('GOOGLE NATIVE ERROR: $e');
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
      if (!kIsWeb) {
        // Also drop the cached Google account, otherwise the next "Continue
        // with Google" would silently reuse the previous identity.
        try {
          final clientId = FirebaseConfig.googleServerClientId.trim();
          await GoogleSignIn(
            serverClientId: clientId.isEmpty ? null : clientId,
          ).signOut();
        } catch (error) {
          debugPrint('Google sign-out skipped: $error');
        }
      }
      await FirebaseAuth.instance.signOut();
    }
  }
}

final authControllerProvider = Provider<AuthController>((ref) {
  return AuthController();
});