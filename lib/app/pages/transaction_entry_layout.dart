import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

class TransactionEntryHeader extends StatelessWidget {
  const TransactionEntryHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.onBack,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? AppPageSpacing.compactGutter : AppPageSpacing.desktopGutter,
        AppSpacing.xs,
        compact ? AppPageSpacing.compactGutter : AppPageSpacing.desktopGutter,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              tooltip: 'Back',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
