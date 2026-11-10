import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/firebase_config.dart';
import 'data/transaction_repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  // --dart-define=LOCAL_ONLY=true skips Firebase completely. Use it when the
  // demo machine has no usable route to gstatic.com / Firestore (auth then
  // falls back to the local ledger, see AuthGate).
  const localOnly = bool.fromEnvironment('LOCAL_ONLY');

  if (!localOnly && FirebaseConfig.configured) {
    try {
      // Never let a slow/blocked network freeze the app on a white screen.
      await Firebase.initializeApp(options: FirebaseConfig.options)
          .timeout(const Duration(seconds: 15));
      FirebaseRuntime.initialized = true;
      try {
        FirebaseFirestore.instance.settings =
            const Settings(persistenceEnabled: true);
      } catch (_) {
        // Some web runtimes do not expose persistence settings.
      }

      // Optional temporary credential for testing cross-device sync before the
      // partner's login UI exists. Remove these defines for the final build.
      const demoEmail = String.fromEnvironment('DEMO_AUTH_EMAIL');
      const demoPassword = String.fromEnvironment('DEMO_AUTH_PASSWORD');
      if (demoEmail.isNotEmpty && demoPassword.isNotEmpty) {
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: demoEmail,
            password: demoPassword,
          );
        } catch (error) {
          debugPrint('Demo auth sign-in failed: $error');
        }
      }
    } catch (error) {
      debugPrint('Firebase init skipped: $error');
    }
  }

  // For demos and screenshots:
  // flutter run -d chrome --dart-define=DEMO=true
  // It only seeds when the local ledger is empty.
  const demoMode = bool.fromEnvironment('DEMO');
  if (demoMode) {
    await LocalTransactionRepository(prefs).seedDemo();
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const SmartPayLaApp(),
    ),
  );
}
