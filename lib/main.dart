import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/transaction_repository.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

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
