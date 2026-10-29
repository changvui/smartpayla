import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder.dart';
import '../models/transaction.dart';
import '../services/commission_engine.dart';
import '../state/providers.dart';

/// Read-only contract for the partner modules (authentication, customer,
/// OCR/receipts, reminder history and settings). The partner code should depend
/// on these providers instead of reaching into this module's widgets.
final partnerTransactionsProvider = Provider<List<Transaction>>((ref) {
  return ref.watch(transactionsProvider).valueOrNull ?? const [];
});

final partnerCommissionProvider = Provider<CommissionReport>((ref) {
  final transactions = ref.watch(partnerTransactionsProvider);
  final rate = ref.watch(settingsProvider).commissionRate;
  return const CommissionEngine().build(
    transactions: transactions,
    rate: rate,
  );
});

final partnerOverdueProvider = Provider<List<Transaction>>((ref) {
  final transactions = ref.watch(partnerTransactionsProvider);
  return transactions.where((t) => t.isOverdue).toList();
});

final partnerReminderHistoryProvider = Provider<List<ReminderRecord>>((ref) {
  return ref.watch(reminderHistoryProvider).valueOrNull ?? const [];
});

/// Payload helpers so the partner module does not copy field names by hand.
class PartnerBridge {
  PartnerBridge._();

  static const firestoreCollection =
      'users/{userId}/transactions/{transactionId}';

  static Map<String, dynamic> transaction(Transaction value) => value.toJson();

  static Map<String, dynamic> commission(CommissionReport report) => {
        'rate': report.rate,
        'earned': report.earned,
        'potential': report.potential,
        'paidCount': report.paidCount,
        'openCount': report.openCount,
        'lines': report.lines
            .map(
              (line) => {
                'transactionId': line.transaction.id,
                'amount': line.commission,
                'sale': line.transaction.totalAmount,
              },
            )
            .toList(),
      };

  static Map<String, dynamic> reminder(ReminderRecord record) =>
      record.toJson();
}
