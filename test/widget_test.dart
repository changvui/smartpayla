import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpayla/app.dart';
import 'package:smartpayla/state/providers.dart';

void main() {
  testWidgets('shows the SmartPayLA home shell', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const SmartPayLaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('SmartPayLA'), findsOneWidget);
    expect(find.text('Your field ledger'), findsOneWidget);
    expect(find.text('TOTAL OUTSTANDING'), findsOneWidget);
  });
}
