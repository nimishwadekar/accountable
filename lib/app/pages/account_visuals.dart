import 'package:flutter/material.dart';

import '../../data/models/models.dart';
import '../theme/design_tokens.dart';

class AccountVisualIcon extends StatelessWidget {
  const AccountVisualIcon({
    super.key,
    required this.account,
    required this.currencies,
    this.size,
  });

  final Account account;
  final Map<String, CurrencyDefinition> currencies;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final color = accountTypeColor(account);
    final icon = _baseIcon(account);
    if (account.accountTypeKind != AccountType.cash) {
      return Icon(icon, size: size, color: color);
    }

    final currencySymbol =
        currencies[account.currencyId]?.symbol ?? account.currencyId;
    return SizedBox(
      width: size ?? 24,
      height: size ?? 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon, size: size, color: color),
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                currencySymbol,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _baseIcon(Account account) {
  final name = account.name.toLowerCase();
  if (name.contains('credit') || name.contains('card')) {
    return Icons.credit_card;
  }
  if (name.contains('loan') || name.contains('mortgage')) {
    return Icons.request_quote_outlined;
  }
  return switch (account.accountTypeKind) {
    AccountType.cash => Icons.account_balance,
    AccountType.asset => Icons.trending_up,
    AccountType.liability => Icons.account_balance,
  };
}

Color accountTypeColor(Account account) {
  return switch (account.accountTypeKind) {
    AccountType.cash => const Color(0xFF90CAF9),
    AccountType.asset => AppColors.success,
    AccountType.liability => AppColors.danger,
  };
}

String accountTypeLabel(Account account) => account.accountTypeKind.displayName;
