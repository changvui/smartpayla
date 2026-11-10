import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/firebase_config.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'state/auth_provider.dart';
import 'state/providers.dart';
import 'theme.dart';

class SmartPayLaApp extends ConsumerWidget {
  const SmartPayLaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'SmartPayLA',
      debugShowCheckedModeBanner: false,
      
      theme: buildAppTheme(), 
      darkTheme: buildDarkAppTheme(), // 👈 Use the new function here
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
      home: const AuthGate(), 
    );
  }
}

// (Keep AuthGate exactly as it was here...)
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Escape hatch for offline demos / screenshots when Firebase Auth is not
    // reachable (no network, or e-mail/password sign-in not enabled yet):
    //   flutter run -d chrome --dart-define=DEMO=true --dart-define=SKIP_LOGIN=true
    if (const bool.fromEnvironment('SKIP_LOGIN')) {
      return const HomeShell();
    }

    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(body: Center(child: Text('Error: $error'))),
      // If Firebase never initialised (offline, blocked, plugin missing) fall
      // back to the local-only ledger instead of trapping the user on a login
      // screen that can never succeed.
      data: (user) {
        if (user != null) return const HomeShell();
        return FirebaseRuntime.initialized ? const LoginScreen() : const HomeShell();
      },
    );
  }
}