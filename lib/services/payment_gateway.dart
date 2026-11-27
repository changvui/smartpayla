import 'dart:convert';

import 'package:http/http.dart' as http;

/// A Checkout Session created by the Worker.
class GatewaySession {
  const GatewaySession({
    required this.id,
    required this.url,
    required this.amount,
  });

  final String id;
  final String url;
  final double amount;
}

/// What the gateway says about a session.
class GatewayPayment {
  const GatewayPayment({
    required this.paid,
    required this.amount,
    required this.method,
    required this.reference,
    this.token,
  });

  final bool paid;
  final double amount;
  final String method;
  final String reference;

  /// The statement token the session was created for, echoed by the gateway.
  final String? token;
}

/// Stripe Checkout, through the Worker.
///
/// The client never sees the secret key: it asks the Worker to create the
/// session and, on return, to verify it. Verification is the trust anchor - a
/// payment is only written when Stripe reports `paid`.
///
/// Enabled with `--dart-define=STRIPE_CHECKOUT=true`. Without it the statement
/// keeps its built-in simulated checkout, so a build without keys still works.
class PaymentGateway {
  static const enabled = bool.fromEnvironment('STRIPE_CHECKOUT');
  static const _proxy = String.fromEnvironment('REMINDER_PROXY_URL');

  static bool get isConfigured => enabled && _proxy.trim().isNotEmpty;

  String get _base => _proxy.trim().replaceAll(RegExp(r'/+$'), '');

  Future<GatewaySession?> create({
    required String token,
    required double amount,
    required String description,
    required String returnUrl,
    String? billNo,
    String? customerName,
  }) async {
    if (!isConfigured) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_base/pay/create'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'amount': amount,
              'description': description,
              'returnUrl': returnUrl,
              'billNo': billNo ?? '',
              'customerName': customerName ?? '',
            }),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final url = (data['url'] ?? '').toString();
      final id = (data['id'] ?? '').toString();
      if (url.isEmpty || id.isEmpty) return null;
      return GatewaySession(
        id: id,
        url: url,
        amount: (data['amount'] as num?)?.toDouble() ?? amount,
      );
    } catch (_) {
      return null;
    }
  }

  Future<GatewayPayment?> verify(String sessionId) async {
    if (!isConfigured || sessionId.isEmpty) return null;
    try {
      final response = await http
          .post(
            Uri.parse('$_base/pay/verify'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'sessionId': sessionId}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      return GatewayPayment(
        paid: data['paid'] == true,
        amount: (data['amount'] as num?)?.toDouble() ?? 0,
        method: (data['method'] ?? 'Card').toString(),
        reference: (data['reference'] ?? '').toString(),
        token: (data['token'] ?? '').toString(),
      );
    } catch (_) {
      return null;
    }
  }
}
