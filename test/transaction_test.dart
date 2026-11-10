import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpayla/data/transaction_repository.dart';
import 'package:smartpayla/models/transaction.dart';

Transaction buildTransaction({
  required DateTime dueDate,
  PaymentStatus status = PaymentStatus.unpaid,
  double total = 1000,
  double advance = 0,
}) {
  final now = DateTime.now();
  return Transaction(
    id: 't1',
    customerName: 'Test Customer',
    itemDescription: 'Test item',
    totalAmount: total,
    advancePaid: advance,
    dueDate: dueDate,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('Transaction money', () {
    test('balanceDue is total minus advance', () {
      final t = buildTransaction(
        dueDate: DateTime.now().add(const Duration(days: 7)),
        total: 1200,
        advance: 400,
      );
      expect(t.balanceDue, 800);
    });

    test('balanceDue never goes below zero', () {
      final t = buildTransaction(
        dueDate: DateTime.now(),
        total: 500,
        advance: 700,
      );
      expect(t.balanceDue, 0);
    });
  });

  group('Aging', () {
    test('not overdue when due date is in the future', () {
      final t = buildTransaction(
        dueDate: DateTime.now().add(const Duration(days: 5)),
      );
      expect(t.daysOverdue, 0);
      expect(t.isOverdue, isFalse);
      expect(t.agingBucket, AgingBucket.current);
    });

    test('31-60 days bucket', () {
      final t = buildTransaction(
        dueDate: DateTime.now().subtract(const Duration(days: 45)),
      );
      expect(t.daysOverdue, greaterThanOrEqualTo(44));
      expect(t.agingBucket, AgingBucket.days31to60);
      expect(t.displayStatus, 'Overdue');
    });

    test('60+ days bucket', () {
      final t = buildTransaction(
        dueDate: DateTime.now().subtract(const Duration(days: 75)),
      );
      expect(t.agingBucket, AgingBucket.days60plus);
    });

    test('paid transactions are not overdue', () {
      final t = buildTransaction(
        dueDate: DateTime.now().subtract(const Duration(days: 90)),
        status: PaymentStatus.paid,
        advance: 1000,
      );
      expect(t.isOverdue, isFalse);
      expect(t.agingBucket, AgingBucket.paid);
      expect(t.displayStatus, 'Paid');
    });
  });

  test('JSON round-trip keeps the important fields', () {
    final t = buildTransaction(
      dueDate: DateTime(2026, 11, 20),
      status: PaymentStatus.partial,
      total: 900,
      advance: 300,
    );
    final copy = Transaction.fromJson(t.toJson());
    expect(copy.id, t.id);
    expect(copy.customerName, t.customerName);
    expect(copy.totalAmount, t.totalAmount);
    expect(copy.advancePaid, t.advancePaid);
    expect(copy.status, t.status);
    expect(copy.dueDate, t.dueDate);
  });

  test('billDate prefers cash bill, then invoice, then createdAt', () {
    final base = buildTransaction(
      dueDate: DateTime(2026, 11, 20),
    );
    expect(base.billDate, base.createdAt);

    final withInvoice = base.copyWith(invoiceDate: DateTime(2026, 9, 3));
    expect(withInvoice.billDate, DateTime(2026, 9, 3));

    final withCashBill =
        withInvoice.copyWith(cashBillDate: DateTime(2026, 8, 1));
    expect(withCashBill.billDate, DateTime(2026, 8, 1));
  });

  test('local repository saves, reloads and deletes', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalTransactionRepository(prefs);
    final t = buildTransaction(
      dueDate: DateTime(2026, 12, 1),
      total: 500,
      advance: 100,
    );

    await repo.save(t);
    final loaded = await repo.getAll();
    expect(loaded, hasLength(1));
    expect(loaded.first.customerName, 'Test Customer');
    expect(loaded.first.balanceDue, 400);

    final updated = t.copyWith(status: PaymentStatus.paid, advancePaid: 500);
    await repo.save(updated);
    final afterUpdate = await repo.getAll();
    expect(afterUpdate, hasLength(1));
    expect(afterUpdate.first.status, PaymentStatus.paid);
    expect(afterUpdate.first.balanceDue, 0);

    await repo.delete(t.id);
    expect(await repo.getAll(), isEmpty);
  });

  test('demo seed only fills an empty ledger', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = LocalTransactionRepository(prefs);

    expect(await repo.seedDemo(), isTrue);
    expect(await repo.getAll(), hasLength(5));
    expect(await repo.seedDemo(), isFalse);
    expect(await repo.getAll(), hasLength(5));
  });
}
