import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpayla/app.dart';
import 'package:smartpayla/data/transaction_repository.dart';
import 'package:smartpayla/state/providers.dart';

void main() {
  testWidgets('bill month filter shows only that month', (tester) async {
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
        matching: find.text('Transactions'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All bill months'), findsOneWidget);
    await tester.tap(find.text('All bill months'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final monthShort = DateFormat('MMM').format(now);
    final monthLong = DateFormat('MMMM yyyy').format(now);

    await tester.tap(find.text(monthShort));
    await tester.pumpAndSettle();

    expect(find.text(monthLong), findsOneWidget);
    expect(find.text('Nur Aisyah'), findsOneWidget);
    expect(find.text('Siti Nurhaliza'), findsNothing);
  });
}
