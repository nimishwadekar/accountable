import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../theme/design_tokens.dart';

class CategoryChoice {
  const CategoryChoice(this.id);

  final String? id;
}

class TransactionAccountSelector extends StatelessWidget {
  const TransactionAccountSelector({
    super.key,
    required this.label,
    required this.value,
    required this.accounts,
    required this.data,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Account> accounts;
  final AppDataSnapshot data;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == null ? null : data.accountsById[value!];
    return FormField<String>(
      initialValue: value,
      validator: (current) => current == null ? 'Select an account.' : null,
      builder: (field) => _SelectorField(
        label: label,
        errorText: field.errorText,
        child: selected == null
            ? const Text('Select account')
            : _AccountSummary(account: selected, data: data),
        onTap: () async {
          final selectedId = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _AccountPicker(
              accounts: accounts,
              data: data,
              selectedId: value,
            ),
          );
          if (selectedId == null) return;
          field.didChange(selectedId);
          onChanged(selectedId);
        },
      ),
    );
  }
}

class TransactionCategorySelector extends StatelessWidget {
  const TransactionCategorySelector({
    super.key,
    required this.label,
    required this.value,
    required this.categories,
    required this.requiredSelection,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Category> categories;
  final bool requiredSelection;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value == null
        ? null
        : categories.where((category) => category.id == value).firstOrNull;
    return FormField<String?>(
      initialValue: value,
      validator: (current) =>
          requiredSelection && current == null ? 'Select a category.' : null,
      builder: (field) => _SelectorField(
        label: label,
        errorText: field.errorText,
        child: selected == null
            ? Text(requiredSelection ? 'Select category' : 'No category')
            : _CategorySummary(category: selected),
        onTap: () async {
          final choice = await showModalBottomSheet<CategoryChoice>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => _CategoryPicker(
              categories: categories,
              selectedId: value,
              requiredSelection: requiredSelection,
            ),
          );
          if (choice == null) return;
          field.didChange(choice.id);
          onChanged(choice.id);
        },
      ),
    );
  }
}

class _SelectorField extends StatelessWidget {
  const _SelectorField({
    required this.label,
    required this.child,
    required this.onTap,
    this.errorText,
  });

