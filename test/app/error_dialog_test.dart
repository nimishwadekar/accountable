import 'package:accountable/app/error_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('error dialog stays until the user presses OK', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showPersistentErrorDialog(
                context,
                'A write failed: Bad state: future error',
              ),
              child: const Text('Show error'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show error'));
    await tester.pumpAndSettle();
    expect(
      find.text('A write failed: Bad state: future error'),
      findsOneWidget,
    );

    await tester.pump(const Duration(minutes: 1));
    expect(
      find.text('A write failed: Bad state: future error'),
      findsOneWidget,
    );

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('A write failed: Bad state: future error'), findsNothing);
  });
}
