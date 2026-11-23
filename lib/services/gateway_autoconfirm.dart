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
  bool _busy = false;

  @override
  void build() {
    ref.listen(pendingClaimsProvider, (previous, next) {
      final claims = next.valueOrNull;
      if (claims == null || claims.isEmpty) return;
      for (final claim in claims) {
        if (claim['autoConfirm'] != true) continue;
        final id = (claim['id'] ?? '').toString();
        if (id.isEmpty || _handled.contains(id)) continue;
        _handled.add(id);
        _confirm(claim);
      }
    });
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
            method: (claim['note'] ?? '').toString().contains('Card')
                ? 'Card'
                : 'DuitNow',
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

final gatewayAutoConfirmProvider =
    NotifierProvider<GatewayAutoConfirm, void>(GatewayAutoConfirm.new);
