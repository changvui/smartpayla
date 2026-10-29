import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpayla/app.dart';
import 'package:smartpayla/data/transaction_repository.dart';
import 'package:smartpayla/state/providers.dart';

void main() {
  testWidgets('generates a fallback reminder without an API key',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await LocalTransactionRepository(prefs).seedDemo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const SmartPayLaApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Reminders'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Generate reminder'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Preview for'), findsOneWidget);
    expect(find.text('Fallback'), findsOneWidget);
  });
}
