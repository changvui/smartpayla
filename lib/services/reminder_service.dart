import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/reminder.dart';
import '../models/transaction.dart';

/// Language the reminder is written in. Malaysian agents deal with customers
/// who read English, Bahasa Malaysia or Chinese, and a formal English reminder
/// reads badly to a customer who only reads Chinese.
enum ReminderLanguage { english, malay, chinese }

extension ReminderLanguageX on ReminderLanguage {
  String get code {
    switch (this) {
      case ReminderLanguage.english:
        return 'en';
      case ReminderLanguage.malay:
        return 'ms';
      case ReminderLanguage.chinese:
        return 'zh';
    }
  }

  String get label {
    switch (this) {
      case ReminderLanguage.english:
        return 'English';
      case ReminderLanguage.malay:
        return 'Bahasa';
      case ReminderLanguage.chinese:
        return '中文';
    }
  }
}

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
    ReminderLanguage language = ReminderLanguage.english,
    String? reference,
  }) async {
    final fallback = _fallback(transaction, tone, language, reference);
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
      final endpoint =
          base.endsWith('/reminder') ? base : '$base/reminder';
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
              'language': language.code,
              'reference': reference ?? '',
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

  String _fallback(
    Transaction transaction,
    ReminderTone tone,
    ReminderLanguage language,
    String? reference,
  ) {
    final name = transaction.customerName.trim().isEmpty
        ? 'there'
        : transaction.customerName.trim();
    final item = transaction.itemDescription.trim().isEmpty
        ? 'your recent purchase'
        : transaction.itemDescription.trim();
    final amount = _money(transaction.balanceDue);
    final due = _date(transaction.dueDate);
    final days = transaction.daysOverdue;
    final ref = (reference ?? '').trim();
    final refLine = ref.isEmpty ? '' : ' (bill $ref)';

    switch (language) {
      case ReminderLanguage.english:
        switch (tone) {
          case ReminderTone.formal:
            return 'Dear $name, this is a gentle reminder that $amount remains '
                'outstanding for $item$refLine. The payment was due on $due'
                '${days > 0 ? ' ($days days ago)' : ''}. Kindly arrange payment '
                'at your earliest convenience. Thank you.';
          case ReminderTone.friendly:
            return 'Hi $name, hope you are doing well! Just a quick reminder '
                'that $amount is still outstanding for $item$refLine '
                '(due $due). If you have already arranged it, please ignore '
                'this message. Thank you!';
          case ReminderTone.urgent:
            return 'Dear $name, our records show that $amount for $item$refLine '
                'is now ${days > 0 ? '$days days overdue' : 'due'}. Please '
                'settle the balance as soon as possible, or contact me to '
                'arrange a payment plan. Thank you.';
        }
      case ReminderLanguage.malay:
        switch (tone) {
          case ReminderTone.formal:
            return 'Salam sejahtera $name, ini peringatan bahawa $amount masih '
                'tertunggak bagi $item$refLine. Bayaran sepatutnya dibuat pada '
                '$due${days > 0 ? ' ($days hari lepas)' : ''}. Sila jelaskan '
                'bayaran secepat mungkin. Terima kasih.';
          case ReminderTone.friendly:
            return 'Hai $name! Sekadar peringatan mesra, $amount bagi '
                '$item$refLine masih belum dijelaskan (tarikh $due). Jika sudah '
                'dibuat, abaikan mesej ini. Terima kasih!';
          case ReminderTone.urgent:
            return 'Salam $name, rekod kami menunjukkan $amount bagi '
                '$item$refLine telah ${days > 0 ? 'tertunggak $days hari' : 'sampai tempoh'}. '
                'Sila jelaskan segera atau hubungi saya untuk aturan bayaran. '
                'Terima kasih.';
        }
      case ReminderLanguage.chinese:
        switch (tone) {
          case ReminderTone.formal:
            return '$name 您好，提醒您 $item$refLine 尚有 $amount 未结清，'
                '原定付款日期为 $due${days > 0 ? '（已逾期 $days 天）' : ''}。'
                '请尽早安排付款，谢谢。';
          case ReminderTone.friendly:
            return '$name 你好！温馨提醒一下，$item$refLine 的 $amount 还未付款'
                '（到期日 $due）。如果已经转账了请忽略这条消息，谢谢！';
          case ReminderTone.urgent:
            return '$name 您好，记录显示 $item$refLine 的 $amount 已'
                '${days > 0 ? '逾期 $days 天' : '到期'}。请尽快结清，或联系我安排'
                '分期付款。谢谢。';
        }
    }
  }

  String _money(double amount) =>
      NumberFormat.currency(symbol: 'RM ', decimalDigits: 2).format(amount);

  String _date(DateTime date) => DateFormat('d MMM yyyy').format(date);
}
