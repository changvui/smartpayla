import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/payment_gateway.dart';
import '../services/receipt_pdf.dart';
import '../services/statement_service.dart';
import '../utils/checkout_url.dart';
import '../utils/qr_saver.dart';
import '../utils/navigate_url.dart';
import '../utils/pending_payment.dart';
import '../utils/pending_token.dart';
import '../utils/payment_bridge.dart';
import 'checkout_screen.dart';
import '../utils/whatsapp.dart';
import '../widgets/payment_actions.dart';
import 'qr_fullscreen_screen.dart';

/// Public, read-only page a customer opens from a WhatsApp link.
///
/// It is deliberately independent of the application theme: no bottom
/// navigation, no dark mode, a large balance and a single call to action. The
/// only data it can read is the snapshot behind the token in the URL.
class CustomerStatementScreen extends StatefulWidget {
  const CustomerStatementScreen({
    super.key,
    required this.token,
    this.service,
  });

  final String token;
  final StatementService? service;

  @override
  State<CustomerStatementScreen> createState() =>
      _CustomerStatementScreenState();
}

// ------------------------------------------------------------------ palette
const _bg = Color(0xFFF5F8FE);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF64748B);
const _blue = Color(0xFF1D4ED8);
const _blueSoft = Color(0xFFE8EEFB);
const _border = Color(0xFFDCE5F5);
const _green = Color(0xFF15803D);
const _red = Color(0xFFB91C1C);
const _amber = Color(0xFFB45309);

