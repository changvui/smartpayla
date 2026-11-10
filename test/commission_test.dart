import 'package:flutter_test/flutter_test.dart';
import 'package:smartpayla/models/transaction.dart';
import 'package:smartpayla/services/commission_engine.dart';

Transaction tx({
  required String id,
  required DateTime billDate,
  required PaymentStatus status,
  required double total,
}) {
  return Transaction(
    id: id,
    customerName: 'Customer $id',
    itemDescription: 'Item $id',
    totalAmount: total,
    advancePaid: status == PaymentStatus.paid ? total : 0,
    dueDate: billDate.add(const Duration(days: 14)),
    status: status,
    createdAt: billDate,
    updatedAt: billDate,
    cashBillDate: billDate,
  );
}

void main() {
  final october = DateTime(2026, 10, 5);
  final november = DateTime(2026, 11, 3);
  final september = DateTime(2026, 9, 20);

  final transactions = [
    tx(id: 'a', billDate: october, status: PaymentStatus.paid, total: 1000),
    tx(id: 'b', billDate: november, status: PaymentStatus.unpaid, total: 500),
    tx(id: 'c', billDate: september, status: PaymentStatus.paid, total: 200),
  ];

  test('all-time commission counts paid transactions only', () {
    final report = const CommissionEngine().build(
      transactions: transactions,
      rate: 0.05,
    );
    expect(report.earned, closeTo(60, 0.001));
    expect(report.potential, closeTo(25, 0.001));
    expect(report.paidCount, 2);
    expect(report.openCount, 1);
    expect(report.lines.length, 2);
  });

  test('month filter applies to bill date', () {
    final report = const CommissionEngine().build(
      transactions: transactions,
      rate: 0.05,
      month: october,
    );
    expect(report.earned, closeTo(50, 0.001));
    expect(report.paidCount, 1);
    expect(report.lines.single.transaction.id, 'a');
  });

  test('months are unique and newest first', () {
    final months = CommissionEngine.monthsIn(transactions);
    expect(months.length, 3);
    expect(months.first.year, 2026);
    expect(months.first.month, 11);
  });
}
