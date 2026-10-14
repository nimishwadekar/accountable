import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/data.dart';
import '../theme/design_tokens.dart';

class TransactionTypeChooser extends StatelessWidget {
  const TransactionTypeChooser({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add transaction',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final type in TransactionType.values)
              ListTile(
                leading: Icon(_typeIcon(type)),
                title: Text(transactionTypeLabel(type)),
                onTap: () => Navigator.of(context).pop(type),
              ),
          ],
        ),
      ),
    );
  }
}

class TransactionFormSheet extends StatefulWidget {
  const TransactionFormSheet({
    super.key,
    required this.type,
    required this.data,
  });

  final TransactionType type;
  final AppDataSnapshot data;

  @override
  State<TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _sourceAmountController = TextEditingController();
  final _destinationAmountController = TextEditingController();
  final _descriptionController = TextEditingController();

  late DateTime _date = DateTime.now();
  String? _sourceAccountId;
  String? _destinationAccountId;
  String? _categoryId;
  String? _tagId;

  bool get _sourceRequired => transactionTypeRules[widget.type]!.sourceRequired;
  bool get _destinationRequired =>
      transactionTypeRules[widget.type]!.destinationRequired;
  bool get _categoryRequired =>
      transactionTypeRules[widget.type]!.categoryRequired;

  List<Category> get _availableCategories => widget.data.categories
      .where(
        (category) => category.allowedTransactionTypes.contains(widget.type),
      )
      .toList();

  @override
  void dispose() {
    _sourceAmountController.dispose();
    _destinationAmountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            transactionTypeLabel(widget.type),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
            textInputAction: TextInputAction.next,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a description.'
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_formatDate(_date)),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_sourceRequired) ...[
            _accountDropdown(
              label: 'Source account',
              value: _sourceAccountId,
              onChanged: (value) => setState(() => _sourceAccountId = value),
            ),
            const SizedBox(height: AppSpacing.md),
            _amountField(
              controller: _sourceAmountController,
              label: 'Source amount',
            ),
            if (_destinationRequired) const SizedBox(height: AppSpacing.md),
          ],
          if (_destinationRequired) ...[
            _accountDropdown(
              label: 'Destination account',
              value: _destinationAccountId,
              onChanged: (value) =>
                  setState(() => _destinationAccountId = value),
            ),
            const SizedBox(height: AppSpacing.md),
            _amountField(
              controller: _destinationAmountController,
              label: 'Destination amount',
            ),
          ],
          if (_categoryRequired || _availableCategories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _categoryDropdown(),
          ],
          const SizedBox(height: AppSpacing.md),
          _tagDropdown(),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _submit,
            child: const Text('Add transaction'),
          ),
        ],
      ),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: content,
      ),
    );
  }

  Widget _accountDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      validator: (value) => value == null ? 'Select an account.' : null,
      items: [
        for (final account in widget.data.accounts)
          DropdownMenuItem<String>(
            value: account.id,
            child: Text('${account.name} (${account.currencyId})'),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter an amount.';
        }
        final parsed = num.tryParse(value.trim());
        if (parsed == null || parsed < 0) return 'Enter a valid amount.';
        return null;
      },
    );
  }

  Widget _categoryDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _categoryId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: _categoryRequired ? 'Category' : 'Category (optional)',
      ),
      validator: (value) =>
          _categoryRequired && value == null ? 'Select a category.' : null,
      items: [
        if (!_categoryRequired)
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('No category'),
          ),
        for (final category in _availableCategories)
          DropdownMenuItem<String?>(
            value: category.id,
            child: Text(category.name),
          ),
      ],
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }

  Widget _tagDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _tagId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Tag'),
      validator: (value) => value == null ? 'Select a tag.' : null,
      items: [
        for (final tag in widget.data.tags)
          DropdownMenuItem<String?>(value: tag.id, child: Text(tag.name)),
      ],
      onChanged: (value) => setState(() => _tagId = value),
    );
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted || selected == null) return;
    setState(() => _date = selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final sourceAccount = _sourceAccountId == null
        ? null
        : widget.data.accountsById[_sourceAccountId!];
    final destinationAccount = _destinationAccountId == null
        ? null
        : widget.data.accountsById[_destinationAccountId!];
    final sourceAmount = _parseAmount(
      _sourceAmountController.text,
      sourceAccount,
    );
    final destinationAmount = _parseAmount(
      _destinationAmountController.text,
      destinationAccount,
    );
    if (sourceAmount == null && _sourceRequired ||
        destinationAmount == null && _destinationRequired) {
      return;
    }

    final transaction = Transaction(
      id: const Uuid().v4(),
      createdAt: DateTime.now().toUtc(),
      date: DateTime.utc(_date.year, _date.month, _date.day),
      type: widget.type,
      sourceAmount: sourceAmount,
      sourceAccountId: _sourceAccountId,
      destinationAmount: destinationAmount,
      destinationAccountId: _destinationAccountId,
      categoryId: _categoryId,
      tagId: _tagId,
      description: _descriptionController.text.trim(),
    );
    final errors = transaction.validateForEntry();
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errors.join(' '))));
      return;
    }
    Navigator.of(context).pop(transaction);
  }

  Money? _parseAmount(String value, Account? account) {
    if (value.trim().isEmpty || account == null) return null;
    try {
      return Money.fromMajorUnits(
        value: value,
        currency: widget.data.currenciesById[account.currencyId]!,
      );
    } on FormatException {
      return null;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

String transactionTypeLabel(TransactionType type) {
  return switch (type) {
    TransactionType.expense => 'Expense',
    TransactionType.income => 'Income',
    TransactionType.reimbursement => 'Reimbursement',
    TransactionType.transfer => 'Transfer',
  };
}

IconData _typeIcon(TransactionType type) {
  return switch (type) {
    TransactionType.expense => Icons.arrow_upward,
    TransactionType.income => Icons.arrow_downward,
    TransactionType.reimbursement => Icons.replay,
    TransactionType.transfer => Icons.swap_horiz,
  };
}