Color _statusColor(String status) {
  switch (status) {
    case 'Paid':
      return _green;
    case 'Partial':
      return _blue;
    case 'Overdue':
      return _red;
    case 'Unpaid':
      return _amber;
    default:
      return _muted;
  }
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen>
    with WidgetsBindingObserver {
  late Future<Map<String, dynamic>?> _future;
  bool _declared = false;
  Map<String, dynamic>? _data;
  bool _gatewayDeclared = false;
  bool _gatewayHandled = false;

  /// Money the gateway has already confirmed in this session. The published
  /// statement is a snapshot that only the agent can rewrite, so the page shows
  /// the payment immediately and lets the snapshot catch up.
  double _paidNow = 0;

  /// The published total, before anything the gateway confirmed locally.
  double get _snapshotTotal =>
      (_data?['totalBalance'] as num?)?.toDouble() ?? 0;

  /// Last gateway verification result, shown while a payment is being applied.
  String? _gatewayNote;
  Timer? _gatewayPoll;
  bool _autoReceiptDone = false;
  Object? _checkoutTab;
  bool _gatewayNoteBad = false;
  bool _sending = false;
  String? _lastError;

  /// Bills the customer wants to settle now. Defaults to all of them.
  final Set<String> _selected = {};
  bool _seedSelection = true;

  /// False = pay the full selected amount, true = the customer typed an
  /// amount of their own.
  bool _customAmount = false;
  String _customAmountText = '';

  /// The QR is tucked behind a DuitNow card until the customer asks for it.
  bool _showQr = false;

  StatementService get _service => widget.service ?? StatementService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = _service.fetch(widget.token);
  }

  @override
  void dispose() {
    _gatewayPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The customer has to leave the page to open their banking app. When they
  /// come back, offer the declaration straight away instead of waiting for them
  /// to scroll down. There is no way to observe the transfer itself: a personal
  /// DuitNow code has no callback, so this prompt is the closest honest
  /// approximation of "auto detected".
  bool _leftToPay = false;
  bool _prompted = false;
  bool _showReturnPrompt = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _leftToPay = true;
      return;
    }
    if (state == AppLifecycleState.resumed &&
        _leftToPay &&
        !_prompted &&
        !_declared) {
      _prompted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _showReturnPrompt = true);
      });
    }
  }


  String _money(num value) =>
      'RM ${NumberFormat('#,##0.00').format(value)}';

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          brightness: Brightness.light,
          surface: _bg,
        ).copyWith(onSurface: _ink, onSurfaceVariant: _muted),
        scaffoldBackgroundColor: _bg,
      ),
      child: Scaffold(
        body: SafeArea(
          child: FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data;
              if (data == null) return _invalidState();
              return _statement(data);
            },
          ),
        ),
      ),
    );
  }

  Widget _invalidState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_off_rounded, size: 48, color: _muted),
            const SizedBox(height: 16),
            const Text(
              'This link is no longer valid',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'It may have expired or been replaced by a newer statement. '
              'Ask the agent to send a fresh link.',
              style: TextStyle(fontSize: 14, color: _muted, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statement(Map<String, dynamic> data) {
    _data = data;
    // The customer is on their own statement again; the fallback token has done
    // its job and must not redirect a later visit.
    clearPendingToken();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _handleGatewayReturn(data),
    );
    final shop = (data['shopName'] ?? 'SmartPayLA').toString();
    final customer = (data['customerName'] ?? '').toString();
    final snapshotTotal = (data['totalBalance'] as num?)?.toDouble() ?? 0;
    final bills = (data['bills'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    // Oldest bill first, so the customer sees what should be settled first.
    bills.sort((a, b) {
      final da = DateTime.tryParse(a['dueDate']?.toString() ?? '') ??
          DateTime(2100);
      final db = DateTime.tryParse(b['dueDate']?.toString() ?? '') ??
          DateTime(2100);
      return da.compareTo(db);
    });
    if (_seedSelection) {
      _seedSelection = false;
      _selected.clear();
      if (bills.isNotEmpty) {
        _selected.add((bills.first['id'] ?? '').toString());
      }
    }
    // A gateway payment survives a reload: the snapshot is only rewritten when
    // the agent confirms, and the customer must not see the balance bounce back
    // in the meantime. Once the snapshot has caught up, the local record is
    // dropped so nothing is subtracted twice.
    if (_paidNow == 0) {
      final pending = readPendingPayment(widget.token);
      if (pending != null) {
        if (snapshotTotal <= pending.expectedTotal + 0.01) {
          clearPendingPayment(widget.token);
        } else {
          _paidNow = pending.amount;
        }
      }
    }

    // Subtract what the gateway just confirmed, oldest bill first - the same
    // order the ledger uses - so the page agrees with the money that has left.
    if (_paidNow > 0) {
      var remaining = _paidNow;
      for (final bill in bills) {
        if (remaining <= 0) break;
        final balance = (bill['balance'] as num?)?.toDouble() ?? 0;
        final applied = balance < remaining ? balance : remaining;
        bill['balance'] = balance - applied;
        // Keep the "Paid" column honest: the money is confirmed, so it counts as
        // paid even though the snapshot has not been rewritten yet.
        final paid = (bill['paid'] as num?)?.toDouble() ?? 0;
        bill['paid'] = paid + applied;
        final status = (bill['status'] ?? 'Unpaid').toString();
        if (applied > 0 && status != 'Paid') {
          bill['status'] = (balance - applied) <= 0.005 ? 'Paid' : 'Partial';
        }
        remaining -= applied;
      }
    }
    final totalBalance = bills.isEmpty
        ? (snapshotTotal - _paidNow).clamp(0.0, snapshotTotal)
        : bills.fold<double>(
            0,
            (sum, bill) => sum + ((bill['balance'] as num?)?.toDouble() ?? 0),
          );

    var selectedTotal = 0.0;
    for (final bill in bills) {
      if (_selected.contains((bill['id'] ?? '').toString())) {
        selectedTotal += (bill['balance'] as num?)?.toDouble() ?? 0;
      }
    }

    final reconCode = (data['reconCode'] ?? '').toString();
    final qr = data['paymentQr']?.toString();
    final bankNote = (data['bankNote'] ?? '').toString();
    final payee = (data['payeeName'] ?? '').toString();
    final agentPhone = (data['agentPhone'] ?? '').toString();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                shop,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: _blue,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded, size: 20, color: _blue),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Statement for $customer',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _ink,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 20),
        if (_paidNow > 0) ...[
          _paidBanner(_paidNow),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _downloadReceipt,
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
              label: const Text(
                'Download receipt (PDF)',
                style: TextStyle(fontSize: 12.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_gatewayNote != null) ...[
          _gatewayStrip(_gatewayNote!, _gatewayNoteBad),
          const SizedBox(height: 12),
        ],
        _balanceCard(totalBalance, bills.length),
        const SizedBox(height: 24),
        if (bills.isEmpty)
          _paidUp()
        else ...[
          const Text(
            'Outstanding bills',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Tap a bill to pay it. Each payment settles one bill.',
            style: TextStyle(fontSize: 11.5, color: _muted),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < bills.length; i++) ...[
            _billCard(
              bills[i],
              selected: _selected.contains(
                (bills[i]['id'] ?? '').toString(),
              ),
              onToggle: () => _toggleBill(i, bills),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          _paymentSection(
            totalBalance: selectedTotal,
            qr: qr,
            bankNote: bankNote,
            payee: payee,
            reconCode: reconCode,
            bills: bills,
          ),
          if (_showReturnPrompt && !_declared) ...[
            const SizedBox(height: 12),
            if (!PaymentGateway.isConfigured) _returnPrompt(selectedTotal),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      size: 18, color: _red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not send: $_lastError',
                      style: const TextStyle(
                        fontSize: 12,
                        color: _red,
                        height: 1.35,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _lastError = null),
                    icon: const Icon(Icons.close_rounded, size: 16),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _actions(_payAmount(selectedTotal), agentPhone),
        ],
        const SizedBox(height: 28),
        Text(
          'Updated ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
          style: const TextStyle(fontSize: 11.5, color: _muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Shown the moment the gateway confirms, before the agent's ledger has been
  /// republished. "Updating" is honest: the snapshot is still the old one, and
  /// this page refreshes itself when the agent confirms.
  /// Watches the session from this tab instead of trusting the redirect.
  ///
  /// A provider redirect can lose its query, be blocked, or land in a different
  /// tab. Asking the Worker about the session we just created needs none of that:
  /// the moment Stripe reports `paid`, this page records the payment.
  void _startGatewayPoll(String sessionId, double amount) {
    _gatewayPoll?.cancel();
    var attempts = 0;
    _gatewayPoll = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts += 1;
      if (attempts > 100 || !mounted) {
        timer.cancel();
        return;
      }
      final payment = await PaymentGateway().verify(sessionId);
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (payment == null || !payment.paid) return;

      timer.cancel();
      closeTabHandle(_checkoutTab);
      await _applyGatewayPayment(payment, amount);
    });
  }

  /// Writes the claim for a verified payment, once.
  Future<void> _applyGatewayPayment(
    GatewayPayment payment,
    double fallbackAmount,
  ) async {
    if (_declared) return;
    final data = _data ?? const <String, dynamic>{};
    final amount = payment.amount > 0 ? payment.amount : fallbackAmount;
    setState(() => _sending = true);
    try {
      final sent = await _service.declarePayment(
        token: widget.token,
        ownerUid: (data['ownerUid'] ?? '').toString(),
        customerName: (data['customerName'] ?? '').toString(),
        amount: amount,
        note: 'Stripe ${payment.method} (${payment.reference})',
        proofImage: null,
        reconCode: (data['reconCode'] ?? '').toString(),
        billIds: _selected.toList(),
        billLabels: const [],
        simulated: false,
        autoConfirm: true,
      );
      if (!sent) throw StateError('This link has no owner.');
      notifyPaymentConfirmed(widget.token);
      if (!mounted) return;
      setState(() {
        _declared = true;
        _gatewayDeclared = true;
        _sending = false;
        _paidNow = amount;
        _gatewayNote =
            'Verified ${payment.method} · RM ${amount.toStringAsFixed(2)}'
            ' · ${payment.reference}';
        _gatewayNoteBad = false;
      });
      rememberPendingPayment(
        token: widget.token,
        amount: amount,
        expectedTotal: (_snapshotTotal - amount).clamp(0, _snapshotTotal),
      );
      if (!_autoReceiptDone) {
        _autoReceiptDone = true;
        // A short delay so the confirmation is visible before the download.
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await _downloadReceipt();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _gatewayNote = 'Payment seen but not recorded: $error';
        _gatewayNoteBad = true;
      });
    }
  }

  Widget _paidBanner(double amount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _green, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paid ${_money(amount)}',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _green,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "The gateway confirmed this payment. The bills below are "
                  "updated already; the agent's ledger catches up by itself.",
                  style: TextStyle(fontSize: 11, color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the receipt PDF and hands it to the browser.
  ///
  /// Called automatically once after a gateway payment, and again from a button:
  /// a browser can refuse a download that no click started, so the button is the
  /// reliable path and the automatic attempt is a convenience.
  Future<void> _downloadReceipt() async {
    if (_paidNow <= 0) return;
    final data = _data ?? const <String, dynamic>{};
    final bills = (data['bills'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final bill = bills
        .where((b) => _selected.contains((b['id'] ?? '').toString()))
        .firstOrNull ??
        bills.firstOrNull;
    final billNo = (bill?['billNo'] ?? data['reconCode'] ?? '').toString();
    final billTotal = (bill?['total'] as num?)?.toDouble();
    final paidBefore = (bill?['paid'] as num?)?.toDouble();
    final remaining = (data['totalBalance'] as num?)?.toDouble();

    final bytes = ReceiptPdf.build(
      shopName: (data['shopName'] ?? 'SmartPayLA').toString(),
      customerName: (data['customerName'] ?? '').toString(),
      amount: _paidNow,
      method: _gatewayNote == null ? 'Gateway' : _methodFromNote(_gatewayNote!),
      reference: _referenceFromNote(_gatewayNote),
      billNo: billNo,
      paidAt: _stamp(DateTime.now()),
      billTotal: billTotal,
      paidBefore: paidBefore,
      remaining: remaining == null ? null : (remaining).clamp(0, remaining),
      simulated: !PaymentGateway.isConfigured,
    );

    final uri = 'data:application/pdf;base64,${base64Encode(bytes)}';
    final saved = saveDataUri(uri, 'receipt-$billNo.pdf');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Receipt downloaded (receipt-$billNo.pdf).'
              : 'Receipt ready - use the download button on a desktop browser.',
        ),
        backgroundColor: _green,
      ),
    );
  }

  String _methodFromNote(String note) {
    final value = note.toLowerCase();
    if (value.contains('fpx')) return 'FPX';
    if (value.contains('card')) return 'Card';
    return 'Gateway';
  }

  String _referenceFromNote(String? note) {
    if (note == null) return '';
    final parts = note.split('·');
    return parts.length > 1 ? parts.last.trim() : '';
  }

  String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.day}/${two(at.month)}/${at.year} ${two(at.hour)}:${two(at.minute)}';
  }

  /// A one-line trace of what the gateway verification did. Kept visible during
  /// the prototype, so a failed return can be diagnosed without the console.
  Widget _gatewayStrip(String note, bool bad) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bad ? const Color(0xFFFEF2F2) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bad ? _red : _border),
      ),
      child: Row(
        children: [
          Icon(
            bad ? Icons.error_outline_rounded : Icons.verified_rounded,
            size: 14,
            color: bad ? _red : _muted,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                fontSize: 10.5,
                color: bad ? _red : _muted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(double total, int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _blue,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count == 1 ? 'Amount outstanding' : 'Amount outstanding ($count bills)',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFDCE6FF),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _money(total),
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paidUp() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_rounded, color: _green),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Nothing outstanding — thank you!',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _green,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Selection is a contiguous run from the oldest bill: picking a newer bill
  /// also picks every older one, and un-picking a bill clears the newer ones.
  /// This is the credit-control rule — the oldest debt is settled first.
  /// What the customer is actually going to transfer.
  double _payAmount(double selectedTotal) {
    if (!_customAmount) return selectedTotal;
    final parsed = double.tryParse(_customAmountText.replaceAll(',', '.'));
    if (parsed == null || parsed <= 0) return selectedTotal;
    return parsed > selectedTotal ? selectedTotal : parsed;
  }

  /// One payment settles exactly one bill, so the transfer reference is always
  /// that bill's number and there is nothing to allocate or guess.
  void _toggleBill(int index, List<Map<String, dynamic>> bills) {
    setState(() {
      final id = (bills[index]['id'] ?? '').toString();
      _selected
        ..clear()
        ..add(id);
    });
  }

  Widget _billCard(
    Map<String, dynamic> bill, {
    required bool selected,
    required VoidCallback onToggle,
  }) {
    final status = (bill['status'] ?? 'Unpaid').toString();
    final color = _statusColor(status);
    final daysOverdue = (bill['daysOverdue'] as num?)?.toInt() ?? 0;
    final dueDate = DateTime.tryParse(bill['dueDate']?.toString() ?? '');
    final billNo = (bill['billNo'] ?? '').toString();
    final evidence = bill['evidence']?.toString();
    final evidenceNote = (bill['evidenceNote'] ?? '').toString();
    final total = (bill['total'] as num?)?.toDouble() ?? 0;
    final paid = (bill['paid'] as num?)?.toDouble() ?? 0;
    final balance = (bill['balance'] as num?)?.toDouble() ?? 0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? _blueSoft.withValues(alpha: 0.45) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _blue : _border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: selected ? _blue : _muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      (bill['description'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (billNo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Bill $billNo',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _amountColumn('Total', total),
              const SizedBox(width: 18),
              _amountColumn('Paid', paid),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Balance',
                    style: TextStyle(fontSize: 11.5, color: _muted),
                  ),
                  Text(
                    _money(balance),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                daysOverdue > 0
                    ? Icons.error_outline_rounded
                    : Icons.schedule_rounded,
                size: 15,
                color: daysOverdue > 0 ? _red : _muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  daysOverdue > 0
                      ? '${daysOverdue.toString()} days overdue'
                      : 'Due ${dueDate == null ? '—' : DateFormat('d MMM yyyy').format(dueDate)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: daysOverdue > 0 ? _red : _muted,
                    fontWeight:
                        daysOverdue > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (evidence != null && evidence.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _showEvidence(evidence, bill),
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: const Text('View bill'),
                  style: TextButton.styleFrom(
                    foregroundColor: _blue,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (evidenceNote.isNotEmpty)
                Text(
                  'No photo',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: _muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountColumn(String label, double value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5, color: _muted)),
        Text(
          _money(value),
          style: const TextStyle(fontSize: 14, color: _ink),
        ),
      ],
    );
  }

  void _showEvidence(String dataUri, Map<String, dynamic> bill) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (bill['description'] ?? 'Bill').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.memory(
                  _decode(dataUri),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _paymentSection({
    required double totalBalance,
    required String? qr,
    required String bankNote,
    required String payee,
    required String reconCode,
    required List<Map<String, dynamic>> bills,
  }) {
    final gateway = PaymentGateway.isConfigured;
    final hasQr = qr != null && qr.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            gateway ? 'Amount to pay' : 'Pay now',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            () {
              final payBill = bills
                  .where(
                    (b) => _selected.contains((b['id'] ?? '').toString()),
                  )
                  .firstOrNull;
              final billNo = (payBill?['billNo'] ?? '').toString();
              return billNo.isEmpty
                  ? 'Outstanding ${_money(totalBalance)}'
                  : 'Paying bill $billNo · ${_money(totalBalance)}';
            }(),
            style: const TextStyle(fontSize: 12.5, color: _muted),
          ),
          const SizedBox(height: 14),
          if (hasQr && !gateway) ...[
            if (!_showQr)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _showQr = true),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      _duitnowBadge(),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Pay with DuitNow',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            const Text(
                              'Scan the QR with any banking app or TNG',
                              style: TextStyle(fontSize: 12, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.qr_code_2_rounded, size: 26, color: _blue),
                      const Icon(Icons.chevron_right_rounded, color: _muted),
                    ],
                  ),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _blue, width: 1.6),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _duitnowBadge(),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Scan to pay',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hide QR',
                          onPressed: () => setState(() => _showQr = false),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Fill the card: a phone screen is the normal case, so
                        // the QR should use every pixel available.
                        final side = constraints.maxWidth > 420
                            ? 420.0
                            : constraints.maxWidth;
                        final selectedBill = bills
                            .where(
                              (b) => _selected.contains(
                                (b['id'] ?? '').toString(),
                              ),
                            )
                            .firstOrNull;
                        return InkWell(
                          onTap: () => _showFullScreenQr(
                            qr,
                            amount: _payAmount(totalBalance),
                            reference: (selectedBill?['billNo'] ?? '').toString(),
                          ),
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Image.memory(
                                _decode(qr),
                                width: side,
                                height: side,
                                fit: BoxFit.contain,
                              ),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.white70,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.zoom_out_map_rounded,
                                  size: 16,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Scan with any banking app or TNG eWallet · tap to enlarge',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (!gateway && reconCode.isNotEmpty)
              _reconCodeRow(reconCode, bills),
          ] else if (!gateway)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _blueSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'No DuitNow QR has been set up yet. Use one of the options '
                'below, or contact the agent.',
                style: TextStyle(fontSize: 12.5, color: _ink, height: 1.45),
              ),
            ),
            Center(
              child: Column(
                children: [
                  Text(
                    _money(_payAmount(totalBalance)),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('Pay in full'),
                        selected: !_customAmount,
                        onSelected: (_) =>
                            setState(() => _customAmount = false),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Other amount'),
                        selected: _customAmount,
                        onSelected: (_) =>
                            setState(() => _customAmount = true),
                      ),
                    ],
                  ),
                  if (_customAmount)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        width: 180,
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.center,
                          onChanged: (value) =>
                              setState(() => _customAmountText = value),
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixText: 'RM ',
                            hintText: '50.00',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ),
                  if (!gateway)
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(
                            text: _payAmount(totalBalance).toStringAsFixed(2),
                          ),
                        );
                        _toast('Amount copied — paste it after scanning');
                      },
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy amount'),
                      style: TextButton.styleFrom(foregroundColor: _blue),
                    ),
                ],
              ),
            ),
          if (gateway && hasQr) ...[
            const Divider(height: 26),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => _showFullScreenQr(
                    qr,
                    amount: _payAmount(totalBalance),
                    reference: reconCode,
                  ),
                  child: Container(
                    width: 74,
                    height: 74,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Image.memory(_decode(qr), fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Or pay by DuitNow',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Scan the code, or transfer and use the bill number as '
                        'the reference. The agent confirms this one, because no '
                        'gateway verifies it.',
                        style: TextStyle(fontSize: 11.5, color: _muted, height: 1.35),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _reconCodeRow(reconCode, bills),
          ] else if (!gateway) ...[
            const SizedBox(height: 10),
            _reconCodeRow(reconCode, bills),
          ],
        ],
      ),
    );
  }

  /// The reference the customer types into their bank transfer. The bill
  /// number is used directly, because that is the number printed on the paper
  /// and the one the agent can look up. The SPL code stays as a secondary
  /// option for a payment that covers several bills.
  /// A plain text mark rather than the DuitNow logo: the logo is a registered
  /// trademark and is not redistributed with this prototype.
  Widget _duitnowBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE6007E),
        borderRadius: BorderRadius.circular(7),
      ),
      child: const Text(
        'DuitNow',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _reconCodeRow(
    String reconCode,
    List<Map<String, dynamic>> bills,
  ) {
    final selectedBills = bills
        .where((b) => _selected.contains((b['id'] ?? '').toString()))
        .toList();
    final selectedNumbers = selectedBills
        .map((b) => (b['billNo'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toList();
    // With one bill per payment the number is always available; the SPL code is
    // only a fallback for a record created before numbers were mandatory.
    final primary = selectedNumbers.isEmpty ? reconCode : selectedNumbers.first;
    final useCode = selectedNumbers.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _blueSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Transfer reference',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: _muted,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  useCode ? 'customer code' : 'bill number',
                  style: const TextStyle(fontSize: 9.5, color: _muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: primary));
              _toast('Reference copied');
            },
            child: Row(
              children: [
                Text(
                  primary,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _blue,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.copy_rounded, size: 16, color: _blue),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            useCode
                ? 'Use this code in the transfer reference.'
                : 'Use this bill number in the transfer reference. A part '
                      'payment uses the same number.',
            style: const TextStyle(fontSize: 11.5, color: _ink, height: 1.4),
          ),
          if (useCode && reconCode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Code: $reconCode',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
            ),
        ],
      ),
    );
  }

  /// A second way to pay, but only when the agent has actually configured one.
  ///
  /// The statement already shows a DuitNow QR and the exact amount, so a list of
  /// generic "you can also pay by cash / e-wallet" rows told the customer
  /// nothing: a static QR has no amount, and cash is handed over in person. What
  /// is genuinely missing when a QR cannot be scanned is the bank account, so
  /// that one line survives - and only if it has been filled in.
  /// Shown when the customer returns from their banking app. It does not claim
  /// the money arrived — it cannot know that — it simply removes the friction of
  /// finding the declaration button again.
  /// Opens the QR on a page of its own: full width, pinch to zoom, and a save
  /// action for the customer who wants to scan later.
  void _showFullScreenQr(String qr, {double? amount, String? reference}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QrFullScreenScreen(
          dataUri: qr,
          amountLabel: amount == null ? null : _money(amount),
          reference: reference,
        ),
      ),
    );
  }

  /// Shown after the declaration is stored, so the customer knows the agent
  /// still has to confirm it against the bank statement.
  /// Opens the hosted checkout page, then records the payment it approved.
  ///
  /// This is the shape of a real integration: the customer leaves the merchant
  /// page, pays on the provider's page, and comes back. Here the provider page
  /// is part of the same app - it looks and reads like a separate checkout, and
  /// the address bar changes on the web - but nothing is charged.
  Future<void> _payNowDialog(double totalBalance) async {
    final data = _data ?? const <String, dynamic> {};

    // A build with Stripe keys sends the customer to the real hosted checkout.
    // If that call fails the simulated page below still runs, so a demo never
    // dead-ends on the network.
    if (PaymentGateway.isConfigured) {
      // Opened here, synchronously, while the click still counts as a gesture.
      // Creating the session takes a round trip, and `window.open` after an
      // await is blocked by the browser.
      final tab = prepareCheckoutTab();

      // The provider should return with `?s=<token>`, but a redirect can drop
      // it. Remember it here so the return can be rebuilt either way.
      rememberPendingToken(widget.token);

      // Point the current history entry at the statement, so a same-tab
      // fallback cannot leave the app (or its login screen) one Back away.
      ensureStatementUrl(widget.token);

      final selectedBill = (data['bills'] as List? ?? const [])
          .whereType<Map>()
          .where((b) => _selected.contains((b['id'] ?? '').toString()))
          .firstOrNull;

      final session = await PaymentGateway().create(
        token: widget.token,
        amount: totalBalance,
        description:
            'Bill payment - ${(data['customerName'] ?? 'customer').toString()}',
        returnUrl: _returnUrlBase(),
        billNo: (selectedBill?['billNo'] ?? '').toString(),
        customerName: (data['customerName'] ?? '').toString(),
      );
      if (session != null) {
        final opened = loadInCheckoutTab(tab, session.url) ||
            await navigateTo(session.url);
        if (!mounted) return;
        setState(() => _sending = opened);
        if (opened) {
          _checkoutTab = tab;
          _startGatewayPoll(session.id, totalBalance);
        }
        return;
      }
      // No session: the prepared tab is not needed and will be closed by the
      // browser when it stays on about:blank.
    }

    if (!mounted) return;
    final outcome = await Navigator.of(context).push<CheckoutOutcome>(
      MaterialPageRoute<CheckoutOutcome>(
        fullscreenDialog: true,
        builder: (_) => CheckoutScreen(
          token: widget.token,
          merchantName: (data['shopName'] ?? '').toString(),
          customerName: (data['customerName'] ?? '').toString(),
          amount: totalBalance,
          reference: (data['reconCode'] ?? '').toString(),
        ),
      ),
    );
    if (outcome == null || !outcome.paid || !mounted) return;

    setState(() => _sending = true);
    try {
      final sent = await _service.declarePayment(
        token: widget.token,
        ownerUid: (data['ownerUid'] ?? '').toString(),
        customerName: (data['customerName'] ?? '').toString(),
        amount: totalBalance,
        note: 'Paid through the demo gateway (${outcome.method})',
        proofImage: null,
        reconCode: (data['reconCode'] ?? '').toString(),
        billIds: _selected.toList(),
        billLabels: const [],
        simulated: true,
        autoConfirm: true,
      );
      if (!sent) {
        throw StateError('This link has no owner. Ask for a new link.');
      }
      if (!mounted) return;
      setState(() {
        _declared = true;
        _gatewayDeclared = true;
        _sending = false;
        _paidNow = totalBalance;
      });
      rememberPendingPayment(
        token: widget.token,
        amount: totalBalance,
        expectedTotal: (_snapshotTotal - totalBalance).clamp(0, _snapshotTotal),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment approved - the agent ledger updates itself.'),
          backgroundColor: _green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $error')),
      );
    }
  }

  /// Where the provider sends the customer back to. On the web that is this
  /// page without its query string; in the app it is the configured origin.
  String _returnUrlBase() {
    const appOrigin = String.fromEnvironment(
      'APP_ORIGIN',
      defaultValue: 'https://changvui.github.io/smartpayla/',
    );
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      final withoutQuery = base.replace(query: '', fragment: '');
      return withoutQuery.toString();
    }
    return appOrigin;
  }

  /// The provider redirects back with `paid=1&session_id=...`. The payment is
  /// only recorded after the Worker has asked Stripe whether that session was
  /// really paid - the query string alone is not evidence.
  Future<void> _handleGatewayReturn(Map<String, dynamic> data) async {
    if (_gatewayHandled) return;
    final params = Uri.base.queryParameters;
    if (params['paid'] != '1' && (params['session_id'] ?? '').isEmpty) return;
    if (!PaymentGateway.isConfigured) {
      setState(() {
        _gatewayNote = 'This build has no gateway keys (STRIPE_CHECKOUT off).';
        _gatewayNoteBad = true;
      });
      return;
    }
    final sessionId = (params['session_id'] ?? '').trim();
    if (sessionId.isEmpty) {
      setState(() {
        _gatewayNote = 'The return URL carried no session id.';
        _gatewayNoteBad = true;
      });
      return;
    }

    _gatewayHandled = true;
    final payment = await PaymentGateway().verify(sessionId);
    if (!mounted) return;

    if (payment == null || !payment.paid) {
      setState(() {
        _gatewayNote = payment == null
            ? 'Could not reach the gateway to verify this payment.'
            : 'The gateway reports "${payment.paid ? 'paid' : 'not paid'}".';
        _gatewayNoteBad = true;
      });
      clearPaymentParams(token: widget.token);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The payment could not be verified. Nothing was charged.'),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final sent = await _service.declarePayment(
        token: widget.token,
        ownerUid: (data['ownerUid'] ?? '').toString(),
        customerName: (data['customerName'] ?? '').toString(),
        amount: payment.amount > 0 ? payment.amount : _totalFrom(data),
        note: 'Stripe ${payment.method} (${payment.reference})',
        proofImage: null,
        reconCode: (data['reconCode'] ?? '').toString(),
        billIds: _selected.toList(),
        billLabels: const [],
        simulated: false,
        autoConfirm: true,
      );
      if (!sent) {
        throw StateError('This link has no owner. Ask for a new link.');
      }
      clearPaymentParams(token: widget.token);
      clearPendingToken();
      // The statement tab is still open in the other window; tell it, then close
      // this tab so the customer lands back where they started.
      notifyPaymentConfirmed(widget.token);
      if (!mounted) return;
      setState(() {
        _declared = true;
        _gatewayDeclared = true;
        _sending = false;
        _paidNow = payment.amount > 0 ? payment.amount : _paidNow;
        rememberPendingPayment(
          token: widget.token,
          amount: _paidNow,
          expectedTotal: (_snapshotTotal - _paidNow).clamp(0, _snapshotTotal),
        );
        _gatewayNote =
            'Verified ${payment.method} · RM ${payment.amount.toStringAsFixed(2)}'
            ' · ${payment.reference}';
        _gatewayNoteBad = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Payment confirmed by Stripe (${payment.method}).'),
          backgroundColor: _green,
        ),
      );
      if (Uri.base.queryParameters['popup'] == '1') {
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        closeCurrentTab();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment recorded elsewhere: $error')),
      );
    }
  }

  double _totalFrom(Map<String, dynamic> data) {
    final bills = data['bills'];
    if (bills is! List) return 0;
    var sum = 0.0;
    for (final bill in bills.whereType<Map>()) {
      sum += (bill['balance'] as num?)?.toDouble() ?? 0;
    }
    return sum;
  }

  Widget _declaredCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _green, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _gatewayDeclared ? 'Payment confirmed' : 'Payment declared',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: _green,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'The agent will check the transfer and confirm it. Your '
                  'balance updates once they do.',
                  style: TextStyle(fontSize: 12, color: _ink, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _returnPrompt(double selectedTotal) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded, color: _green, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Back from your banking app?',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Text(
                  'Confirm the transfer so the agent can match it.',
                  style: TextStyle(fontSize: 11.5, color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _declareDialog(_payAmount(selectedTotal)),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: const Text('I have paid', style: TextStyle(fontSize: 12.5)),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: () => setState(() => _showReturnPrompt = false),
            icon: const Icon(Icons.close_rounded, size: 16, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _actions(double totalBalance, String agentPhone) {
    return Column(
      children: [
        if (_declared) _declaredCard(),
        if (!_declared) ...[
          // Demo gateway: one tap, and the agent's ledger updates itself.
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : () => _payNowDialog(totalBalance),
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.credit_card_rounded, size: 18),
              label: Text(
                'Pay now · RM ${totalBalance.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            PaymentGateway.isConfigured
                ? 'Card or FPX. The payment is confirmed automatically - no '
                      'waiting for the agent.'
                : 'Demo gateway - the payment is confirmed automatically, '
                      'without waiting for the agent.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10.5, color: _muted, height: 1.3),
          ),
          const SizedBox(height: 10),
        ],
        if (!_declared && PaymentGateway.isConfigured)
          TextButton(
            onPressed: _sending ? null : () => _declareDialog(totalBalance),
            style: TextButton.styleFrom(foregroundColor: _muted),
            child: const Text(
              'I paid by transfer instead',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
        if (!_declared && !PaymentGateway.isConfigured)
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => _declareDialog(totalBalance),
            icon: Icon(
              _declared ? Icons.check_circle_rounded : Icons.done_all_rounded,
            ),
            label: Text(
              _declared ? 'Payment declared' : 'I have paid',
              style: const TextStyle(fontSize: 15),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: agentPhone.isEmpty ? null : () => _contact(agentPhone),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Contact the agent'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _declareDialog(double totalBalance) async {
    final amountController = TextEditingController(
      text: totalBalance.toStringAsFixed(2),
    );
    final noteController = TextEditingController();
    String? proof;
    bool proofMissing = false;
    final data = await _future;
    if (data == null || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setSheetState) => AlertDialog(
        title: const Text('I have paid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tell the agent how much you have sent. They will confirm it '
              'against the bank statement.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (RM)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'DuitNow, 6.42 pm',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            // The agent must be able to see that the money moved before they
            // confirm, so a screenshot is captured here and shown to them.
            Row(
              children: [
                if (proof != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _decode(proof!),
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (proof != null) const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await pickImageAsDataUri(context);
                      if (picked == null) return;
                      setSheetState(() {
                        proof = picked;
                        proofMissing = false;
                      });
                    },
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(
                      proof == null ? 'Attach screenshot *' : 'Replace',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
          if (proof != null)
            IconButton(
              onPressed: () => setSheetState(() => proof = null),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
              ],
            ),
            if (proofMissing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Please attach the transfer screenshot so the agent can '
                  'verify the payment.',
                  style: TextStyle(fontSize: 11.5, color: _red),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (proof == null) {
                setSheetState(() => proofMissing = true);
                return;
              }
              final amount =
                  double.tryParse(amountController.text.trim()) ?? 0;
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter an amount above zero')),
                );
                return;
              }
              if (amount > totalBalance + 0.005) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'You cannot pay more than RM '
                      '${totalBalance.toStringAsFixed(2)}',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop();
              setState(() => _sending = true);
              try {
              final sent = await _service.declarePayment(
                token: widget.token,
                ownerUid: (data['ownerUid'] ?? '').toString(),
                customerName: (data['customerName'] ?? '').toString(),
                amount: amount,
                note: noteController.text.trim(),
                proofImage: proof,
                reconCode: (data['reconCode'] ?? '').toString(),
                billIds: _selected.toList(),
                billLabels: (data['bills'] as List? ?? const [])
                    .whereType<Map>()
                    .where(
                      (b) => _selected.contains((b['id'] ?? '').toString()),
                    )
                    .map((b) {
                      final no = (b['billNo'] ?? '').toString();
                      final desc = (b['description'] ?? '').toString();
                      return no.isEmpty ? desc : 'Bill $no';
                    })
                    .toList(),
              );
              if (!sent) {
                throw StateError(
                  'The agent link is missing its owner. Ask for a new link.',
                );
              }
              } catch (error) {
                final raw = error.toString();
                final tooLarge = raw.contains('invalid-argument') ||
                    raw.contains('exceed') ||
                    raw.contains('too large') ||
                    raw.contains('maximum');
                // Android browsers hand back much larger screenshots than iOS.
                // Firestore rejects a document over 1 MiB, so retry once without
                // the image: the claim still reaches the agent.
                if (tooLarge && proof != null) {
                  try {
                    final retried = await _service.declarePayment(
                      token: widget.token,
                      ownerUid: (data['ownerUid'] ?? '').toString(),
                      customerName: (data['customerName'] ?? '').toString(),
                      amount: amount,
                      note: noteController.text.trim(),
                      reconCode: (data['reconCode'] ?? '').toString(),
                      billIds: _selected.toList(),
                      billLabels: const <String>[],
                    );
                    if (!retried) {
                      throw StateError('Claim was not stored');
                    }
                    if (!mounted) return;
                    setState(() {
                      _sending = false;
                      _declared = true;
                      _lastError = null;
                    });
                    _toast(
                      'Payment declared. The screenshot was too large to send, '
                      'so the agent will ask for it.',
                    );
                    return;
                  } catch (_) {
                    // Fall through to the error message below.
                  }
                }
                if (!mounted) return;
                setState(() {
                  _sending = false;
                  _lastError = raw.contains('permission-denied')
                      ? 'The agent has not published the Firestore rules yet, '
                            'so the payment could not be sent.'
                      : raw;
                });
                return;
              }
              if (!mounted) return;
              setState(() {
                _sending = false;
                _declared = true;
              });
              _toast('Thank you — the agent will confirm your payment.');
            },
            child: _sending
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send'),
          ),
        ],
      ),
      ),
    );
  }

  /// Tries to open the TNG eWallet app. A personal DuitNow receive code has no
  /// documented deep link that carries an amount, so the amount and reference
  /// are copied first: the customer pastes them once the app is open.
  Future<void> _contact(String phone) async {
    final opened = await openWhatsApp(
      'Hi, I am looking at my statement.',
      phone: phone,
    );
    if (!opened) _toast('Could not open WhatsApp');
  }

  Future<void> _reload() async {
    final future = _service.fetch(widget.token);
    setState(() => _future = future);
    await future;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _ink,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Uint8List _decode(String dataUri) {
    final comma = dataUri.indexOf(',');
    return base64Decode(comma >= 0 ? dataUri.substring(comma + 1) : dataUri);
  }
}
