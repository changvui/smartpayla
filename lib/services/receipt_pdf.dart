import 'dart:convert';
import 'dart:typed_data';

/// A very small PDF writer, enough for a one-page receipt.
///
/// Written by hand instead of pulling in a PDF package: the receipt is a fixed
/// A4 page of Helvetica text and one filled rectangle, the build has no network
/// to fetch dependencies, and this keeps the web bundle small.
class ReceiptPdf {
  ReceiptPdf._();

  static const double _pageWidth = 595; // A4 at 72 dpi
  static const double _pageHeight = 842;

  static const _ink = '0.06 0.09 0.16';
  static const _muted = '0.39 0.45 0.55';
  static const _green = '0.03 0.42 0.36';

  /// Builds the document. Every string is plain ASCII; the caller is expected to
  /// keep the shop and customer names in Latin script.
  static Uint8List build({
    required String shopName,
    required String customerName,
    required double amount,
    required String method,
    required String reference,
    required String billNo,
    required String paidAt,
    double? billTotal,
    double? paidBefore,
    double? remaining,
    bool simulated = false,
  }) {
    final content = StringBuffer();

    // Header band
    content.writeln('q $_green rg 0 ${_pageHeight - 96} $_pageWidth 96 re f Q');
    _text(content, shopName.isEmpty ? 'SmartPayLA' : shopName,
        x: 48, y: _pageHeight - 46, size: 20, bold: true, color: '1 1 1');
    _text(content, 'PAYMENT RECEIPT',
        x: 48, y: _pageHeight - 74, size: 10, color: '0.85 0.94 0.92');

    // Amount
    _text(content, 'Amount paid', x: 48, y: _pageHeight - 140, size: 10, color: _muted);
    _text(content, 'RM ${amount.toStringAsFixed(2)}',
        x: 48, y: _pageHeight - 176, size: 30, bold: true, color: _ink);

    var y = _pageHeight - 220.0;
    _rule(content, y);
    y -= 28;

    _row(content, 'Customer', customerName.isEmpty ? 'Walk-in customer' : customerName, y);
    y -= 22;
    _row(content, 'Bill number', billNo, y);
    y -= 22;
    _row(content, 'Method', method, y);
    y -= 22;
    _row(content, 'Gateway reference', reference, y);
    y -= 22;
    _row(content, 'Paid at', paidAt, y);

    if (billTotal != null) {
      y -= 34;
      _rule(content, y);
      y -= 26;
      _row(content, 'Bill total', 'RM ${billTotal.toStringAsFixed(2)}', y);
      if (paidBefore != null) {
        y -= 22;
        _row(content, 'Paid before this', 'RM ${paidBefore.toStringAsFixed(2)}', y);
      }
      y -= 22;
      _row(content, 'This payment', 'RM ${amount.toStringAsFixed(2)}', y);
      if (remaining != null) {
        y -= 22;
        _row(content, 'Remaining after', 'RM ${remaining.toStringAsFixed(2)}', y,
            bold: true);
      }
    }

    if (simulated) {
      y -= 40;
      content.writeln('q 0.99 0.95 0.78 rg 48 $y ${_pageWidth - 96} 56 re f Q');
      content.writeln('q 0.96 0.62 0.04 RG 2 w 48 $y ${_pageWidth - 96} 56 re S Q');
      _text(content, 'SIMULATED PAYMENT',
          x: 64, y: y + 32, size: 12, bold: true, color: '0.57 0.25 0.05');
      _text(content, 'Demo gateway - no money left any account.',
          x: 64, y: y + 14, size: 9, color: '0.57 0.25 0.05');
    }

    // Footer
    _text(content, 'Verified by the payment gateway.',
        x: 48, y: 92, size: 9, color: _muted);
    _text(content, 'SmartPayLA - generated ${_nowStamp()}',
        x: 48, y: 76, size: 8, color: _muted);

    return _assemble(content.toString());
  }

  static String _nowStamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.day}/${two(now.month)}/${now.year} ${two(now.hour)}:${two(now.minute)}';
  }

  static void _text(
    StringBuffer out,
    String text, {
    required double x,
    required double y,
    double size = 11,
    bool bold = false,
    String color = _ink,
  }) {
    final font = bold ? '/F2' : '/F1';
    out.writeln('BT $color rg $font ${size.toStringAsFixed(1)} Tf '
        '1 0 0 1 ${x.toStringAsFixed(1)} ${y.toStringAsFixed(1)} Tm '
        '(${_escape(text)}) Tj ET');
  }

  static void _row(
    StringBuffer out,
    String label,
    String value,
    double y, {
    bool bold = false,
  }) {
    _text(out, label, x: 48, y: y, size: 10.5, color: _muted);
    // Right-align by estimating the width; Helvetica averages 0.52 em.
    final width = value.length * 10.5 * 0.52;
    final x = (595 - 48 - width).clamp(48.0, 500.0);
    _text(out, value, x: x, y: y, size: 10.5, bold: bold);
  }

  static void _rule(StringBuffer out, double y) {
    out.writeln('q 0.89 0.91 0.94 RG 0.8 w 48 ${y.toStringAsFixed(1)} m '
        '${(595 - 48).toStringAsFixed(1)} ${y.toStringAsFixed(1)} l S Q');
  }

  static String _escape(String value) {
    // Keep the PDF indexable and simple: Latin script only.
    final ascii = value
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '?')
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    return ascii;
  }

  static Uint8List _assemble(String content) {
    final objects = <String>[
      '<< /Type /Catalog /Pages 2 0 R >>',
      '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${_pageWidth.toInt()} '
          '${_pageHeight.toInt()}] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> '
          '/Contents 6 0 R >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
      '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
      '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    ];

    final buffer = StringBuffer('%PDF-1.4\n');
    final offsets = <int>[];

    for (var i = 0; i < objects.length; i++) {
      offsets.add(buffer.length);
      buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
    }

    final xrefStart = buffer.length;
    buffer.write('xref\n0 ${objects.length + 1}\n');
    buffer.write('0000000000 65535 f \n');
    for (final offset in offsets) {
      buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
    }
    buffer.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
    buffer.write('startxref\n$xrefStart\n%%EOF\n');

    return Uint8List.fromList(latin1.encode(buffer.toString()));
  }
}
