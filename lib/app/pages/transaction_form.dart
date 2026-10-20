import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../theme/design_tokens.dart';
import 'transaction_form_selectors.dart';

class AddTransactionChoice {
  const AddTransactionChoice({
    this.type,
    this.template,
    this.createTemplate = false,
  });

  final TransactionType? type;
  final TransactionTemplate? template;
  final bool createTemplate;
}

class TransactionTypeChooser extends StatelessWidget {
  const TransactionTypeChooser({
    super.key,
    this.data,
    this.createTemplate = false,
  });

  final AppDataSnapshot? data;
  final bool createTemplate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    createTemplate ? 'Create Template' : 'Add Transaction',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (!createTemplate &&
                data?.transactionTemplates.isNotEmpty == true) ...[
              const Text('Templates'),
              for (final template in data!.transactionTemplates)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(template.name),
                  subtitle: Text(transactionTypeLabel(template.type)),
                  onTap: () => Navigator.of(context).pop(
                    AddTransactionChoice(
                      type: template.type,
                      template: template,
                    ),
                  ),
                ),
              const Divider(),
            ],
            if (!createTemplate)
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Create Template'),
                onTap: () =>
                    Navigator.of(context)
                        .pop(const AddTransactionChoice(createTemplate: true)),
              ),
            const SizedBox(height: AppSpacing.md),
            Text(createTemplate ? 'Transaction Type' : 'Transaction Types'),
            for (final type in TransactionType.values)
              ListTile(
                leading: Icon(_typeIcon(type)),
                title: Text(transactionTypeLabel(type)),
                onTap: () =>
                    Navigator.of(context).pop(AddTransactionChoice(type: type)),
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
    this.template,
    this.createTemplate = false,
    this.editTemplate = false,
  });

  final TransactionType type;
  final AppDataSnapshot data;
  final TransactionTemplate? template;
  final bool createTemplate;
  final bool editTemplate;

  @override
  State<TransactionFormSheet> createState() => _TransactionFormSheetState();
}

