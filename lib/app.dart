import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/firebase_config.dart';
import 'screens/customer_statement_screen.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/session_policy.dart';
import 'utils/back_guard.dart';
import 'utils/navigate_url.dart';
import 'utils/pending_token.dart';
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

    // Confirms payments a gateway already verified, in whichever context the
    // signed-in session is: the dashboard, or a statement tab on the agent's own
    // device. Inert until such a claim exists.
    ref.watch(gatewayAutoConfirmProvider);
    // A customer opens a statement from WhatsApp: `?s=<token>` renders the
    // read-only page and never touches the sign-in flow.
    final params = Uri.base.queryParameters;
    var statementToken = params['s'];
    // A gateway return without a token means the redirect lost it. Showing the
    // login screen there would look like the payment failed and would expose the
    // agent's sign-in page to a customer, so a neutral notice is shown instead.
    final returningFromGateway =
        params['paid'] == '1' || (params['session_id'] ?? '').isNotEmpty;

    // A redirect can come back with no query at all, so the remembered token is
    // used whenever `?s=` is missing - not only when gateway parameters survive.
    // It expires after two hours, so an agent opening the app later is not pulled
    // into an old statement.
    if (statementToken == null || statementToken.isEmpty) {
      final remembered = readPendingToken();
      if (remembered != null && remembered.isNotEmpty) {
        statementToken = remembered;
      }
    }

    return MaterialApp(
      title: 'SmartPayLA',
      debugShowCheckedModeBanner: false,
      
      theme: buildAppTheme(), 
      darkTheme: buildDarkAppTheme(), // 👈 Use the new function here
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,

      // Confirms payments a gateway already verified, in whichever context the
      // signed-in session happens to be: the dashboard, or a statement tab on
      // the agent's own device. Inert until such a claim exists.
      
      home: statementToken != null && statementToken.isNotEmpty
          ? CustomerVisit(token: statementToken)
          : returningFromGateway
              ? const _GatewayReturnNotice()
              : const AuthGate(),
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
/// Shown when a provider redirect arrives without the statement token.
///
/// The payment itself is unaffected: the gateway tab has nothing to display, so
/// it says so and can be closed. It must never fall back to the sign-in screen.
class _GatewayReturnNotice extends StatelessWidget {
  const _GatewayReturnNotice();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FE),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                size: 44,
                color: Color(0xFF15803D),
              ),
              const SizedBox(height: 14),
              const Text(
                'Payment received',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Return to the statement tab to see the updated balance. '
                'This window can be closed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                  height: 1.45,
                ),
              ),
              SizedBox(height: 18),
              // Diagnostic: which parameters the redirect actually delivered.
              Text(
                'Redirect contained: ${Uri.base.queryParameters.keys.join(', ')}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

    // A tab we opened that came back without `paid=1` is a cancelled checkout.
    // Close it, so the customer is not left on an empty tab; the statement in
    // the original window never changed.
    final params = Uri.base.queryParameters;
    final cancelled = params['paid'] != '1' && (params['session_id'] ?? '').isEmpty;
    if (cancelled && wasOpenedAsPopup()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          if (mounted) cancelAndCloseTab();
        });
      });
    }
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