import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartpayla/services/receipt_pdf.dart';

void main() {
  test('builds a one-page receipt PDF', () {
    final bytes = ReceiptPdf.build(
      shopName: 'Kedai Ah Seng',
      customerName: 'Kerry',
      amount: 50,
      method: 'Card',
      reference: 'WLUYQCDHIALX',
      billNo: 'CB-261116-2520',
      paidAt: '27/11/2026 16:05',
      billTotal: 335,
      paidBefore: 12,
      remaining: 273,
    );

    final text = String.fromCharCodes(bytes);
    expect(text.startsWith('%PDF-1.4'), isTrue);
    expect(text.contains('/Type /Catalog'), isTrue);
    expect(text.contains('Kedai Ah Seng'), isTrue);
    expect(text.contains('RM 50.00'), isTrue);
    expect(text.contains('Remaining after'), isTrue);
    expect(text.trimRight().endsWith('%%EOF'), isTrue);

    // A visual check during development, and proof the file opens.
    final out = File('build/receipt_preview.pdf');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  });
}
