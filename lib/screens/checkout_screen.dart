import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/checkout_url.dart';

/// What the checkout page hands back to the statement.
class CheckoutOutcome {
  const CheckoutOutcome({required this.paid, this.method = 'DuitNow'});

  final bool paid;
  final String method;
}

/// A stand-in for a hosted payment gateway page.
///
/// It deliberately does not look like SmartPayLA: a different palette, its own
/// header, its own wording ("merchant", "return to merchant") and a different
/// address in the browser. That is what a customer experiences when a merchant
/// sends them to a provider, and it is the part of a real integration that a
/// demonstrator cannot fake with a dialog.
///
/// The money is simulated. Replacing this screen with a real provider means
/// opening the provider's URL instead and letting its webhook confirm the
/// payment; everything after this page stays the same.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.token,
    required this.merchantName,
    required this.customerName,
    required this.amount,
    this.reference,
  });

  final String token;
  final String merchantName;
  final String customerName;
  final double amount;
  final String? reference;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  static const _ink = Color(0xFF0B1220);
  static const _panel = Colors.white;
  static const _muted = Color(0xFF64748B);
  static const _line = Color(0xFFE2E8F0);
  static const _accent = Color(0xFF4F46E5);

  String _method = 'DuitNow';
  bool _processing = false;
  bool _approved = false;

  @override
  void initState() {
    super.initState();
    // Make the address bar read like a provider page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setCheckoutUrl(token: widget.token, inCheckout: true);
    });
  }

  @override
  void dispose() {
    setCheckoutUrl(token: widget.token, inCheckout: false);
    super.dispose();
  }

  Future<void> _pay() async {
    setState(() => _processing = true);
    // Deliberately not instant: a gateway round trip takes a moment, and the
    // pause is what makes the return to the merchant read as a real redirect.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() {
      _processing = false;
      _approved = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    Navigator.of(context).pop(CheckoutOutcome(paid: true, method: _method));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _merchantCard(),
                    const SizedBox(height: 14),
                    _methodTabs(),
                    const SizedBox(height: 14),
                    if (_approved)
                      _approvedCard()
                    else
                      _methodBody(),
                    const SizedBox(height: 18),
                    if (!_approved)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _processing ? null : _pay,
                          style: FilledButton.styleFrom(
                            backgroundColor: _accent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _processing
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Contacting your bank…'),
                                  ],
                                )
                              : Text(
                                  'Pay RM ${widget.amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (!_approved)
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _processing
                              ? null
                              : () => Navigator.of(context)
                                  .pop(const CheckoutOutcome(paid: false)),
                          child: const Text(
                            'Cancel and return to merchant',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      color: _ink,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.lock_rounded, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DuitNow Checkout',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Secure payment · demo environment',
                style: TextStyle(color: Color(0xFFB6C2D9), fontSize: 10.5),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'SIMULATED',
              style: TextStyle(
                color: Color(0xFFFBBF24),
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _merchantCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pay to',
            style: TextStyle(fontSize: 11, color: _muted, letterSpacing: 0.4),
          ),
          const SizedBox(height: 2),
          Text(
            widget.merchantName.isEmpty ? 'SmartPayLA' : widget.merchantName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Amount',
            style: TextStyle(fontSize: 11, color: _muted, letterSpacing: 0.4),
          ),
          const SizedBox(height: 2),
          Text(
            'RM ${widget.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'For ${widget.customerName.isEmpty ? 'customer' : widget.customerName}',
                  style: TextStyle(fontSize: 11.5, color: _muted),
                ),
              ),
              if ((widget.reference ?? '').isNotEmpty)
                Text(
                  widget.reference!,
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _methodTabs() {
    const options = ['DuitNow', 'Card'];
    return Row(
      children: [
        for (final option in options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _processing
                    ? null
                    : () => setState(() => _method = option),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _method == option ? _accent : _panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _method == option ? _accent : _line,
                    ),
                  ),
                  child: Text(
                    option,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _method == option ? Colors.white : _ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _methodBody() {
    switch (_method) {
      case 'Card':
        return Column(
          children: [
            _fakeField('Card number', '4242 4242 4242 4242'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _fakeField('Expiry', '12 / 28')),
                const SizedBox(width: 8),
                Expanded(child: _fakeField('CVC', '123')),
              ],
            ),
            const SizedBox(height: 8),
            _note('Demo card - no card network is contacted.'),
          ],
        );
      case 'Online banking':
        return Column(
          children: [
            _bankRow('Maybank2u'),
            const SizedBox(height: 8),
            _bankRow('CIMB Clicks'),
            const SizedBox(height: 8),
            _bankRow('Public Bank'),
            const SizedBox(height: 8),
            _note('Demo bank list - nothing is submitted.'),
          ],
        );
      default:
        return Column(
          children: [
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.qr_code_2_rounded, size: 54, color: _ink),
                  const SizedBox(height: 6),
                  Text(
                    'Scan with your banking app',
                    style: TextStyle(fontSize: 11.5, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _note('Demo QR - tapping Pay approves the payment instantly.'),
          ],
        );
    }
  }

  Widget _approvedCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF15803D), size: 44),
          const SizedBox(height: 8),
          const Text(
            'Payment approved',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF15803D),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Returning to merchant…',
            style: TextStyle(fontSize: 11.5, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _fakeField(String label, String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: _muted),
          ),
          const Spacer(),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _bankRow(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_rounded, size: 16, color: _muted),
          const SizedBox(width: 10),
          Text(name, style: const TextStyle(fontSize: 12.5)),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, size: 16, color: _muted),
        ],
      ),
    );
  }

  Widget _note(String text) {
    return Row(
      children: [
        const Icon(Icons.info_outline_rounded, size: 13, color: _muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 10.5, color: _muted, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.verified_user_outlined, size: 12, color: _muted),
          const SizedBox(width: 6),
          Text(
            'Not a real payment page · SmartPayLA demo',
            style: TextStyle(fontSize: 10, color: _muted),
          ),
        ],
      ),
    );
  }
}
