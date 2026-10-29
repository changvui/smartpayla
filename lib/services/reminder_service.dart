import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/reminder.dart';
import '../models/transaction.dart';

class ReminderService {
  ReminderService({http.Client? client}) : _client = client ?? http.Client();

  static const endpoint = 'https://api.deepseek.com/v1/chat/completions';
  static const model = 'deepseek-chat';

  final http.Client _client;

  Future<ReminderResult> generate({
    required Transaction transaction,
    required ReminderTone tone,
    required String apiKey,
  }) async {
    final fallback = _fallback(transaction, tone);
    if (apiKey.trim().isEmpty) {
      return ReminderResult(
        text: fallback,
        tone: tone,
        usedFallback: true,
        error: 'No DeepSeek API key configured',
      );
    }

    try {
      final response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode({
              'model': model,
              'temperature': 0.7,
              'max_tokens': 220,
              'messages': [
                {
                  'role': 'system',
                  'content': _systemPrompt(tone),
                },
                {
                  'role': 'user',
                  'content': _userPrompt(transaction),
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ReminderResult(
          text: fallback,
          tone: tone,
          usedFallback: true,
          error: 'API ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);
      String? content;
      if (decoded is Map) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map) {
            final message = first['message'];
            if (message is Map) {
              content = message['content']?.toString();
            }
          }
        }
      }
      if (content == null || content.trim().isEmpty) {
        return ReminderResult(
          text: fallback,
          tone: tone,
          usedFallback: true,
          error: 'Empty API response',
        );
      }

      return ReminderResult(
        text: _clean(content),
        tone: tone,
        usedFallback: false,
      );
    } on TimeoutException {
      return ReminderResult(
        text: fallback,
        tone: tone,
        usedFallback: true,
        error: 'API timeout',
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

  String _systemPrompt(ReminderTone tone) {
    final toneText = switch (tone) {
      ReminderTone.formal => 'formal, polite and businesslike',
      ReminderTone.friendly => 'warm, friendly and conversational',
      ReminderTone.urgent => 'firm and urgent but still respectful',
    };
    return 'You write short payment reminder messages for a Malaysian sales agent. '
        'The tone must be $toneText. Include the customer name, the outstanding '
        'amount, the item, and how many days overdue. Do not threaten or shame '
        'the customer. Keep it under 75 words. Return only the message, with no '
        'headings or quotation marks.';
  }

  String _userPrompt(Transaction transaction) {
    final item = transaction.itemDescription.trim().isEmpty
        ? 'the recent purchase'
        : transaction.itemDescription.trim();
    return 'Customer: ${transaction.customerName}\n'
        'Item: $item\n'
        'Outstanding amount: ${_money(transaction.balanceDue)}\n'
        'Due date: ${_date(transaction.dueDate)}\n'
        'Days overdue: ${transaction.daysOverdue}\n'
        'Write the reminder now.';
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

  String _clean(String text) {
    var result = text.trim();
    if (result.startsWith('"') && result.endsWith('"') && result.length > 1) {
      result = result.substring(1, result.length - 1).trim();
    }
    return result;
  }

  String _money(double amount) =>
      NumberFormat.currency(symbol: 'RM ', decimalDigits: 2).format(amount);

  String _date(DateTime date) => DateFormat('d MMM yyyy').format(date);
}
