import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transactions_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets(
    'short restricted startup keeps sign-in and explicit retry reachable',
    (tester) async {
      const size = Size(390, 520);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = await AssetAppDataRepository().load();
      var signIns = 0;
      var retries = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: size),
              child: Scaffold(
                body: TransactionsPage(
                  data: data,
                  onTransactionAdded: (_) async {},
                  onTransactionsAdded: (_) async {},
                  onTemplateAdded: (_) async {},
                  onTemplateUpdated: (_) async {},
                  restrictedStartup: true,
                  startupError: 'The local batch is waiting for sign-in.',
                  onStartupSignIn: () async {
                    signIns++;
                  },
                  onRetryOutbox: () async {
                    retries++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Add transaction'), findsOneWidget);
      expect(find.textContaining('pending local transactions'), findsOneWidget);
      expect(find.textContaining('waiting for sign-in'), findsOneWidget);
      expect(find.text('Filters'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Retry upload'));
      await tester.tap(find.text('Retry upload'));
      await tester.pump();
      expect(retries, 1);
      await tester.ensureVisible(find.text('Sign in to sync'));
      await tester.tap(find.text('Sign in to sync'));
      await tester.pump();
      expect(signIns, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
