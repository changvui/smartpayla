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

  if (FirebaseConfig.configured) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
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
