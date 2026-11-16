/// Payment records are append-only: a payment is created, then either confirmed
/// or voided. It is never deleted and the amount is never edited, so the ledger
/// keeps an audit trail and receipts stay meaningful.
library;

enum PaymentMethod { cash, duitnow, bank, writeOff }

extension PaymentMethodX on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.duitnow:
        return 'DuitNow';
      case PaymentMethod.bank:
        return 'Bank transfer';
      case PaymentMethod.writeOff:
        return 'Write-off';
    }
  }

  /// True for rails that the customer initiates from the statement link. These
  /// cannot be reversed by editing the transaction status; the payment itself
  /// has to be voided.
  bool get isOnline =>
      this == PaymentMethod.duitnow || this == PaymentMethod.bank;

  static PaymentMethod fromName(String? value) {
    return PaymentMethod.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PaymentMethod.cash,
    );
  }
}

enum PaymentState { pending, confirmed, voided }

extension PaymentStateX on PaymentState {
  String get label {
    switch (this) {
      case PaymentState.pending:
        return 'Pending';
      case PaymentState.confirmed:
        return 'Confirmed';
      case PaymentState.voided:
        return 'Voided';
    }
  }

  static PaymentState fromName(String? value) {
    return PaymentState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PaymentState.confirmed,
    );
  }
}

class Payment {
  const Payment({
    required this.id,
    required this.transactionId,
    required this.customerName,
    required this.amount,
    required this.method,
    required this.state,
    required this.receiptNo,
    required this.paidAt,
    required this.createdAt,
    this.confirmedAt,
    this.voidedAt,
    this.voidReason,
    this.note,
    this.reference,
    this.declaredByCustomer = false,
    this.openingBalance = false,
    this.proofImage,
  });

  final String id;
  final String transactionId;
  final String customerName;
  final double amount;
  final PaymentMethod method;
  final PaymentState state;

  /// Printed on the receipt. Generated on the device so a payment can be
  /// recorded offline without waiting for a server-side counter.
  final String receiptNo;

  final DateTime paidAt;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? voidedAt;
  final String? voidReason;
  final String? note;

  /// Bank reference or the short reconciliation code the customer typed.
  final String? reference;

  /// True when the customer declared the payment from the statement page.
  final bool declaredByCustomer;

  /// True for the synthetic record created when migrating `advancePaid`.
  final bool openingBalance;

  /// Screenshot of the transfer / cash slip supplied when the payment was
  /// recorded. Separate from the bill photo on the transaction: that one
  /// proves the sale, this one proves the money arrived.
  final String? proofImage;

  bool get countsTowardsBalance => state == PaymentState.confirmed;

  Payment copyWith({
    PaymentState? state,
    DateTime? confirmedAt,
    DateTime? voidedAt,
    String? voidReason,
    String? note,
    String? reference,
  }) {
    return Payment(
      id: id,
      transactionId: transactionId,
      customerName: customerName,
      amount: amount,
      method: method,
      state: state ?? this.state,
      receiptNo: receiptNo,
      paidAt: paidAt,
      createdAt: createdAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      voidedAt: voidedAt ?? this.voidedAt,
      voidReason: voidReason ?? this.voidReason,
      note: note ?? this.note,
      reference: reference ?? this.reference,
      declaredByCustomer: declaredByCustomer,
      openingBalance: openingBalance,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'transactionId': transactionId,
    'customerName': customerName,
    'amount': amount,
    'method': method.name,
    'state': state.name,
    'receiptNo': receiptNo,
    'paidAt': paidAt.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'confirmedAt': confirmedAt?.toIso8601String(),
    'voidedAt': voidedAt?.toIso8601String(),
    'voidReason': voidReason,
    'note': note,
    'reference': reference,
    'declaredByCustomer': declaredByCustomer,
    'openingBalance': openingBalance,
    'proofImage': proofImage,
  };

  factory Payment.fromJson(Map<String, dynamic> json) {
    DateTime parse(Object? value, {DateTime? fallback}) {
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
      }
      return fallback ?? DateTime.now();
    }

    DateTime? parseNullable(Object? value) {
      if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
      return null;
    }

    return Payment(
      id: (json['id'] ?? '').toString(),
      transactionId: (json['transactionId'] ?? '').toString(),
      customerName: (json['customerName'] ?? '').toString(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      method: PaymentMethodX.fromName(json['method']?.toString()),
      state: PaymentStateX.fromName(json['state']?.toString()),
      receiptNo: (json['receiptNo'] ?? '').toString(),
      paidAt: parse(json['paidAt']),
      createdAt: parse(json['createdAt']),
      confirmedAt: parseNullable(json['confirmedAt']),
      voidedAt: parseNullable(json['voidedAt']),
      voidReason: json['voidReason']?.toString(),
      note: json['note']?.toString(),
      reference: json['reference']?.toString(),
      declaredByCustomer: json['declaredByCustomer'] == true,
      openingBalance: json['openingBalance'] == true,
      proofImage: json['proofImage']?.toString(),
    );
  }
}