  final String label;
  final Widget child;
  final VoidCallback onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.control),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          suffixIcon: const Icon(Icons.expand_more),
        ),
        child: child,
      ),
    );
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.account, required this.data});

  final Account account;
  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final currency = data.currenciesById[account.currencyId];
    return Row(
      children: [
        Icon(
          account.isLiability ? Icons.credit_card : Icons.account_balance,
          color: _accountTypeColor(account),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(account.name, overflow: TextOverflow.ellipsis)),
        Text(
          currency?.id ?? account.currencyId,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

Color _accountTypeColor(Account account) {
  final type = account.accountType.trim().toLowerCase();
  if (account.isLiability || type == 'credit') return AppColors.danger;
  if (type == 'asset') return AppColors.success;
  return const Color(0xFF90CAF9);
}

String _accountTypeLabel(Account account) {
  final type = account.accountType.trim().toLowerCase();
  if (type == 'cash') return '';
  return type.isEmpty ? '' : '${type[0].toUpperCase()}${type.substring(1)}';
}

class _CategorySummary extends StatelessWidget {
  const _CategorySummary({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(categoryIcon(category), color: categoryColor(category)),
        const SizedBox(width: AppSpacing.sm),
        Text(category.name),
      ],
    );
  }
}

class _AccountPicker extends StatelessWidget {
  const _AccountPicker({
    required this.accounts,
    required this.data,
    required this.selectedId,
  });

  final List<Account> accounts;
  final AppDataSnapshot data;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select account',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final account in accounts)
                Card(
                  color: account.id == selectedId
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : _accountTypeColor(account).withValues(alpha: 0.06),
                  child: ListTile(
                    leading: Icon(
                      account.isLiability
                          ? Icons.credit_card
                          : Icons.account_balance,
                      color: _accountTypeColor(account),
                    ),
                    title: Text(account.name),
                    subtitle: Text(
                      [
                        account.currencyId,
                        if (_accountTypeLabel(account).isNotEmpty)
                          _accountTypeLabel(account),
                      ].join(' · '),
                    ),
                    trailing: account.id == selectedId
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.of(context).pop(account.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({
    required this.categories,
    required this.selectedId,
    required this.requiredSelection,
  });

  final List<Category> categories;
  final String? selectedId;
  final bool requiredSelection;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Select category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              if (!requiredSelection)
                _CategoryTile(
                  label: 'No category',
                  icon: Icons.remove_circle_outline,
                  color: AppColors.mutedText,
                  selected: selectedId == null,
                  onTap: () =>
                      Navigator.of(context).pop(const CategoryChoice(null)),
                ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: AppSpacing.sm,
                  mainAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 1.15,
                ),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return _CategoryTile(
                    label: category.name,
                    icon: categoryIcon(category),
                    color: categoryColor(category),
                    selected: category.id == selectedId,
                    onTap: () =>
                        Navigator.of(context).pop(CategoryChoice(category.id)),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? color.withValues(alpha: 0.18) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData categoryIcon(Category category) {
  final text = '${category.id} ${category.name}'.toLowerCase();
  if (_categoryContains(text, ['dining', 'restaurant', 'food', 'meal'])) {
    return Icons.restaurant;
  }
  if (_categoryContains(text, ['groceries'])) {
    return Icons.eco;
  }
  if (_categoryContains(text, ['shopping', 'clothing'])) {
    return Icons.shopping_bag;
  }
  if (_categoryContains(text, ['personal', 'beauty'])) return Icons.spa;
  if (_categoryContains(text, ['nightlife', 'bar', 'drinks', 'alcohol'])) {
    return Icons.wine_bar;
  }
  if (_categoryContains(text, ['gifts', 'gift'])) {
    return Icons.card_giftcard;
  }
  if (_categoryContains(text, ['travel'])) {
    return Icons.directions_car;
  }
  if (_categoryContains(text, ['transport', 'fuel', 'car'])) {
    return Icons.train;
  }
  if (_categoryContains(text, ['health', 'medical', 'dental'])) {
    return Icons.health_and_safety;
  }
  if (_categoryContains(text, ['housing', 'rent', 'home'])) return Icons.home;
  if (_categoryContains(text, ['bills', 'bill'])) {
    return Icons.note_alt;
  }
  if (_categoryContains(text, ['utilities', 'internet', 'phone'])) {
    return Icons.receipt_long;
  }
  if (_categoryContains(text, ['entertainment', 'leisure', 'hobby'])) {
    return Icons.movie;
  }
  if (_categoryContains(text, ['education', 'school', 'course'])) {
    return Icons.school;
  }
  if (_categoryContains(text, ['tax', 'government', 'fee'])) {
    return Icons.account_balance;
  }
  return Icons.category_outlined;
}

Color categoryColor(Category category) {
  final text = '${category.id} ${category.name}'.toLowerCase();
  if (_categoryContains(text, ['dining', 'restaurant', 'food', 'meal'])) {
    return const Color(0xFFE76F51);
  }
  if (_categoryContains(text, ['groceries'])) {
    return const Color(0xFF4CAF50);
  }
  if (_categoryContains(text, ['shopping', 'clothing'])) {
    return const Color(0xFF7B61FF);
  }
  if (_categoryContains(text, ['personal', 'beauty'])) {
    return const Color(0xFFE07A5F);
  }
  if (_categoryContains(text, ['nightlife', 'bar', 'drinks', 'alcohol'])) {
    return const Color(0xFF9B5DE5);
  }
  if (_categoryContains(text, ['gifts', 'gift'])) {
    return const Color(0xFFE63946);
  }
  if (_categoryContains(text, ['travel'])) {
    return const Color(0xFF2A9D8F);
  }
  if (_categoryContains(text, ['transport', 'fuel', 'car'])) {
    return const Color(0xFF277DA1);
  }
  if (_categoryContains(text, ['health', 'medical', 'dental'])) {
    return const Color(0xFFD1495B);
  }
  if (_categoryContains(text, ['housing', 'rent', 'home'])) {
    return const Color(0xFF457B9D);
  }
  if (_categoryContains(text, ['bills', 'bill'])) {
    return const Color(0xFF8D99AE);
  }
  if (_categoryContains(text, ['utilities', 'internet', 'phone'])) {
    return const Color(0xFFF4A261);
  }
  if (_categoryContains(text, ['entertainment', 'leisure', 'hobby'])) {
    return const Color(0xFF6A4C93);
  }
  if (_categoryContains(text, ['education', 'school', 'course'])) {
    return const Color(0xFF277DA1);
  }
  if (_categoryContains(text, ['tax', 'government', 'fee'])) {
    return const Color(0xFF606C38);
  }
  return AppColors.teal;
}

bool _categoryContains(String text, List<String> terms) =>
    terms.any(text.contains);