class _TransactionFormSheetState extends State<TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _sourceAmountController = TextEditingController();
  final _destinationAmountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _templateNameController = TextEditingController();

  DateTime? _date;
  String? _sourceAccountId;
  String? _destinationAccountId;
  String? _categoryId;
  String? _tagId;

  bool get _sourceRequired => transactionTypeRules[widget.type]!.sourceRequired;
  bool get _destinationRequired =>
      transactionTypeRules[widget.type]!.destinationRequired;
  bool get _categoryRequired =>
      transactionTypeRules[widget.type]!.categoryRequired;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _date = template?.date ?? (widget.createTemplate ? null : DateTime.now());
    _descriptionController.text = template?.description ?? '';
    _sourceAccountId = template?.sourceAccountId;
    _destinationAccountId = template?.destinationAccountId;
    _categoryId = template?.categoryId;
    _tagId = template?.tagId;
    if (template?.sourceAmount != null) {
      _sourceAmountController.text = template!.sourceAmount!
          .toMajorUnits(
            widget.data.currenciesById[template.sourceAmount!.currencyId]!,
          )
          .toString();
    }
    if (template?.destinationAmount != null) {
      _destinationAmountController.text = template!.destinationAmount!
          .toMajorUnits(
            widget.data.currenciesById[template.destinationAmount!.currencyId]!,
          )
          .toString();
    }
  }

  List<Category> get _availableCategories => widget.data.entryFormCategories
      .where(
        (category) => category.allowedTransactionTypes.contains(widget.type),
      )
      .toList();

  @override
  void dispose() {
    _sourceAmountController.dispose();
    _destinationAmountController.dispose();
    _descriptionController.dispose();
    _templateNameController.dispose();
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
            widget.createTemplate
                ? 'Create Template'
                : transactionTypeLabel(widget.type),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (widget.createTemplate) ...[
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _templateNameController,
              decoration: const InputDecoration(labelText: 'Template Name'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a template name.'
                  : null,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (widget.template == null || !widget.template!.hasDescription)
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  !widget.createTemplate &&
                      (value == null || value.trim().isEmpty)
                  ? 'Enter a description.'
                  : null,
            ),
          const SizedBox(height: AppSpacing.md),
          if (widget.template == null || widget.template!.date == null)
            OutlinedButton.icon(
              onPressed: _selectDate,
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_date == null ? 'Select date' : _formatDate(_date!)),
            ),
          const SizedBox(height: AppSpacing.md),
          if (_sourceRequired &&
              (widget.template == null ||
                  widget.template!.sourceAccountId == null)) ...[
            _accountDropdown(
              label: _destinationRequired ? 'Source Account' : 'Account',
              value: _sourceAccountId,
              onChanged: (value) => setState(() => _sourceAccountId = value),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_sourceRequired &&
              (widget.template == null ||
                  widget.template!.sourceAmount == null)) ...[
            _amountField(
              controller: _sourceAmountController,
              label: _destinationRequired ? 'Source Amount' : 'Amount',
              accountId: _sourceAccountId,
            ),
            if (_destinationRequired) const SizedBox(height: AppSpacing.md),
          ],
          if (_destinationRequired &&
              (widget.template == null ||
                  widget.template!.destinationAccountId == null)) ...[
            _accountDropdown(
              label: _sourceRequired ? 'Destination Account' : 'Account',
              value: _destinationAccountId,
              onChanged: (value) =>
                  setState(() => _destinationAccountId = value),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_destinationRequired &&
              (widget.template == null ||
                  widget.template!.destinationAmount == null))
            _amountField(
              controller: _destinationAmountController,
              label: _sourceRequired ? 'Destination Amount' : 'Amount',
              accountId: _destinationAccountId,
            ),
          if ((widget.template == null ||
                  widget.template!.categoryId == null) &&
              (_categoryRequired || _availableCategories.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.md),
            _categoryDropdown(),
          ],
          if (widget.template == null || widget.template!.tagId == null) ...[
            const SizedBox(height: AppSpacing.md),
            _tagDropdown(),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _submit,
            child: const Text('Add Transaction'),
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
    return TransactionAccountSelector(
      label: label,
      value: value,
      accounts: widget.data.entryFormAccounts,
      data: widget.data,
      requiredSelection: !widget.createTemplate,
      onChanged: onChanged,
    );
  }

  Widget _amountField({
    required TextEditingController controller,
    required String label,
    required String? accountId,
  }) {
    final account = accountId == null
        ? null
        : widget.data.accountsById[accountId];
    final currency = account == null
        ? null
        : widget.data.currenciesById[account.currencyId];
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixText: currency == null ? null : '${currency.symbol} ',
        prefixStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (widget.createTemplate && (value == null || value.trim().isEmpty)) {
          return null;
        }
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
    return TransactionCategorySelector(
      label: _categoryRequired ? 'Category' : 'Category (optional)',
      value: _categoryId,
      categories: _availableCategories,
      requiredSelection: _categoryRequired && !widget.createTemplate,
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }

  Widget _tagDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _tagId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Tag'),
      validator: (value) =>
          !widget.createTemplate && value == null ? 'Select a tag.' : null,
      items: [
        for (final tag in widget.data.entryFormTags)
          DropdownMenuItem<String?>(value: tag.id, child: Text(tag.name)),
      ],
      onChanged: (value) => setState(() => _tagId = value),
    );
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (!mounted || selected == null) return;
    setState(() => _date = selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    if (!widget.createTemplate && _date == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a date.')));
      return;
    }
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
    if (!widget.createTemplate &&
        (sourceAmount == null && _sourceRequired ||
            destinationAmount == null && _destinationRequired)) {
      return;
    }
    if (widget.createTemplate) {
      final now = DateTime.now().toUtc();
      Navigator.of(context).pop(
        TransactionTemplate(
          id: generateTransactionId(widget.data.transactionTemplatesById.keys),
          name: _templateNameController.text.trim(),
          type: widget.type,
          date: _date,
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          categoryId: _categoryId,
          tagId: _tagId,
          sourceAccountId: _sourceAccountId,
          sourceAmount: sourceAmount,
          destinationAccountId: _destinationAccountId,
          destinationAmount: destinationAmount,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return;
    }

    final transaction = Transaction(
      id: generateTransactionId(widget.data.transactionsById.keys),
      createdAt: DateTime.now().toUtc(),
      date: DateTime.utc(_date!.year, _date!.month, _date!.day),
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

const _transactionIdAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _transactionIdLength = 12;

String generateTransactionId(Iterable<String> existingIds, {Random? random}) {
  final existing = existingIds.toSet();
  final generator = random ?? Random.secure();
  String candidate;
  do {
    candidate = List.generate(
      _transactionIdLength,
      (_) =>
          _transactionIdAlphabet[generator.nextInt(
            _transactionIdAlphabet.length,
          )],
    ).join();
  } while (existing.contains(candidate));
  return candidate;
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
