import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

/// One reminder that was sent (or copied), kept so the screen can answer two
/// questions: "when did I last chase this customer?" and "what did I say?".
class SentReminder {
  const SentReminder({
    required this.customerKey,
    required this.customerName,
    required this.tone,
    required this.language,
    required this.text,
    required this.usedFallback,
    required this.sentAt,
  });

  /// Normalised customer name, so the same customer matches across bills.
  final String customerKey;
  final String customerName;
  final ReminderTone tone;
  final String language;
  final String text;
  final bool usedFallback;
  final DateTime sentAt;

  Map<String, dynamic> toJson() => {
        'customerKey': customerKey,
        'customerName': customerName,
        'tone': tone.name,
        'language': language,
        'text': text,
        'usedFallback': usedFallback,
        'sentAt': sentAt.toIso8601String(),
      };

  static SentReminder fromJson(Map<String, dynamic> json) => SentReminder(
        customerKey: (json['customerKey'] ?? '').toString(),
        customerName: (json['customerName'] ?? '').toString(),
        tone: ReminderToneX.fromName((json['tone'] ?? 'formal').toString()),
        language: (json['language'] ?? 'en').toString(),
        text: (json['text'] ?? '').toString(),
        usedFallback: json['usedFallback'] == true,
        sentAt: DateTime.tryParse((json['sentAt'] ?? '').toString()) ??
            DateTime.now(),
      );
}

/// Local, device-scoped log of reminders. It is deliberately not in Firestore:
/// the reminder history is a working aid, not part of the ledger, and keeping it
/// local avoids another collection to secure.
class ReminderLog {
  static const _key = 'reminder_log_v1';
  static const _maxEntries = 200;

  static Future<List<SentReminder>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => SentReminder.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Most recent first.
  static Future<List<SentReminder>> recent({int limit = 20}) async {
    final entries = await all();
    entries.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return entries.take(limit).toList();
  }

  /// Last time each customer was reminded, keyed by the normalised name.
  static Future<Map<String, DateTime>> lastSentByCustomer() async {
    final entries = await all();
    final result = <String, DateTime>{};
    for (final entry in entries) {
      final current = result[entry.customerKey];
      if (current == null || entry.sentAt.isAfter(current)) {
        result[entry.customerKey] = entry.sentAt;
      }
    }
    return result;
  }

  static Future<void> add(SentReminder entry) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = await all();
    entries.add(entry);
    // Trim the oldest entries so the value never grows without bound.
    if (entries.length > _maxEntries) {
      entries.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      entries.removeRange(0, entries.length - _maxEntries);
    }
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
