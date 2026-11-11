import 'dart:async';

import 'package:flutter/material.dart';

import 'theme/design_tokens.dart';

/// Shows why daily history needs a rebuild and runs the rebuild action.
///
/// The dialog stays open while [onRebuild] runs and reports a failure inline so
/// the action can be retried. Returns true when [onRebuild] completed without
/// throwing.
Future<bool> showDailyHistoryRebuildDialog({
  required BuildContext context,
  required String message,
  required Future<void> Function() onRebuild,
}) async {
  var status = message;
  var rebuilding = false;
  var succeeded = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => PopScope(
        canPop: !rebuilding,
        child: AlertDialog(
          title: const Text('Daily history needs a rebuild'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(status),
                if (rebuilding) ...[
                  const SizedBox(height: AppSpacing.md),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: rebuilding
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: rebuilding
                  ? null
                  : () {
                      setDialogState(() => rebuilding = true);
                      unawaited(() async {
                        try {
                          await onRebuild();
                          succeeded = true;
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (error) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            rebuilding = false;
                            status =
                                'Could not rebuild daily tables: $error '
                                'Check your connection and try again.';
                          });
                        }
                      }());
                    },
              icon: const Icon(Icons.refresh),
              label: Text(rebuilding ? 'Rebuilding…' : 'Rebuild daily tables'),
            ),
          ],
        ),
      ),
    ),
  );
  return succeeded;
}
