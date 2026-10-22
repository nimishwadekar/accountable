import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import '../../data/data.dart';

class IncomeAllocationDialog extends StatefulWidget {
  const IncomeAllocationDialog({super.key, required this.data});

  final AppDataSnapshot data;

  @override
  State<IncomeAllocationDialog> createState() => _IncomeAllocationDialogState();
}

class _IncomeAllocationDialogState extends State<IncomeAllocationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  String? _categoryId;
  String? _incomeAccountId;
  String? _transferCategoryId;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final incomeCategories = widget.data.entryFormCategories
        .where(
          (category) =>
              category.allowedTransactionTypes.contains(TransactionType.income),
        )
        .toList();
    final accounts = widget.data.entryFormAccounts;
    return AlertDialog(
      title: const Text('Add Income Allocation'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: _required,
                ),
                const SizedBox(height: AppSpacing.md),
                _dropdown<String>(
                  label: 'Income Category',
                  value: _categoryId,
                  items: [
                    for (final category in incomeCategories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _categoryId = value),
                ),
                const SizedBox(height: AppSpacing.md),
                _dropdown<String>(
                  label: 'Income Account',
                  value: _incomeAccountId,
                  items: [
                    for (final account in accounts)
                      DropdownMenuItem(
                        value: account.id,
                        child: Text(account.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _incomeAccountId = value),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _amount,
                  decoration: const InputDecoration(
                    labelText: 'Expected Amount per Income',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _amountValidator,
                ),
                const SizedBox(height: AppSpacing.md),
                _dropdown<String>(
                  label: 'Transfer Category',
                  value: _transferCategoryId,
                  items: [
                    for (final category
                        in widget.data.entryFormCategories.where(
                          (category) => category.allowedTransactionTypes
                              .contains(TransactionType.transfer),
                        ))
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _transferCategoryId = value),
                ),
                const SizedBox(height: AppSpacing.md),
                _dateButton(
                  'Start Date',
                  _startDate,
                  (value) => setState(() => _startDate = value),
                ),
                _dateButton(
                  'End Date (optional)',
                  _endDate,
                  (value) => setState(() => _endDate = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: items,
      validator: (value) => value == null ? 'Select a value.' : null,
      onChanged: onChanged,
    );
  }

  Widget _dateButton(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onChanged,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () async {
          final selected = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 3650)),
          );
          if (selected != null) onChanged(selected);
        },
        icon: const Icon(Icons.calendar_today_outlined),
        label: Text(
          value == null
              ? label
              : '$label: ${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required.' : null;

  String? _amountValidator(String? value) {
    if (_required(value) != null) return _required(value);
    final parsed = num.tryParse(value!.trim());
    return parsed == null || parsed <= 0 ? 'Enter a positive amount.' : null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be after start date.')),
      );
      return;
    }
    final now = DateTime.now().toUtc();
    final incomeAccount = widget.data.accountsById[_incomeAccountId!]!;
    final currency = widget.data.currenciesById[incomeAccount.currencyId]!;
    Navigator.pop(
      context,
      IncomeAllocation(
        id: 'income-allocation-${now.microsecondsSinceEpoch}',
        name: _name.text.trim(),
        incomeCategoryId: _categoryId!,
        incomeAccountId: _incomeAccountId!,
        transferCategoryId: _transferCategoryId!,
        expectedAmountPerIncome: Money.fromMajorUnits(
          value: _amount.text.trim(),
          currency: currency,
        ),
        startDate: _startDate,
        endDate: _endDate,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}
