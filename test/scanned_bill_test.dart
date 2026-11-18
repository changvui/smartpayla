import 'package:flutter_test/flutter_test.dart';
import 'package:smartpayla/services/scanned_bill.dart';

void main() {
  group('ScannedBill items', () {
    test('reads quantity and unit price per printed line', () {
      final bill = ScannedBill.fromMap({
        'is_bill': true,
        'total': 80.0,
        'items': [
          {'description': 'Notebook A5', 'qty': 2, 'unit_price': 15.0, 'amount': 30.0},
          {'description': 'Gel Pen Box', 'qty': 1, 'unit_price': 25.0, 'amount': 25.0},
        ],
      });

      expect(bill.items, hasLength(2));
      expect(bill.items.first.description, 'Notebook A5');
      expect(bill.items.first.qty, 2);
      expect(bill.items.first.linePrice, 15.0);
      expect(bill.items.last.qty, 1);
    });

    test('falls back to the line amount when no unit price is printed', () {
      final bill = ScannedBill.fromMap({
        'is_bill': true,
        'items': [
          {'description': 'A4 Paper', 'amount': '25.00'},
        ],
      });

      expect(bill.items.single.qty, isNull);
      expect(bill.items.single.linePrice, 25.0);
    });

    test('ignores malformed rows instead of failing the scan', () {
      final bill = ScannedBill.fromMap({
        'is_bill': true,
        'items': [
          'not a map',
          {'description': '  '},
          {'description': 'Stapler', 'qty': 0, 'amount': 12.5},
        ],
      });

      expect(bill.items, hasLength(1));
      expect(bill.items.single.description, 'Stapler');
      expect(bill.items.single.qty, isNull);
    });
  });
}
