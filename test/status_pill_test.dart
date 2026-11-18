import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartpayla/models/transaction.dart';
import 'package:smartpayla/theme.dart';
import 'package:smartpayla/widgets/common.dart';

Transaction _bill({
  required DateTime dueDate,
  double total = 100,
  double advance = 0,
  PaymentStatus status = PaymentStatus.unpaid,
}) {
  final now = DateTime.now();
  return Transaction(
    id: 't1',
    customerName: 'Kerry',
    itemDescription: 'Notebook',
    totalAmount: total,
    advancePaid: advance,
    dueDate: dueDate,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  final today = DateTime.now();
  DateTime daysFromNow(int days) => today.add(Duration(days: days));

  group('status colour encodes urgency', () {
    test('on time is neutral, not warm', () {
      expect(statusColor('Unpaid'), AppColors.slate);
      expect(statusColor('Unpaid'), isNot(AppColors.orange));
      expect(statusColor('Unpaid'), isNot(AppColors.red));
    });

    test('amber is reserved for a bill that is nearly due', () {
      expect(statusColor('Due soon'), AppColors.amber);
    });

    test('overdue keeps the only alarm colour', () {
      expect(statusColor('Overdue'), AppColors.red);
    });

    test('settled and partial stay green and blue', () {
      expect(statusColor('Paid'), AppColors.green);
      expect(statusColor('Partial'), AppColors.blue);
    });

    test('the ladder is ordered by urgency, with no repeated colour', () {
      final ladder = [
        statusColor('Paid'),
        statusColor('Partial'),
        statusColor('Unpaid'),
        statusColor('Due soon'),
        statusColor('Overdue'),
      ];
      expect(ladder.toSet(), hasLength(ladder.length));
    });
  });

  group('displayStatus', () {
    test('a bill due within a week is called out before it is late', () {
      expect(_bill(dueDate: daysFromNow(3)).displayStatus, 'Due soon');
      expect(_bill(dueDate: today).displayStatus, 'Due soon');
    });

    test('a bill due later stays Unpaid', () {
      expect(_bill(dueDate: daysFromNow(20)).displayStatus, 'Unpaid');
    });

    test('overdue beats due-soon', () {
      expect(_bill(dueDate: daysFromNow(-3)).displayStatus, 'Overdue');
    });

    test('a partially paid bill keeps its own label', () {
      final bill = _bill(
        dueDate: daysFromNow(3),
        advance: 40,
        status: PaymentStatus.partial,
      );
      expect(bill.displayStatus, 'Partial');
    });
  });

  testWidgets('the pill carries an icon, so colour is not the only signal',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusPill(label: 'Unpaid', compact: true)),
      ),
    );

    expect(find.byIcon(statusIcon('Unpaid')), findsOneWidget);
    expect(find.text('Unpaid'), findsOneWidget);
  });
}
