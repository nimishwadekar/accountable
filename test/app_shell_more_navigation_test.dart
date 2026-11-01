import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/app_shell.dart';
import 'package:accountable/app/session_ui_preferences.dart';
import 'package:accountable/app/theme/app_theme.dart';
import 'package:accountable/data/data.dart';

void main() {
  late final AssetAppDataRepository repository;

  setUpAll(() async {
    repository = AssetAppDataRepository();
    await repository.load();
  });

  testWidgets('five sections stay visible across size and startup changes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await SessionUiPreferences.instance.startSession();
    final windowSize = ValueNotifier(const Size(390, 844));
    addTearDown(windowSize.dispose);
    final systemScale = ValueNotifier(1.0);
    addTearDown(systemScale.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ValueListenableBuilder<Size>(
          valueListenable: windowSize,
          builder: (context, size, _) => ValueListenableBuilder<double>(
            valueListenable: systemScale,
            builder: (context, scale, _) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(size: size, textScaler: TextScaler.linear(scale)),
              child: AppShell(dataRepository: repository),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final navigation = find.byType(NavigationBar);
    expect(navigation, findsOneWidget);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 0);
    expect(find.text('Add transaction'), findsOneWidget);
    final destinations = tester
        .widget<NavigationBar>(navigation)
        .destinations
        .whereType<NavigationDestination>();
    expect(destinations.map((destination) => destination.label), [
      'Transactions',
      'Analysis',
      'Accounts',
      'Milestones',
      'Settings',
    ]);
    expect(find.text('More'), findsNothing);

    windowSize.value = const Size(320, 740);
    await tester.binding.setSurfaceSize(const Size(320, 740));
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .whereType<NavigationDestination>(),
      hasLength(5),
    );
    expect(tester.takeException(), isNull);
    windowSize.value = const Size(390, 844);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pump();

    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(tester.widget<NavigationBar>(navigation).selectedIndex, 4);

    await tester.tap(find.byIcon(Icons.celebration_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Milestones'), findsWidgets);

    await tester.tap(find.byIcon(Icons.account_balance_wallet_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Assets & Liabilities'), findsOneWidget);

    windowSize.value = const Size(1280, 900);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    await tester.pump();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
      2,
      reason: 'Resizing preserves the selected content section.',
    );

    windowSize.value = const Size(390, 844);
    systemScale.value = 2;
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Navigate'), findsNothing);
    expect(
      tester
          .widget<NavigationBar>(find.byType(NavigationBar))
          .destinations
          .whereType<NavigationDestination>()
          .map((destination) => destination.label),
      ['Transactions', 'Analysis', 'Accounts', 'Milestones', 'Settings'],
    );
    expect(tester.takeException(), isNull);
    systemScale.value = 1;
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    windowSize.value = const Size(390, 844);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('restricted-startup'),
        theme: AppTheme.light(),
        home: ValueListenableBuilder<Size>(
          valueListenable: windowSize,
          builder: (context, size, _) => ValueListenableBuilder<double>(
            valueListenable: systemScale,
            builder: (context, scale, _) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(size: size, textScaler: TextScaler.linear(scale)),
              child: AppShell(
                dataRepository: repository,
                restrictedStartup: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    final restricted = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(restricted.selectedIndex, 0);
    expect(
      restricted.destinations
          .whereType<NavigationDestination>()
          .elementAt(4)
          .enabled,
      isFalse,
    );
    expect(find.text('8 pending local transactions'), findsOneWidget);
  });

  testWidgets('More appears only when an optional sixth section is enabled', (
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
          child: AppShell(
            dataRepository: repository,
            migrationAssistance: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      navigation.destinations.whereType<NavigationDestination>().map(
        (destination) => destination.label,
      ),
      [
        'Transactions',
        'Analysis',
        'Accounts',
        'Milestones',
        'Settings',
        'More',
      ],
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('More destinations'), findsOneWidget);
    final moreSheet = find.byType(BottomSheet).last;
    expect(
      find.descendant(
        of: moreSheet,
        matching: find.text('Migration Assistance'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: moreSheet, matching: find.text('Milestones')),
      findsNothing,
    );
    expect(
      find.descendant(of: moreSheet, matching: find.text('Settings')),
      findsNothing,
    );
  });
}
