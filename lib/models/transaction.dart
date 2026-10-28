import 'dart:math' as math;

/// The three payment states that are stored for a transaction.
/// "Overdue" is not stored: it is derived from [Transaction.daysOverdue].
enum PaymentStatus { unpaid, partial, paid }

extension PaymentStatusX on PaymentStatus {
  String get label {
    switch (this) {
      case PaymentStatus.unpaid:
        return 'Unpaid';
      case PaymentStatus.partial:
        return 'Partial';
      case PaymentStatus.paid:
        return 'Paid';
    }
  }

  static PaymentStatus fromName(String value) {
    return PaymentStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PaymentStatus.unpaid,
    );
  }
}

enum AgingBucket { current, days31to60, days60plus, paid }

extension AgingBucketX on AgingBucket {
  String get label {
    switch (this) {
      case AgingBucket.current:
        return '0–30 days';
      case AgingBucket.days31to60:
        return '31–60 days';
      case AgingBucket.days60plus:
        return '60+ days';
      case AgingBucket.paid:
        return 'Paid';
    }
  }
}

class Transaction {
  const Transaction({
    required this.id,
    required this.customerName,
    required this.itemDescription,
    required this.totalAmount,
    required this.advancePaid,
    required this.dueDate,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.finishDate,
    this.claimExpiry,
    this.invoiceNumber,
    this.invoiceDate,
    this.cashBillNumber,
    this.cashBillDate,
  });

  final String id;
  final String customerName;
  final String itemDescription;
  final double totalAmount;
  final double advancePaid;
  final DateTime dueDate;
  final PaymentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  final DateTime? finishDate;
  final DateTime? claimExpiry;
  final String? invoiceNumber;
  final DateTime? invoiceDate;
  final String? cashBillNumber;
  final DateTime? cashBillDate;

  /// Amount still owed. Never negative, even if the user entered an advance
  /// larger than the total by mistake.
  double get balanceDue => math.max(0, totalAmount - advancePaid);

  bool get isPaid => status == PaymentStatus.paid;

  bool get isOpen => !isPaid;

  /// Whole days past the due date. Zero when the due date is today or later.
  int get daysOverdue {
    final today = DateTime.now();
    final d = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final t = DateTime(today.year, today.month, today.day);
    final diff = t.difference(d).inDays;
    return diff > 0 ? diff : 0;
  }

  bool get isOverdue => isOpen && daysOverdue > 0;

  /// The date used for the "bill month" filter.
  ///
  /// The physical document date is the most meaningful when it exists; older
  /// records without a cash-bill/invoice date fall back to when the record was
  /// created, so no transaction disappears from the month view.
  DateTime get billDate => cashBillDate ?? invoiceDate ?? createdAt;

  /// What the UI should show. This is why "Overdue" is a display state rather
  /// than a fourth stored payment status.
  String get displayStatus {
    if (isPaid) return 'Paid';
    if (isOverdue) return 'Overdue';
    return status.label;
  }

  AgingBucket get agingBucket {
    if (isPaid) return AgingBucket.paid;
    if (daysOverdue <= 30) return AgingBucket.current;
    if (daysOverdue <= 60) return AgingBucket.days31to60;
    return AgingBucket.days60plus;
  }

  /// Fraction of the total that has been paid. Used by the detail screen.
  double get paidFraction {
    if (totalAmount <= 0) return 0;
    return (advancePaid / totalAmount).clamp(0.0, 1.0);
  }

  Transaction copyWith({
    String? customerName,
    String? itemDescription,
    double? totalAmount,
    double? advancePaid,
    DateTime? dueDate,
    PaymentStatus? status,
    DateTime? updatedAt,
    DateTime? finishDate,
    DateTime? claimExpiry,
    String? invoiceNumber,
    DateTime? invoiceDate,
    String? cashBillNumber,
    DateTime? cashBillDate,
  }) {
    return Transaction(
      id: id,
      customerName: customerName ?? this.customerName,
      itemDescription: itemDescription ?? this.itemDescription,
      totalAmount: totalAmount ?? this.totalAmount,
      advancePaid: advancePaid ?? this.advancePaid,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      finishDate: finishDate ?? this.finishDate,
      claimExpiry: claimExpiry ?? this.claimExpiry,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      cashBillNumber: cashBillNumber ?? this.cashBillNumber,
      cashBillDate: cashBillDate ?? this.cashBillDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerName': customerName,
      'itemDescription': itemDescription,
      'totalAmount': totalAmount,
      'advancePaid': advancePaid,
      'dueDate': dueDate.toIso8601String(),
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'finishDate': finishDate?.toIso8601String(),
      'claimExpiry': claimExpiry?.toIso8601String(),
      'invoiceNumber': invoiceNumber,
      'invoiceDate': invoiceDate?.toIso8601String(),
      'cashBillNumber': cashBillNumber,
      'cashBillDate': cashBillDate?.toIso8601String(),
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value, {DateTime? fallback}) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
      }
      return fallback ?? DateTime.now();
    }

    DateTime? parseNullableDate(Object? value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return Transaction(
      id: (json['id'] ?? '').toString(),
      customerName: (json['customerName'] ?? '').toString(),
      itemDescription: (json['itemDescription'] ?? '').toString(),
      totalAmount: (json['totalAmount'] as num?)?.toDouble() ?? 0,
      advancePaid: (json['advancePaid'] as num?)?.toDouble() ?? 0,
      dueDate: parseDate(json['dueDate']),
      status: PaymentStatusX.fromName((json['status'] ?? 'unpaid').toString()),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      finishDate: parseNullableDate(json['finishDate']),
      claimExpiry: parseNullableDate(json['claimExpiry']),
      invoiceNumber: json['invoiceNumber']?.toString(),
      invoiceDate: parseNullableDate(json['invoiceDate']),
      cashBillNumber: json['cashBillNumber']?.toString(),
      cashBillDate: parseNullableDate(json['cashBillDate']),
    );
  }
}
