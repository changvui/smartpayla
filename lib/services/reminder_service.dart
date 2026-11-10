import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/reminder.dart';
import '../models/transaction.dart';

/// Calls the SmartPayLA AI proxy. The app never holds a DeepSeek key, so every
/// user can use the reminder feature without buying their own API account.
class ReminderService {
  ReminderService({http.Client? client, String? proxyUrl})
      : _client = client ?? http.Client(),
        proxyUrl = (proxyUrl ?? defaultProxyUrl).trim();

  /// Set at build time:
  /// --dart-define=REMINDER_PROXY_URL=https://smartpayla-ai.example.workers.dev
  static const defaultProxyUrl =
      String.fromEnvironment('REMINDER_PROXY_URL');

  static bool get isConfigured => defaultProxyUrl.trim().isNotEmpty;

  final http.Client _client;
  final String proxyUrl;

  Future<ReminderResult> generate({
    required Transaction transaction,
    required ReminderTone tone,
  }) async {
    final fallback = _fallback(transaction, tone);
    if (proxyUrl.isEmpty) {
      return ReminderResult(
        text: fallback,
        tone: tone,
        usedFallback: true,
        error: 'AI proxy not configured',
      );
    }

    try {
      final base = proxyUrl.replaceAll(RegExp(r'/+$'), '');
      final endpoint = base.endsWith('/reminder')
          ? base
          : '$base/reminder';
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'customerName': transaction.customerName,
              'item': transaction.itemDescription,
              'amount': transaction.balanceDue,
              'dueDate': DateFormat('yyyy-MM-dd').format(transaction.dueDate),
              'daysOverdue': transaction.daysOverdue,
              'tone': tone.name,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ReminderResult(
          text: fallback,
          tone: tone,
          usedFallback: true,
          error: 'AI ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      final text = decoded is Map ? decoded['text']?.toString() : null;
      if (text == null || text.trim().isEmpty) {
        return ReminderResult(
          text: fallback,
          tone: tone,
          usedFallback: true,
          error: 'Empty AI response',
        );
      }

      return ReminderResult(
        text: text.trim(),
        tone: tone,
        usedFallback: false,
      );
    } on TimeoutException {
      return ReminderResult(
        text: fallback,
        tone: tone,
        usedFallback: true,
        error: 'AI timeout',
      );
    } catch (error) {
      return ReminderResult(
        text: fallback,
        tone: tone,
        usedFallback: true,
        error: error.toString(),
      );
    }
  }

  String _fallback(Transaction transaction, ReminderTone tone) {
    final name = transaction.customerName.trim().isEmpty
        ? 'there'
        : transaction.customerName.trim();
    final item = transaction.itemDescription.trim().isEmpty
        ? 'your recent purchase'
        : transaction.itemDescription.trim();
    final amount = _money(transaction.balanceDue);
    final due = _date(transaction.dueDate);
    final days = transaction.daysOverdue;

    switch (tone) {
      case ReminderTone.formal:
        return 'Dear $name, this is a gentle reminder that $amount remains '
            'outstanding for $item. The payment was due on $due'
            '${days > 0 ? ' ($days days ago)' : ''}. Kindly arrange payment at '
            'your earliest convenience. Thank you.';
      case ReminderTone.friendly:
        return 'Hi $name, hope you are doing well! Just a quick reminder that '
            '$amount is still outstanding for $item (due $due). If you have '
            'already arranged it, please ignore this message. Thank you!';
      case ReminderTone.urgent:
        return 'Dear $name, our records show that $amount for $item is now '
            '${days > 0 ? '$days days overdue' : 'due'}. Please settle the '
            'balance as soon as possible, or contact me to arrange a payment '
            'plan. Thank you.';
    }
  }

  String _money(double amount) =>
      NumberFormat.currency(symbol: 'RM ', decimalDigits: 2).format(amount);

  String _date(DateTime date) => DateFormat('d MMM yyyy').format(date);
}
