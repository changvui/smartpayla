import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpayla/app.dart';
import 'package:smartpayla/data/transaction_repository.dart';
import 'package:smartpayla/state/providers.dart';

void main() {
  testWidgets('the chase list opens a reminder with a fallback message',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    // The tab is a worklist, not a form: every debtor is already ranked.
    expect(find.text("Today's chase list"), findsOneWidget);
    expect(find.text('Remind'), findsWidgets);

    await tester.tap(find.text('Remind').first);
    await tester.pumpAndSettle();

    // The sheet writes the message immediately. Without a proxy URL the service
    // falls back to a template, which is the behaviour under test.
    expect(find.byType(TextField), findsWidgets);
    final draft = tester.widget<TextField>(find.byType(TextField).last);
    expect(draft.controller!.text, isNotEmpty);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
  });
}
