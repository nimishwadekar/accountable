import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/main.dart';

void main() {
  testWidgets('loads the overview shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Net worth'), findsOneWidget);
    expect(find.text('Accounts'), findsWidgets);
  });
}
