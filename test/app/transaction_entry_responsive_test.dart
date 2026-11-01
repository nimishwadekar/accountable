import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/pages/transaction_form.dart';
import 'package:accountable/app/pages/transactions_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  testWidgets(
    'mobile entry is full width and keeps template state through guarded Back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = await AssetAppDataRepository().load();
      final now = DateTime.utc(2026, 10, 20);
      const longName =
          'Weekday lunch at the office canteen with the whole project team';
      final data = _withTemplates(source, [
        TransactionTemplate(
          id: 'long-template',
          name: longName,
          type: TransactionType.expense,
          description: null,
          categoryId: 'food_drink',
          tagId: 'boston',
          sourceAccountId: 'chase_checking',
          sourceAmount: null,
          destinationAccountId: null,
          destinationAmount: null,
          date: null,
          isFavorite: false,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
      Transaction? addedTransaction;

      await tester.pumpWidget(
        _transactionsApp(
          data,
          onTransactionAdded: (transaction) async {
            addedTransaction = transaction;
          },
        ),
      );
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final dialogContent = find.byKey(
        const ValueKey('transaction-entry-flow-content'),
      );
      expect(dialogContent, findsOneWidget);
      expect(tester.getRect(dialogContent).width, 390);
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Dining'), findsWidgets);
      expect(find.text('New Transaction'), findsOneWidget);
      expect(find.text('Create Template'), findsOneWidget);
      expect(
        tester.getRect(find.text(longName)).width,
        greaterThan(200),
        reason: 'Template names should not share a fixed trailing column.',
      );

      await tester.tap(find.text(longName));
      await tester.pump();
      expect(find.text('Description'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Lunch with team',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Lunch with team'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text(longName), findsOneWidget);
      expect(find.text('Lunch with team'), findsNothing);

      // The browser stays mounted behind the chooser/form and retains search.
      await tester.enterText(find.byType(TextField), 'Weekday lunch');
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'New Transaction'));
      await tester.pump();
      expect(find.text('Transaction Type'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField).first, findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Weekday lunch',
      );
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pump();
      expect(
        tester
            .getRect(find.byKey(const ValueKey('transaction-entry-surface')))
            .width,
        lessThanOrEqualTo(560),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Weekday lunch',
        reason: 'Resize must retain the browser controller and query.',
      );
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pump();
      expect(
        tester
            .getRect(find.byKey(const ValueKey('transaction-entry-surface')))
            .width,
        390,
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text(longName));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Lunch with team',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '123.45',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add Transaction'));
      await tester.pumpAndSettle();
      expect(addedTransaction?.description, 'Lunch with team');
      expect(addedTransaction?.sourceAmount?.minorUnits, 12345);
      expect(addedTransaction?.categoryId, 'food_drink');
      expect(addedTransaction?.tagId, 'boston');
      expect(tester.takeException(), isNull);

      await tester.binding.setSurfaceSize(const Size(390, 520));
      await tester.pumpWidget(
        _transactionsApp(
          data,
          key: const ValueKey('short-entry'),
          mediaSize: const Size(390, 520),
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.widgetWithText(OutlinedButton, 'New Transaction'));
      await tester.pump();
      await tester.tap(find.text('Expense'));
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding(
        bottom: 220 * tester.view.devicePixelRatio,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        MediaQuery.viewInsetsOf(
          tester.element(find.byType(TransactionFormSheet)),
        ).bottom,
        closeTo(220, 1),
      );

      final submit = find.widgetWithText(FilledButton, 'Add Transaction');
      expect(
        find.byKey(const ValueKey('transaction-entry-surface')),
        findsOneWidget,
      );
      expect(tester.getRect(submit).bottom, lessThanOrEqualTo(300));
      await tester.tap(submit);
      await tester.pump();
      expect(find.text('Enter a description.'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      for (final width in [320.0, 360.0, 430.0]) {
        await tester.binding.setSurfaceSize(Size(width, 740));
        await tester.pumpWidget(
          _transactionsApp(
            data,
            key: ValueKey('entry-$width'),
            mediaSize: Size(width, 740),
          ),
        );
        await tester.pump();
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(
          MediaQuery.sizeOf(tester.element(find.byType(TransactionsPage)))
              .width,
          width,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Add transaction'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(
          tester
              .getRect(
                find.byKey(const ValueKey('transaction-entry-flow-content')),
              )
              .width,
          width,
          reason: '$width px',
        );
        expect(find.text(longName), findsOneWidget, reason: '$width px');
        expect(
          tester.getRect(find.text(longName)).width,
          greaterThan(150),
          reason: 'The template name remains identifiable at $width px.',
        );
        expect(tester.takeException(), isNull, reason: '$width px');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
      }

      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(
        _transactionsApp(
          data,
          key: const ValueKey('desktop-entry'),
          mediaSize: const Size(1280, 900),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final searchField = tester.getRect(find.byType(TextField));
      expect(searchField.width, lessThan(540));
      expect(searchField.center.dx, closeTo(640, 80));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
    },
  );
}

Widget _transactionsApp(
  AppDataSnapshot data, {
  Key? key,
  Size mediaSize = const Size(390, 844),
  Future<void> Function(Transaction transaction)? onTransactionAdded,
}) => MaterialApp(
  key: key,
  theme: AppTheme.light(),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(size: mediaSize),
      child: Scaffold(
        body: TransactionsPage(
          data: data,
          onTransactionAdded: onTransactionAdded ?? (_) async {},
          onTransactionsAdded: (_) async {},
          onTemplateAdded: (_) async {},
          onTemplateUpdated: (_) async {},
        ),
      ),
    ),
  ),
);

AppDataSnapshot _withTemplates(
  AppDataSnapshot source,
  List<TransactionTemplate> templates,
) => AppDataSnapshot(
  accounts: source.accounts,
  categories: source.categories,
  currencies: source.currencies,
  tags: source.tags,
  transactions: source.transactions,
  transactionsToMigrate: source.transactionsToMigrate,
  exchangeRates: source.exchangeRates,
  dailyAccountBalances: source.dailyAccountBalances,
  dailyNetWorth: source.dailyNetWorth,
  dailyManualValuations: source.dailyManualValuations,
  displayPreferences: source.displayPreferences,
  transactionTemplates: templates,
  incomeAllocations: source.incomeAllocations,
  achievements: source.achievements,
  achievementStartDate: source.achievementStartDate,
);
