import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:accountable/app/daily_history_rebuild_dialog.dart';
import 'package:accountable/app/theme/app_theme.dart';

void main() {
  testWidgets('shows the reason and runs the rebuild action', (tester) async {
    var rebuildCalls = 0;
    final completion = Completer<void>();
    var dialogResult = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                unawaited(
                  showDailyHistoryRebuildDialog(
                    context: context,
                    message:
                        'No INR exchange rate exists on or before 2026-10-10.',
                    onRebuild: () async {
                      rebuildCalls++;
                      await completion.future;
                    },
                  ).then((value) => dialogResult = value),
                );
              },
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Daily history needs a rebuild'), findsOneWidget);
    expect(
      find.text('No INR exchange rate exists on or before 2026-10-10.'),
      findsOneWidget,
    );
    expect(find.text('Rebuild daily tables'), findsOneWidget);

    await tester.tap(find.text('Rebuild daily tables'));
    await tester.pump();
    expect(rebuildCalls, 1);
    expect(find.text('Rebuilding…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Rebuilding…'),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
          .enabled,
      isFalse,
    );

    completion.complete();
    await tester.pumpAndSettle();
    expect(find.text('Daily history needs a rebuild'), findsNothing);
    expect(dialogResult, isTrue);
  });

  testWidgets('keeps the dialog retryable when the rebuild fails', (
    tester,
  ) async {
    var rebuildCalls = 0;
    var dialogResult = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                unawaited(
                  showDailyHistoryRebuildDialog(
                    context: context,
                    message: 'DailyNetWorth has no rows.',
                    onRebuild: () async {
                      rebuildCalls++;
                      if (rebuildCalls == 1) {
                        throw StateError('network down');
                      }
                    },
                  ).then((value) => dialogResult = value),
                );
              },
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rebuild daily tables'));
    await tester.pumpAndSettle();
    expect(rebuildCalls, 1);
    expect(
      find.textContaining('Could not rebuild daily tables'),
      findsOneWidget,
    );
    expect(find.text('Rebuild daily tables'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.text('Rebuild daily tables'));
    await tester.pumpAndSettle();
    expect(rebuildCalls, 2);
    expect(find.text('Daily history needs a rebuild'), findsNothing);
    expect(dialogResult, isTrue);
  });

  testWidgets('closing the dialog reports no rebuild', (tester) async {
    var rebuildCalls = 0;
    var dialogResult = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () {
                unawaited(
                  showDailyHistoryRebuildDialog(
                    context: context,
                    message: 'DailyNetWorth has no rows.',
                    onRebuild: () async {
                      rebuildCalls++;
                    },
                  ).then((value) => dialogResult = value),
                );
              },
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(rebuildCalls, 0);
    expect(find.text('Daily history needs a rebuild'), findsNothing);
    expect(dialogResult, isFalse);
  });
}
