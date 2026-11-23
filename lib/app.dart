import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/firebase_config.dart';
import 'screens/customer_statement_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/session_policy.dart';
import 'utils/back_guard.dart';
import 'utils/payment_bridge.dart';
import 'state/auth_provider.dart';
import 'services/gateway_autoconfirm.dart';
import 'state/providers.dart';
import 'theme.dart';

class SmartPayLaApp extends ConsumerWidget {
  const SmartPayLaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(themeModeProvider);
    // A customer opens a statement from WhatsApp: `?s=<token>` renders the
    // read-only page and never touches the sign-in flow.
    final statementToken = Uri.base.queryParameters['s'];

    return MaterialApp(
      title: 'SmartPayLA',
      debugShowCheckedModeBanner: false,
      
      theme: buildAppTheme(), 
      darkTheme: buildDarkAppTheme(), // 👈 Use the new function here
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      
      home: statementToken == null || statementToken.isEmpty
          ? const AuthGate()
          : CustomerVisit(token: statementToken),
    );
  }
}

/// The customer's visit: the statement only, with the agent session cleared
/// and the browser's Back button absorbed.
///
/// A statement link is opened on a shared or borrowed phone as often as on the
/// customer's own. Two things follow from that: the device must not stay signed
/// in as the agent, and Back must not walk into the agent dashboard that was
/// open before.
class CustomerVisit extends StatefulWidget {
  const CustomerVisit({super.key, required this.token});

  final String token;

  @override
  State<CustomerVisit> createState() => _CustomerVisitState();
}

class _CustomerVisitState extends State<CustomerVisit> {
  int _reloadKey = 0;
  void Function()? _stopListening;

  @override
  void initState() {
    super.initState();
    installCustomerBackGuard();
    signOutForCustomerVisit();
    // The checkout happens in a second tab; when it reports a payment, reload
    // the statement so this window shows the settled balance too.
    _stopListening = listenPaymentConfirmed(widget.token, () {
      if (mounted) setState(() => _reloadKey++);
    });
  }

  @override
  void dispose() {
    _stopListening?.call();
    removeCustomerBackGuard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomerStatementScreen(
      key: ValueKey(_reloadKey),
      token: widget.token,
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

    // Confirms payments a gateway already verified, so the agent does not
    // approve the same money twice. Inert until such a claim exists.
    ref.watch(gatewayAutoConfirmProvider);

    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(body: Center(child: Text('Error: $error'))),
      // A user only reaches the ledger once the e-mail address is confirmed.
      // While unverified they stay on the login screen, which offers a
      // "resend verification link" action.
      data: (user) {
        if (user == null) {
          return FirebaseRuntime.initialized
              ? const LoginScreen()
              : const HomeShell();
        }
        return user.emailVerified ? const HomeShell() : const LoginScreen();
      },
    );
  }
}