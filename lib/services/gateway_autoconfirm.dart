import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'payment_receipt.dart';

/// Confirms payments that a gateway already verified.
///
/// A real gateway calls a webhook and the server writes the payment. This build
/// has no merchant account, so the "gateway" is simulated: the customer's
/// payment is written as a claim flagged `autoConfirm`, and the signed-in agent
/// client performs the confirmation the webhook would have performed. The money
/// path is identical - a payment entry with a receipt number is written - only
/// the trigger differs.
class GatewayAutoConfirm extends Notifier<void> {
  final Set<String> _handled = {};
  final Map<String, String> _publishedPending = {};
  bool _busy = false;

  @override
  void build() {
    ref.listen(pendingClaimsProvider, (previous, next) {
      final claims = next.valueOrNull;
      if (claims == null) return;
      // Declared transfers are mirrored onto the statement so a customer on
      // another device sees the same waiting notice.
      _publishPending(claims);
      if (claims.isEmpty) return;
      for (final claim in claims) {
        if (claim['autoConfirm'] != true) continue;
        final id = (claim['id'] ?? '').toString();
        if (id.isEmpty || _handled.contains(id)) continue;
        _handled.add(id);
        _confirm(claim);
      }
    });
  }


  /// Writes the pending declarations per statement, and clears a statement
  /// once nothing is waiting for it any more.
  Future<void> _publishPending(List<Map<String, dynamic>> claims) async {
    final byToken = <String, List<Map<String, dynamic>>>{};
    for (final claim in claims) {
      if (claim['autoConfirm'] == true) continue;
      if ((claim['status'] ?? 'pending').toString() != 'pending') continue;
      final token = (claim['token'] ?? '').toString();
      if (token.isEmpty) continue;
      byToken.putIfAbsent(token, () => []).add({
        'amount': (claim['amount'] as num?)?.toDouble() ?? 0,
        'at': (claim['declaredAt'] ?? '').toString(),
        'billIds': (claim['billIds'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        'claimId': (claim['id'] ?? '').toString(),
      });
    }

    final service = ref.read(statementServiceProvider);

    for (final entry in byToken.entries) {
      final signature = jsonEncode(entry.value);
      if (_publishedPending[entry.key] == signature) continue;
      _publishedPending[entry.key] = signature;
      await service.publishPending(token: entry.key, entries: entry.value);
    }

    for (final token in _publishedPending.keys.toList()) {
      if (byToken.containsKey(token)) continue;
      _publishedPending.remove(token);
      await service.publishPending(token: token, entries: const []);
    }
  }

  Future<void> _confirm(Map<String, dynamic> claim) async {
    if (_busy) return;
    _busy = true;
    try {
      final transactions =
          ref.read(transactionsProvider).valueOrNull ?? const [];
      final payments = ref.read(paymentServiceProvider);
      final owner = ref.read(dataOwnerProvider);

      // A gateway leaves a receipt behind; without one the agent's payment
      // history would have a blank evidence slot for every automatic payment.
      Map<String, dynamic> enriched = claim;
      if ((claim['proofImage'] ?? '').toString().isEmpty) {
        try {
          final settings = ref.read(settingsProvider);
          final receipt = await PaymentReceipt.gatewayReceipt(
            shopName: settings.shopName,
            customerName: (claim['customerName'] ?? '').toString(),
            amount: (claim['amount'] as num?)?.toDouble() ?? 0,
            method: _methodOf((claim['note'] ?? '').toString()),
            reference: (claim['reconCode'] ?? claim['token'] ?? '').toString(),
            paidAt: DateTime.tryParse(
                  (claim['declaredAt'] ?? '').toString(),
                ) ??
                DateTime.now(),
            simulated: claim['simulated'] != false,
          );
          enriched = {...claim, 'proofImage': receipt};
        } catch (error) {
          debugPrint('Receipt render failed: $error');
        }
      }

      final ok = await payments.confirmClaim(
        ownerUid: owner,
        transactions: transactions,
        claim: enriched,
      );
      if (!ok) return;
      // The ledger changed underneath the transaction list; reload so the
      // dashboard, aging and statement all agree.
      await ref.read(transactionsProvider.notifier).refresh();
      final customer = (claim['customerName'] ?? '').toString();
      if (customer.isNotEmpty) {
        // The customer's page is a published snapshot; republish it so the
        // customer sees the balance clear without asking.
        await ref.read(transactionsProvider.notifier).syncStatementFor(customer);
      }
    } catch (error) {
      debugPrint('Gateway auto-confirm failed: $error');
    } finally {
      _busy = false;
    }
  }
}

String _methodOf(String note) {
  final value = note.toLowerCase();
  if (value.contains('fpx')) return 'FPX';
  if (value.contains('card')) return 'Card';
  if (value.contains('duitnow')) return 'DuitNow';
  return 'Gateway';
}

final gatewayAutoConfirmProvider =
    NotifierProvider<GatewayAutoConfirm, void>(GatewayAutoConfirm.new);
