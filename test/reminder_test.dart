import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartpayla/models/reminder.dart';
import 'package:smartpayla/models/transaction.dart';
import 'package:smartpayla/services/reminder_service.dart';

Transaction overdueTransaction() {
  final now = DateTime.now();
  return Transaction(
    id: 'r1',
    customerName: 'Ahmad Faizal',
    itemDescription: 'Catering order',
    totalAmount: 500,
    advancePaid: 100,
    dueDate: now.subtract(const Duration(days: 10)),
    status: PaymentStatus.partial,
    createdAt: now.subtract(const Duration(days: 20)),
    updatedAt: now,
  );
}

void main() {
  test('no proxy uses a static fallback with the balance', () async {
    final result = await ReminderService(proxyUrl: '').generate(
      transaction: overdueTransaction(),
      tone: ReminderTone.formal,
    );

    expect(result.usedFallback, isTrue);
    expect(result.text, contains('Ahmad Faizal'));
    expect(result.text, contains('RM 400.00'));
    expect(result.text, contains('10 days'));
  });

  test('proxy response is used as-is', () async {
    final service = ReminderService(
      proxyUrl: 'https://ai.smartpayla.test',
      client: MockClient((request) async {
        expect(request.url.path, '/reminder');
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          isNull,
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['tone'], 'friendly');
        expect(body['customerName'], 'Ahmad Faizal');
        return http.Response(
          jsonEncode({'text': 'Hi Ahmad, a custom reminder.'}),
          200,
        );
      }),
    );

    final result = await service.generate(
      transaction: overdueTransaction(),
      tone: ReminderTone.friendly,
    );

    expect(result.usedFallback, isFalse);
    expect(result.text, 'Hi Ahmad, a custom reminder.');
  });

  test('proxy error falls back and records the reason', () async {
    final service = ReminderService(
      proxyUrl: 'https://ai.smartpayla.test',
      client: MockClient((_) async => http.Response('nope', 500)),
    );

    final result = await service.generate(
      transaction: overdueTransaction(),
      tone: ReminderTone.urgent,
    );

    expect(result.usedFallback, isTrue);
    expect(result.error, contains('500'));
  });
}
