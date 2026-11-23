import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartpayla/services/payment_receipt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // The test environment ships a placeholder font that draws solid blocks.
    // Load a real one so the preview is readable during development.
    final candidates = [
      'C:/Windows/Fonts/arial.ttf',
      'C:/Windows/Fonts/segoeui.ttf',
    ];
    for (final path in candidates) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(file.readAsBytesSync()),
          ),
        );
      await loader.load();
      break;
    }
  });

  test('renders a receipt image', () async {
    final dataUri = await PaymentReceipt.gatewayReceipt(
      shopName: 'Kedai Ah Seng',
      customerName: 'Kerry',
      amount: 335,
      method: 'DuitNow',
      reference: 'CB-261116-2520',
      paidAt: DateTime(2026, 11, 23, 15, 4),
      simulated: true,
    );

    expect(dataUri.startsWith('data:image/png;base64,'), isTrue);
    final bytes = Uri.parse(dataUri).data!.contentAsBytes();
    expect(bytes.length, greaterThan(1000));

    // Written for a visual check during development.
    final out = File('build/receipt_preview.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes);
  });
}
