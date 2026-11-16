import 'dart:math';

import '../models/payment.dart';
import '../models/transaction.dart';

/// Pure helpers that turn a list of payments into the numbers the interface
/// shows. Keeping them here means the balance and the status can never drift
/// apart: both are computed by the same function from the same ledger.
class PaymentLedger {
  /// Sum of the payments that actually count (confirmed only).
  static double paidTotal(Iterable<Payment> payments) {
    return payments
        .where((p) => p.countsTowardsBalance)
        .fold(0.0, (sum, p) => sum + p.amount);
  }

  /// Status is derived, never typed by hand.
  static PaymentStatus statusFor(double paid, double total) {
    if (total <= 0) return PaymentStatus.unpaid;
    if (paid >= total - 0.005) return PaymentStatus.paid;
    if (paid > 0.005) return PaymentStatus.partial;
    return PaymentStatus.unpaid;
  }

  static ({double paid, PaymentStatus status}) totals(
    Iterable<Payment> payments,
    double total,
  ) {
    final paid = paidTotal(payments);
    return (paid: paid, status: statusFor(paid, total));
  }

  /// Receipt numbers are generated on the device (`RCP-261116-7F3A`) so a cash
  /// payment can be recorded offline. A random suffix replaces a server-side
  /// counter, which would require a network round trip.
  static String newReceiptNo(DateTime at, {Random? random}) {
    final rng = random ?? Random.secure();
    const alphabet = '0123456789ABCDEF';
    final suffix = List.generate(
      4,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
    final y = at.year.toString().substring(2);
    final m = at.month.toString().padLeft(2, '0');
    final d = at.day.toString().padLeft(2, '0');
    return 'RCP-$y$m$d-$suffix';
  }

  /// Short code the customer types into the DuitNow transfer reference.
  static String newReconCode({Random? random}) {
    final rng = random ?? Random.secure();
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final body = List.generate(
      4,
      (_) => alphabet[rng.nextInt(alphabet.length)],
    ).join();
    return 'SPL-$body';
  }

  /// A payment rail that came through the statement link. When one exists the
  /// status must be changed by voiding that payment, not by editing the record.
  static bool hasOnlinePayment(Iterable<Payment> payments) {
    return payments.any(
      (p) => p.state == PaymentState.confirmed && p.method.isOnline,
    );
  }

  /// Allocate an amount across transactions, oldest due date first. Returns the
  /// per-transaction amounts so the caller can write one payment per bill.
  static Map<String, double> allocateOldestFirst(
    List<Transaction> open,
    double amount,
  ) {
    final result = <String, double>{};
    var left = amount;
    final sorted = [...open]
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    for (final txn in sorted) {
      if (left <= 0.005) break;
      final due = txn.balanceDue;
      if (due <= 0.005) continue;
      final applied = left < due ? left : due;
      result[txn.id] = applied;
      left -= applied;
    }
    return result;
  }
}
