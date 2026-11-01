import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';
import 'account_visuals.dart';

String accountSubtitle(
  Account account,
  Map<String, CurrencyDefinition> currencies,
) {
  final currency = currencies[account.currencyId];
  final currencyCode = currency?.id ?? account.currencyId;
  final type = account.accountTypeKind;
  if (type == AccountType.cash) return currencyCode;
  return '$currencyCode · ${type.displayName}';
}

class AccountBalanceRow extends StatelessWidget {
  const AccountBalanceRow({
    super.key,
    required this.account,
    required this.amount,
    required this.currencies,
  });

  final Account account;
  final Money? amount;
  final Map<String, CurrencyDefinition> currencies;

  @override
  Widget build(BuildContext context) {
    final valueColor = amount == null
        ? null
        : amountColor(context, amount!.minorUnits);
    final text = amount == null || !currencies.containsKey(amount!.currencyId)
        ? '—'
        : formatMoney(amount!, currencies);
    final amountStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      color: valueColor,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final enlargedText = MediaQuery.textScalerOf(context).scale(14) > 16.8;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < AppBreakpoints.compact || enlargedText;
        final compactSpacing = usesCompactVerticalSpacing(
          context,
          availableWidth: constraints.maxWidth,
        );
        final amountPainter = TextPainter(
          text: TextSpan(text: text, style: amountStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        const leadingWidth = 40.0;
        const minimumIdentityWidth = 88.0;
        final trailingAmountBudget =
            constraints.maxWidth -
            AppSpacing.md * 2 -
            leadingWidth -
            AppSpacing.sm * 2 -
            minimumIdentityWidth;
        final showAmountOnRight =
            trailingAmountBudget >= 72 &&
            amountPainter.width <= trailingAmountBudget;
        return Container(
          color: accountTypeColor(account).withValues(alpha: 0.06),
          child: compact
              ? Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: compactSpacing ? AppSpacing.sm : AppSpacing.md,
                  ),
                  child: showAmountOnRight
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: accountTypeColor(account)
                                  .withValues(alpha: 0.14),
                              foregroundColor: accountTypeColor(account),
                              child: AccountVisualIcon(
                                account: account,
                                currencies: currencies,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(child: _buildIdentity(context)),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: amountPainter.width,
                              child: _CompleteAccountAmount(
                                text: text,
                                style: amountStyle,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  backgroundColor: accountTypeColor(account)
                                      .withValues(alpha: 0.14),
                                  foregroundColor: accountTypeColor(account),
                                  child: AccountVisualIcon(
                                    account: account,
                                    currencies: currencies,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(child: _buildIdentity(context)),
                              ],
                            ),
                            SizedBox(
                              height: compactSpacing
                                  ? AppSpacing.xs
                                  : AppSpacing.sm,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _CompleteAccountAmount(
                                text: text,
                                style: amountStyle,
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                )
              : ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: accountTypeColor(account)
                        .withValues(alpha: 0.14),
                    foregroundColor: accountTypeColor(account),
                    child: AccountVisualIcon(
                      account: account,
                      currencies: currencies,
                    ),
                  ),
                  title: Text(account.name),
                  subtitle: Text(accountSubtitle(account, currencies)),
                  trailing: _CompleteAccountAmount(
                    text: text,
                    style: amountStyle,
                    textAlign: TextAlign.right,
                  ),
                ),
        );
      },
    );
  }

  Widget _buildIdentity(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(account.name),
      Text(
        accountSubtitle(account, currencies),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _CompleteAccountAmount extends StatelessWidget {
  const _CompleteAccountAmount({
    required this.text,
    required this.style,
    this.textAlign = TextAlign.left,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final amount = Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: textAlign,
        style: style,
      );
      if (painter.width <= constraints.maxWidth ||
          !constraints.maxWidth.isFinite) {
        return amount;
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: amount,
      );
    },
  );
}

Color? amountColor(BuildContext context, int minorUnits) {
  if (minorUnits > 0) return AppColors.success;
  if (minorUnits < 0) return Theme.of(context).colorScheme.error;
  return null;
}
