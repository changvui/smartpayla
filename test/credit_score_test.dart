import 'package:flutter_test/flutter_test.dart';
import 'package:smartpayla/models/transaction.dart';
import 'package:smartpayla/services/credit_score.dart';

Transaction _txn({
  required String id,
  required double total,
  required double paid,
  required DateTime due,
  DateTime? finished,
  DateTime? updated,
}) {
  final now = DateTime.now();
  return Transaction(
    id: id,
    customerName: 'Test',
    itemDescription: 'Item',
    totalAmount: total,
    advancePaid: paid,
    dueDate: due,
    status: paid >= total
        ? PaymentStatus.paid
        : (paid > 0 ? PaymentStatus.partial : PaymentStatus.unpaid),
    createdAt: now,
    updatedAt: updated ?? now,
    finishDate: finished,
  );
}

void main() {
  group('CustomerCredit', () {
    test('settled on time scores an A', () {
      final now = DateTime.now();
      final credit = CustomerCredit.compute([
        _txn(
          id: 'a',
          total: 100,
          paid: 100,
          due: now.subtract(const Duration(days: 10)),
          finished: now.subtract(const Duration(days: 12)),
          updated: now.subtract(const Duration(days: 12)),
        ),
      ]);
      expect(credit.band, 'A');
      expect(credit.score, greaterThanOrEqualTo(80));
      expect(credit.outstanding, 0);
    });

    test('long overdue debt drops the score', () {
      final now = DateTime.now();
      final credit = CustomerCredit.compute([
        _txn(
          id: 'b',
          total: 1000,
          paid: 0,
          due: now.subtract(const Duration(days: 90)),
          updated: now.subtract(const Duration(days: 90)),
        ),
      ]);
      expect(credit.overdueBills, 1);
      expect(credit.worstOverdueDays, greaterThanOrEqualTo(89));
      expect(credit.score, lessThan(40));
      expect(credit.band, 'D');
    });

    test('a part payment scores better than nothing paid', () {
      final now = DateTime.now();
      final partial = CustomerCredit.compute([
        _txn(
          id: 'c',
          total: 1000,
          paid: 500,
          due: now.subtract(const Duration(days: 20)),
          updated: now,
        ),
      ]);
      final nothing = CustomerCredit.compute([
        _txn(
          id: 'd',
          total: 1000,
          paid: 0,
          due: now.subtract(const Duration(days: 20)),
          updated: now,
        ),
      ]);
      expect(partial.score, greaterThan(nothing.score));
    });

    test('no transactions yields the neutral band', () {
      final credit = CustomerCredit.compute(const []);
      expect(credit.band, '—');
      expect(credit.hasHistory, isFalse);
    });

    test('explanation mentions the overdue days', () {
      final now = DateTime.now();
      final credit = CustomerCredit.compute([
        _txn(
          id: 'e',
          total: 500,
          paid: 0,
          due: now.subtract(const Duration(days: 45)),
          updated: now,
        ),
      ]);
      expect(credit.explanation, contains('45 days'));
    });
  });
}
