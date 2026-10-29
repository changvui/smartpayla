import 'transaction.dart';

enum ReminderTone { formal, friendly, urgent }

extension ReminderToneX on ReminderTone {
  String get label {
    switch (this) {
      case ReminderTone.formal:
        return 'Formal';
      case ReminderTone.friendly:
        return 'Friendly';
      case ReminderTone.urgent:
        return 'Urgent';
    }
  }

  static ReminderTone fromName(String value) {
    return ReminderTone.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReminderTone.formal,
    );
  }
}

class ReminderResult {
  const ReminderResult({
    required this.text,
    required this.tone,
    required this.usedFallback,
    this.error,
  });

  final String text;
  final ReminderTone tone;
  final bool usedFallback;
  final String? error;
}

class ReminderRecord {
  const ReminderRecord({
    required this.id,
    required this.transactionId,
    required this.customerName,
    required this.tone,
    required this.text,
    required this.createdAt,
    required this.usedFallback,
  });

  final String id;
  final String transactionId;
  final String customerName;
  final ReminderTone tone;
  final String text;
  final DateTime createdAt;
  final bool usedFallback;

  Map<String, dynamic> toJson() => {
        'id': id,
        'transactionId': transactionId,
        'customerName': customerName,
        'tone': tone.name,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'usedFallback': usedFallback,
      };

  factory ReminderRecord.fromJson(Map<String, dynamic> json) {
    return ReminderRecord(
      id: (json['id'] ?? '').toString(),
      transactionId: (json['transactionId'] ?? '').toString(),
      customerName: (json['customerName'] ?? '').toString(),
      tone: ReminderToneX.fromName((json['tone'] ?? 'formal').toString()),
      text: (json['text'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      usedFallback: json['usedFallback'] == true,
    );
  }
}

String reminderAmountText(Transaction transaction) {
  final amount = transaction.balanceDue;
  return 'RM ${amount.toStringAsFixed(2)}';
}
