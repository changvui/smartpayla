import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders a payment receipt as a PNG data URI.
///
/// A real gateway returns a receipt: amount, method, reference and time. The
/// demo gateway should not leave the agent's payment history blank just because
/// no human photographed anything, so the receipt is drawn here and attached to
/// the payment entry as its evidence.
///
/// Drawn with dart:ui rather than a widget tree: it needs no BuildContext, it
/// works on the web as well as on Android, and it cannot be affected by the
/// theme on the device that happens to run it.
class PaymentReceipt {
  static const int _width = 720;
  static const int _height = 1040;

  static Future<String> gatewayReceipt({
    required String shopName,
    required String customerName,
    required double amount,
    required String method,
    required String reference,
    required DateTime paidAt,
    bool simulated = true,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const width = _width * 1.0;
    const height = _height * 1.0;

    // Paper
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(24, 24, width - 48, height - 48),
      Paint()
        ..color = const Color(0xFFDCE5F5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Header band
    canvas.drawRect(
      Rect.fromLTWH(24, 24, width - 48, 120),
      Paint()..color = const Color(0xFF0B6B5B),
    );

    _text(
      canvas,
      shopName.isEmpty ? 'SmartPayLA' : shopName,
      48,
      62,
      size: 34,
      bold: true,
      color: const Color(0xFFFFFFFF),
    );
    _text(
      canvas,
      'PAYMENT RECEIPT',
      48,
      106,
      size: 18,
      color: const Color(0xFFCCE7E1),
    );

    var y = 190.0;
    _text(canvas, 'Amount paid', 48, y, size: 18, color: const Color(0xFF64748B));
    y += 34;
    _text(
      canvas,
      'RM ${amount.toStringAsFixed(2)}',
      48,
      y,
      size: 52,
      bold: true,
      color: const Color(0xFF0F172A),
    );

    y += 110;
    _rule(canvas, y, width);
    y += 26;

    final rows = <(String, String)>[
      ('Customer', customerName.isEmpty ? 'Walk-in customer' : customerName),
      ('Method', method.isEmpty ? 'DuitNow' : method),
      ('Reference', reference.isEmpty ? '-' : reference),
      ('Paid at', _stamp(paidAt)),
      if (simulated) ('Channel', 'Demo gateway (simulated)'),
    ];

    for (final (label, value) in rows) {
      _text(canvas, label, 48, y, size: 17, color: const Color(0xFF64748B));
      _textRight(
        canvas,
        value,
        width - 48,
        y,
        size: 19,
        bold: true,
        color: const Color(0xFF0F172A),
      );
      y += 46;
    }

    y += 10;
    _rule(canvas, y, width);
    y += 30;

    if (simulated) {
      // Honest label: no money moved, and nobody should mistake this for a bank
      // receipt.
      final boxRect = Rect.fromLTWH(48, y, width - 96, 96);
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(12)),
        Paint()..color = const Color(0xFFFEF3C7),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(12)),
        Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _text(
        canvas,
        'SIMULATED PAYMENT',
        72,
        y + 26,
        size: 20,
        bold: true,
        color: const Color(0xFF92400E),
      );
      _text(
        canvas,
        'Demo gateway - no money left any account.',
        72,
        y + 58,
        size: 16,
        color: const Color(0xFF92400E),
      );
      y += 130;
    }

    _text(
      canvas,
      'Verified by the payment gateway.',
      48,
      height - 120,
      size: 15,
      color: const Color(0xFF64748B),
    );
    _text(
      canvas,
      'SmartPayLA - generated ${_stamp(DateTime.now())}',
      48,
      height - 92,
      size: 14,
      color: const Color(0xFF94A3B8),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width, _height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('Could not render the receipt');
    return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
  }

  static String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.day}/${two(at.month)}/${at.year} ${two(at.hour)}:${two(at.minute)}';
  }

  static void _rule(Canvas canvas, double y, double width) {
    canvas.drawLine(
      Offset(48, y),
      Offset(width - 48, y),
      Paint()
        ..color = const Color(0xFFE2E8F0)
        ..strokeWidth = 2,
    );
  }

  static TextPainter _painter(
    String text,
    double size, {
    bool bold = false,
    Color color = const Color(0xFF0F172A),
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          color: color,
          fontFamily: 'Roboto',
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 460);
  }

  static void _text(
    Canvas canvas,
    String text,
    double x,
    double y, {
    double size = 18,
    bool bold = false,
    Color color = const Color(0xFF0F172A),
  }) {
    _painter(text, size, bold: bold, color: color).paint(canvas, Offset(x, y));
  }

  static void _textRight(
    Canvas canvas,
    String text,
    double right,
    double y, {
    double size = 18,
    bool bold = false,
    Color color = const Color(0xFF0F172A),
  }) {
    final painter = _painter(text, size, bold: bold, color: color);
    painter.paint(canvas, Offset(right - painter.width, y));
    painter.dispose();
  }
}
