import 'dart:async';

import 'package:flutter/material.dart';

/// Displays an error until the user explicitly acknowledges it.
void showPersistentErrorDialog(BuildContext context, String message) {
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Something went wrong'),
          content: SingleChildScrollView(child: SelectableText(message)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    ),
  );
}
