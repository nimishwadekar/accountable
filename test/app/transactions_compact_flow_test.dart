import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/formatters.dart';
import 'package:accountable/app/pages/transaction_list_widgets.dart';
import 'package:accountable/app/session_ui_preferences.dart';
import 'package:accountable/app/pages/transactions_page.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();
  late final AssetAppDataRepository repository;
  late final AppDataSnapshot data;

  setUpAll(() async {
    repository = AssetAppDataRepository();
    data = await repository.load();
  });

  testWidgets('renders transfer rows without narrow-layout overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await SessionUiPreferences.instance.startSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: AppShell(dataRepository: repository),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final pageTitle = tester.getRect(find.text('Transactions').first);
    final addButton = tester.getRect(
      find.widgetWithText(FilledButton, 'Add transaction'),
    );
    final filtersButton = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Filters'),
    );
    expect(addButton.height, greaterThanOrEqualTo(48));
    expect(addButton.top - pageTitle.bottom, closeTo(12, 1));
    expect(filtersButton.top - addButton.bottom, closeTo(12, 1));

    final firstDateHeader = tester.getRect(
      find.byType(TransactionDateHeader).first,
    );
    final firstTransactionCard = tester.getRect(
      find.descendant(
        of: find.byType(TransactionListRow).first,
        matching: find.byType(InkWell),
      ),
    );
    expect(
      firstTransactionCard.top - firstDateHeader.bottom,
      closeTo(8, 1),
      reason: 'Transaction cards have a visible top margin after date groups.',
    );
    final checkoutCard = tester.getRect(
      find.ancestor(of: find.text('checkout'), matching: find.byType(InkWell)),
    );
    final indiaCard = tester.getRect(
      find.ancestor(of: find.text('india'), matching: find.byType(InkWell)),
    );
    expect(
      indiaCard.top - checkoutCard.bottom,
      closeTo(8, 1),
      reason: 'Same-day cards use the same top margin without a second gap.',
    );

    await tester.scrollUntilVisible(
      find.text('Credit Payment'),
      300,
      scrollable: find
          .ancestor(
            of: find.text('Credit Payment'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Credit Payment'), findsOneWidget);
    expect(find.text('From · Chase Checking'), findsOneWidget);
    expect(find.textContaining('To · Chase Freedom Rise'), findsOneWidget);
    final transfer = data.transactions.singleWhere(
      (item) => item.description == 'Credit Payment',
    );
    expect(
      find.text('-${formatMoney(transfer.sourceAmount!, data.currenciesById)}'),
      findsOneWidget,
    );
    expect(
      find.text(
        '+${formatMoney(transfer.destinationAmount!, data.currenciesById)}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ordinary transaction row keeps its content with tighter spacing',
    (tester) async {
      const size = Size(390, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reimbursement = data.transactions.firstWhere(
        (item) => item.description == 'reimbur',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(size: size),
            child: Scaffold(
              body: ListView(
                children: [
                  TransactionListRow(
                    transaction: reimbursement,
                    data: data,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('reimbur'), findsOneWidget);
      expect(find.text('Dining · Boston'), findsOneWidget);
      expect(find.text('Chase Checking'), findsOneWidget);
      expect(find.text(r'+$ 10.00'), findsOneWidget);
      final metadata = tester.getRect(find.text('Dining · Boston'));
      final account = tester.getRect(find.text('Chase Checking'));
      final amount = tester.getRect(find.text(r'+$ 10.00'));
      final card = tester.getRect(find.byType(InkWell));
      final description = tester.getRect(find.text('reimbur'));
      expect(account.top - metadata.bottom, closeTo(1, 0.5));
      expect(
        tester.widget<Text>(find.text('Chase Checking')).style,
        tester.widget<Text>(find.text('Dining · Boston')).style,
      );
      expect(amount.left, greaterThan(card.center.dx));
      expect(amount.right, lessThan(card.right));
      expect(description.top - card.top, greaterThanOrEqualTo(4));
      expect(card.bottom - account.bottom, greaterThanOrEqualTo(3));
      expect(card.height, lessThanOrEqualTo(112));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('transfer legs and values remain explicit across phone widths', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transfer = data.transactions.singleWhere(
      (item) => item.description == 'Credit Payment',
    );
    for (final size in [
      const Size(320, 740),
      const Size(360, 800),
      const Size(430, 932),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(
              body: ListView(
                children: [
                  TransactionListRow(
                    transaction: transfer,
                    data: data,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Credit Payment'), findsOneWidget);
      expect(find.text('From · Chase Checking'), findsOneWidget);
      expect(find.textContaining('To · Chase Freedom Rise'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('From · Chase Checking')).style,
        tester.widget<Text>(find.text('General')).style,
      );
      expect(
        tester
            .widget<Text>(find.textContaining('To · Chase Freedom Rise'))
            .style,
        tester.widget<Text>(find.text('General')).style,
      );
      expect(
        find.text(
          '-${formatMoney(transfer.sourceAmount!, data.currenciesById)}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '+${formatMoney(transfer.destinationAmount!, data.currenciesById)}',
        ),
        findsOneWidget,
      );
      final transferCard = tester.getRect(
        find.descendant(
          of: find.byType(TransactionListRow),
          matching: find.byType(InkWell),
        ),
      );
      final sourceAmount = tester.getRect(
        find.text(
          '-${formatMoney(transfer.sourceAmount!, data.currenciesById)}',
        ),
      );
      final destinationAmount = tester.getRect(
        find.text(
          '+${formatMoney(transfer.destinationAmount!, data.currenciesById)}',
        ),
      );
      expect(
        transferCard.height,
        lessThan(size.width == 320 ? 190 : 170),
        reason: '${size.width}px',
      );
      expect(sourceAmount.left, greaterThan(transferCard.center.dx));
      expect(destinationAmount.left, greaterThan(transferCard.center.dx));
      expect(sourceAmount.right, lessThanOrEqualTo(transferCard.right));
      expect(destinationAmount.right, lessThanOrEqualTo(transferCard.right));
      expect(tester.takeException(), isNull, reason: '${size.width}px');
    }
  });

  testWidgets(
    'wide enlarged rows keep the amount trailing and avoid stacking',
    (tester) async {
      const size = Size(860, 844);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final reimbursement = data.transactions.firstWhere(
        (item) => item.description == 'reimbur',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: ListView(
                children: [
                  TransactionListRow(
                    transaction: reimbursement,
                    data: data,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('reimbur'), findsOneWidget);
      expect(find.text('Dining · Boston'), findsOneWidget);
      expect(find.text('Chase Checking'), findsOneWidget);
      expect(find.text(r'+$ 10.00'), findsOneWidget);
      final row = tester.getRect(find.byType(TransactionListRow));
      final card = tester.getRect(find.byType(Card));
      final amount = tester.getRect(find.text(r'+$ 10.00'));
      expect(row.height, lessThan(120));
      expect(amount.left, greaterThan(card.center.dx));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('transaction detail sheet width does not follow text length', (
    tester,
  ) async {
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await SessionUiPreferences.instance.startSession();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: TransactionsPage(
            data: data,
            onTransactionAdded: (_) async {},
            onTransactionsAdded: (_) async {},
            onTemplateAdded: (_) async {},
            onTemplateUpdated: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<double> openDetails(String description) async {
      await tester.ensureVisible(find.text(description));
      await tester.tap(find.text(description));
      await tester.pumpAndSettle();
      final width = tester.getRect(find.byType(TransactionDetailsSheet)).width;
      Navigator.of(tester.element(find.byType(TransactionDetailsSheet))).pop();
      await tester.pumpAndSettle();
      return width;
    }

    final shortWidth = await openDetails('reimbur');
    final longWidth = await openDetails('Credit Payment');
    expect(shortWidth, closeTo(size.width, 1));
    expect(longWidth, closeTo(shortWidth, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('transaction details stack account labels and full values at 320', (
    tester,
  ) async {
    const size = Size(320, 740);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final transfer = data.transactions.singleWhere(
      (item) => item.description == 'Credit Payment',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: size),
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TransactionDetailsSheet(
                      transaction: transfer,
                      data: data,
                    ),
                  ),
                  child: const Text('Open details'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open details'));
    await tester.pumpAndSettle();

    expect(find.text('Source'), findsOneWidget);
    expect(find.text('Destination'), findsOneWidget);
    expect(
      find.text(
        'Chase Checking · -${formatMoney(transfer.sourceAmount!, data.currenciesById)}',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Chase Freedom Rise · +${formatMoney(transfer.destinationAmount!, data.currenciesById)}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens compact filters, applies a type, and clears it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await SessionUiPreferences.instance.startSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: AppShell(dataRepository: repository),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.text('Apply filters'), findsOneWidget);
    await tester.tap(find.text('All Types').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(find.text('Filters (1)'), findsOneWidget);
    expect(find.text('5 pending local transactions'), findsNothing);
    expect(find.textContaining('of 8 transactions'), findsNothing);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsOneWidget);
  });
}
