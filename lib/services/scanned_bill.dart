import 'dart:convert';

/// What a scan read off a cash bill / invoice.
///
/// Shared by both engines (ML Kit on a phone, the Worker on the web) so the
/// rest of the app does not care which one produced it.
class ScannedBill {
  const ScannedBill({
    required this.isBill,
    this.customer,
    this.vendor,
    this.amount,
    this.date,
    this.reference,
    this.note,
  });

  /// `false` when the picture is not a bill/invoice.
  final bool isBill;

  /// The party the bill was issued to ("M/s …", "Customer", "Pelanggan").
  final String? customer;

  /// The business that issued the bill, when it is actually printed.
  final String? vendor;

  final double? amount;
  final DateTime? date;
  final String? reference;
  final String? note;

  /// Best value for the transaction's "Customer name" field.
  String? get partyName => customer ?? vendor;

  static ScannedBill notABill() => const ScannedBill(isBill: false);

  static ScannedBill fromMap(Map<String, dynamic> data) {
    final isBill = data['is_bill'] == true;
    if (!isBill) return ScannedBill.notABill();

    final rawAmount = data['amount'] ?? data['total'];
    double? amount;
    if (rawAmount is num) {
      amount = rawAmount.toDouble();
    } else if (rawAmount is String) {
      amount = double.tryParse(
        rawAmount.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.'),
      );
    }

    DateTime? date;
    final rawDate = data['date'];
    if (rawDate is String) date = DateTime.tryParse(rawDate.trim());

    String? text(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
      return trimmed;
    }

    return ScannedBill(
      isBill: true,
      customer: text(data['customer']),
      vendor: text(data['vendor']),
      amount: amount,
      date: date,
      reference: text(data['reference']),
      note: text(data['note']),
    );
  }
}

class ReceiptScanException implements Exception {
  const ReceiptScanException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns raw text (model JSON, a one-line answer, or ML Kit's transcription)
/// into a [ScannedBill].
///
/// Order: strict JSON first, then field-by-field heuristics. The heuristics
/// matter for on-device ML Kit, which never returns JSON — only the lines it
/// recognised.
ScannedBill parseScannedText(String raw) {
  final source = raw.trim();
  if (source.isEmpty) return ScannedBill.notABill();

  final asJson = _tryJson(source);
  if (asJson != null) return asJson;

  final lower = source.toLowerCase();
  final looksLikeBill = RegExp(
    r'cash\s*bill|invoice|receipt|resit|bill\s*no|no\.|jumlah|total|總計',
    caseSensitive: false,
  ).hasMatch(lower);

  final amount = _findAmount(source);
  final date = _findDate(source);
  final reference = _findReference(source);
  final customer = _findCustomer(source);

  if (!looksLikeBill && amount == null) return ScannedBill.notABill();

  final note = source.replaceAll(RegExp(r'\s+'), ' ').trim();

  return ScannedBill(
    isBill: true,
    customer: customer,
    amount: amount,
    date: date,
    reference: reference,
    note: note.length > 140 ? note.substring(0, 140) : note,
  );
}

ScannedBill? _tryJson(String source) {
  var value = source;
  if (value.startsWith('```')) {
    value = value.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    if (value.endsWith('```')) value = value.substring(0, value.length - 3);
  }
  final start = value.indexOf('{');
  final end = value.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(value.substring(start, end + 1));
    if (decoded is Map) {
      return ScannedBill.fromMap(Map<String, dynamic>.from(decoded));
    }
  } catch (_) {
    // not JSON — fall through to heuristics
  }
  return null;
}

double? _findAmount(String text) {
  final labelled = RegExp(
    r'(?:grand\s*total|total|jumlah|amount|bayaran)[^0-9]{0,15}(\d+(?:[.,]\d{1,2})?)',
    caseSensitive: false,
  ).firstMatch(text);
  final anyRm = RegExp(r'rm\s*(\d+(?:[.,]\d{1,2})?)', caseSensitive: false)
      .firstMatch(text);

  final match = labelled ?? anyRm;
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', '.'));
  if (value == null || value <= 0) return null;
  return value;
}

DateTime? _findDate(String text) {
  final iso = RegExp(r'(20\d{2})[-/](\d{1,2})[-/](\d{1,2})').firstMatch(text);
  if (iso != null) {
    return DateTime.tryParse(
      '${iso.group(1)}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}',
    );
  }

  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final named = RegExp(
    r'(\d{1,2})\s*(?:st|nd|rd|th)?\s+([A-Za-z]{3,9})\.?\s+(20\d{2})',
  ).firstMatch(text);
  if (named != null) {
    final month = months[named.group(2)!.toLowerCase().substring(0, 3)];
    if (month != null) {
      return DateTime(
        int.parse(named.group(3)!),
        month,
        int.parse(named.group(1)!),
      );
    }
  }

  final dmy =
      RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2}|\d{2})').firstMatch(text);
  if (dmy != null) {
    final rawYear = int.parse(dmy.group(3)!);
    final year = rawYear < 100 ? 2000 + rawYear : rawYear;
    return DateTime(year, int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));
  }
  return null;
}

String? _findReference(String text) {
  final match = RegExp(r'\bno\.?\s*[:#]?\s*(\d{2,6})', caseSensitive: false)
      .firstMatch(text);
  if (match != null) return match.group(1);
  return null;
}

String? _findCustomer(String text) {
  for (final line in text.split('\n')) {
    final trimmed = line.trim();
    final match =
        RegExp(r'^(?:m/s|ms\.?|customer|pelanggan)\s*[:.]?\s*(.+)$',
                caseSensitive: false)
            .firstMatch(trimmed);
    if (match == null) continue;
    var value = match.group(1)!.replaceAll(RegExp(r'\(.*?\)'), '').trim();
    value = value.replaceAll(RegExp(r'[:\-]+$'), '').trim();
    if (value.length >= 2) return value;
  }
  return null;
}
