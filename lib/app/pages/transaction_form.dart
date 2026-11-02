import 'dart:async';

import 'package:flutter/material.dart';

import '../amount_input_formatter.dart';
import '../error_dialog.dart';
import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';
import 'transaction_entry_layout.dart';
import 'transaction_form_selectors.dart';
import 'transaction_builder.dart';

export 'transaction_builder.dart';

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
    this.createTemplate = false,
    this.onSelected,
    this.onBack,
    this.onClose,
  });

  final bool createTemplate;
  final ValueChanged<AddTransactionChoice>? onSelected;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          TransactionEntryHeader(
            title: createTemplate ? 'Create Template' : 'New Transaction',
            onBack: onBack,
            onClose: onClose ?? () => Navigator.of(context).pop(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppPageSpacing.compactGutter,
              AppSpacing.sm,
              AppPageSpacing.compactGutter,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Transaction Type'),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final type in TransactionType.values)
                  ListTile(
                    leading: Icon(_typeIcon(type)),
                    title: Text(transactionTypeLabel(type)),
                    onTap: () {
                      final choice = AddTransactionChoice(type: type);
                      final select = onSelected;
                      if (select != null) {
                        select(choice);
                      } else {
                        Navigator.of(context).pop(choice);
                      }
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _TransactionFormSheetBuilder on _TransactionFormSheetState {
  Widget _buildTransactionFields(double fieldGap) {
    final template = widget.template;
    final descriptionOptions =
        template?.effectiveDescriptionOptions ??
        const <TemplateOption<String>>[];
    final dateOptions =
        template?.effectiveDateOptions ?? const <TemplateOption<DateTime>>[];
    final sourceAccounts =
        template?.effectiveSourceAccountOptions ??
        const <TemplateOption<String>>[];
    final destinationAccounts =
        template?.effectiveDestinationAccountOptions ??
        const <TemplateOption<String>>[];
    final categoryOptions =
        template?.effectiveCategoryOptions ?? const <TemplateOption<String>>[];
    final tagOptions =
        template?.effectiveTagOptions ?? const <TemplateOption<String>>[];
    final sourceAmounts = _sourceAmountOptionsForUse;
    final destinationAmounts = _amountOptions(template, source: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (template != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildTemplateSummary(template),
        ],
        if (_descriptionPatternError != null)
          Text(
            'This template cannot be used: $_descriptionPatternError. Fix it in Sheets.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (descriptionOptions.length > 1)
          _descriptionChoiceDropdown(descriptionOptions),
        if (descriptionOptions.isEmpty) ...[
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: _validateTransactionDescription,
          ),
          SizedBox(height: fieldGap),
        ],
        if (_descriptionPattern != null &&
            _descriptionPattern!.placeholders.isNotEmpty) ...[
          for (final placeholder in _descriptionPattern!.placeholders)
            Padding(
              padding: EdgeInsets.only(bottom: fieldGap),
              child: _descriptionPlaceholderField(placeholder),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text('Description: ${_descriptionPreview()}'),
            ),
          ),
        ],
        if (dateOptions.length > 1) _dateChoiceDropdown(dateOptions),
        if (dateOptions.isEmpty) ...[
          OutlinedButton.icon(
            key: _dateButtonKey,
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_date == null ? 'Select date' : _formatDate(_date!)),
          ),
          SizedBox(height: fieldGap),
        ],
        if (_sourceRequired && sourceAccounts.isEmpty) ...[
          _accountDropdown(
            label: _destinationRequired ? 'Source Account' : 'Account',
            value: _sourceAccountId,
            onChanged: (value) => _setState(() => _sourceAccountId = value),
          ),
          SizedBox(height: fieldGap),
        ],
        if (_sourceRequired && sourceAccounts.length > 1) ...[
          _accountChoiceDropdown(
            label: _destinationRequired ? 'Source Account' : 'Account',
            value: _sourceAccountId,
            options: sourceAccounts,
            onChanged: (value) => _setState(() => _sourceAccountId = value),
          ),
          SizedBox(height: fieldGap),
        ],
        if (_sourceRequired && !_sourceAmountIsFixed) ...[
          if (sourceAmounts.length > 1)
            _amountChoiceDropdown(
              controller: _sourceAmountController,
              options: sourceAmounts,
              label: _destinationRequired ? 'Source Amount' : 'Amount',
              accountId: _sourceAccountId,
            )
          else
            _amountField(
              controller: _sourceAmountController,
              label: _destinationRequired ? 'Source Amount' : 'Amount',
              accountId: _sourceAccountId,
            ),
          if (_destinationRequired) SizedBox(height: fieldGap),
        ],
        if (widget.type == TransactionType.transfer) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _sourceFeeEnabled,
            title: const Text('Source Account Fee'),
            onChanged: (value) =>
                _setState(() => _sourceFeeEnabled = value ?? false),
          ),
          if (_sourceFeeEnabled)
            _amountField(
              controller: _sourceFeeController,
              label: 'Source Fee',
              accountId: _sourceAccountId,
            ),
          SizedBox(height: fieldGap),
        ],
        if (_destinationRequired && destinationAccounts.isEmpty) ...[
          _accountDropdown(
            label: _sourceRequired ? 'Destination Account' : 'Account',
            value: _destinationAccountId,
            onChanged: (value) =>
                _setState(() => _destinationAccountId = value),
          ),
          SizedBox(height: fieldGap),
        ],
        if (_destinationRequired && destinationAccounts.length > 1) ...[
          _accountChoiceDropdown(
            label: _sourceRequired ? 'Destination Account' : 'Account',
            value: _destinationAccountId,
            options: destinationAccounts,
            onChanged: (value) =>
                _setState(() => _destinationAccountId = value),
          ),
          SizedBox(height: fieldGap),
        ],
        if (_destinationRequired && !_transferSameCurrency) ...[
          if (destinationAmounts.length > 1)
            _amountChoiceDropdown(
              controller: _destinationAmountController,
              options: destinationAmounts,
              label: _sourceRequired ? 'Destination Amount' : 'Amount',
              accountId: _destinationAccountId,
            )
          else if (destinationAmounts.isEmpty)
            _amountField(
              controller: _destinationAmountController,
              label: _sourceRequired ? 'Destination Amount' : 'Amount',
              accountId: _destinationAccountId,
            ),
        ],
        if (widget.type == TransactionType.transfer) ...[
          SizedBox(height: fieldGap),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _destinationFeeEnabled,
            title: const Text('Destination Account Fee'),
            onChanged: (value) =>
                _setState(() => _destinationFeeEnabled = value ?? false),
          ),
          if (_destinationFeeEnabled)
            _amountField(
              controller: _destinationFeeController,
              label: 'Destination Fee',
              accountId: _destinationAccountId,
            ),
        ],
        if (_categoryRequired || _availableCategories.isNotEmpty) ...[
          SizedBox(height: fieldGap),
          if (categoryOptions.length > 1)
            _categoryChoiceDropdown(categoryOptions)
          else if (categoryOptions.isEmpty)
            _categoryDropdown(),
        ],
        SizedBox(height: fieldGap),
        if (tagOptions.length > 1)
          _tagChoiceDropdown(tagOptions)
        else if (tagOptions.isEmpty)
          _tagDropdown(),
      ],
    );
  }

  Widget _descriptionChoiceDropdown(List<TemplateOption<String>> options) =>
      DropdownButtonFormField<String>(
        key: const ValueKey('template-description-options'),
        initialValue: _descriptionPattern == null
            ? null
            : _descriptionController.text,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Description'),
        validator: (value) => value == null ? 'Choose a description.' : null,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.value, child: Text(option.value)),
        ],
        onChanged: (value) {
          if (value == null) return;
          _setState(() {
            _descriptionController.text = value;
            _setDescriptionPattern(value);
          });
        },
      );

  Widget _accountChoiceDropdown({
    required String label,
    required String? value,
    required List<TemplateOption<String>> options,
    required ValueChanged<String?> onChanged,
  }) {
    final accounts = widget.data.entryFormAccounts
        .where((account) => options.any((option) => option.value == account.id))
        .toList();
    return DropdownButtonFormField<String>(
      key: ValueKey('template-account-options-$label'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      validator: (value) => value == null ? 'Choose an account.' : null,
      items: [
        for (final account in accounts)
          DropdownMenuItem(
            value: account.id,
            child: Text('${account.name} · ${account.currencyId}'),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _descriptionPlaceholderField(String placeholder) {
    final options = _placeholderOptions[placeholder] ?? const [];
    if (options.length > 1) {
      return DropdownButtonFormField<String>(
        key: ValueKey('placeholder-options-$placeholder'),
        initialValue: _selectedPlaceholderOptions[placeholder],
        isExpanded: true,
        decoration: InputDecoration(labelText: placeholder),
        validator: (value) => value == null ? 'Choose $placeholder.' : null,
        items: [
          for (final option in options)
            DropdownMenuItem(value: option.value, child: Text(option.value)),
        ],
        onChanged: (value) => _setState(() {
          _selectedPlaceholderOptions[placeholder] = value;
        }),
      );
    }
    if (options.length == 1) return const SizedBox.shrink();
    return TextFormField(
      controller: _placeholderControllers[placeholder],
      decoration: InputDecoration(labelText: placeholder),
      textCapitalization: TextCapitalization.sentences,
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'Enter $placeholder.';
        return validateTemplateEntryText(value);
      },
      onChanged: (_) => _setState(() {}),
    );
  }

  Widget _dateChoiceDropdown(List<TemplateOption<DateTime>> options) =>
      DropdownButtonFormField<DateTime>(
        key: const ValueKey('template-date-options'),
        initialValue: _date,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Date'),
        validator: (value) => value == null ? 'Choose a date.' : null,
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option.value,
              child: Text(_formatDate(option.value)),
            ),
        ],
        onChanged: (value) => _setState(() => _date = value),
      );

  Widget _amountChoiceDropdown({
    required TextEditingController controller,
    required List<TemplateOption<String>> options,
    required String label,
    required String? accountId,
  }) {
    final account = accountId == null
        ? null
        : widget.data.accountsById[accountId];
    final currency = account == null
        ? null
        : widget.data.currenciesById[account.currencyId];
    return DropdownButtonFormField<String>(
      key: ValueKey('template-amount-options-$label'),
      initialValue: controller.text.isEmpty ? null : controller.text,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixText: currency == null ? null : '${currency.symbol} ',
      ),
      validator: (value) => value == null ? 'Choose an amount.' : null,
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option.value,
            child: Text(
              currency == null
                  ? option.value
                  : formatMoney(
                      Money.fromMajorUnits(
                        value: option.value,
                        currency: currency,
                      ),
                      widget.data.currenciesById,
                    ),
            ),
          ),
      ],
      onChanged: (value) => _setState(() => controller.text = value ?? ''),
    );
  }

  Widget _categoryChoiceDropdown(List<TemplateOption<String>> options) =>
      DropdownButtonFormField<String>(
        key: const ValueKey('template-category-options'),
        initialValue: _categoryId,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _categoryRequired ? 'Category' : 'Category (optional)',
        ),
        validator: (value) => value == null ? 'Choose a category.' : null,
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option.value,
              child: Text(
                widget.data.categoriesById[option.value]?.name ?? option.value,
              ),
            ),
        ],
        onChanged: (value) => _setState(() => _categoryId = value),
      );

  Widget _tagChoiceDropdown(List<TemplateOption<String>> options) =>
      DropdownButtonFormField<String>(
        key: const ValueKey('template-tag-options'),
        initialValue: _tagId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tag'),
        validator: (value) => value == null ? 'Choose a tag.' : null,
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option.value,
              child: Text(
                widget.data.tagsById[option.value]?.name ?? option.value,
              ),
            ),
        ],
        onChanged: (value) => _setState(() => _tagId = value),
      );

  Widget _buildTemplateBuilder(double fieldGap) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        controller: _templateNameController,
        decoration: const InputDecoration(labelText: 'Template Name'),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter a template name.'
            : null,
      ),
      SizedBox(height: fieldGap),
      Text(
        'Add one or more saved choices for each field. Leave a field empty to enter it when using the template.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      SizedBox(height: fieldGap),
      for (final field in _templateFields)
        _buildTemplateFieldSection(field, fieldGap),
      if (_templateBuilderError != null) ...[
        SizedBox(height: fieldGap),
        Text(
          _templateBuilderError!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ],
  );

  Widget _buildTemplateFieldSection(_TemplateField field, double fieldGap) {
    final options = _templateOptionDrafts[field]!;
    final label = _templateFieldLabel(field);
    return Padding(
      padding: EdgeInsets.only(bottom: fieldGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Add $label option',
                onPressed: () => _setState(() {
                  options.add(_TemplateOptionDraft());
                  _templateBuilderError = null;
                }),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          for (var index = 0; index < options.length; index++)
            _buildTemplateOption(field, options[index], index, options.length),
        ],
      ),
    );
  }

  Widget _buildTemplateOption(
    _TemplateField field,
    _TemplateOptionDraft option,
    int index,
    int optionCount,
  ) {
    final label = _templateFieldLabel(field);
    final control = switch (field) {
      _TemplateField.date => FormField<DateTime>(
        key: ValueKey('template-builder-date-$index-${option.hashCode}'),
        initialValue: option.date,
        validator: (value) => value == null ? 'Select a date.' : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final selected = await _pickTemplateDate(option.date);
                if (selected == null) return;
                option.date = selected;
                state.didChange(selected);
                _setState(() => _templateBuilderError = null);
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(
                option.date == null ? 'Select date' : _formatDate(option.date!),
              ),
            ),
            if (state.errorText != null)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      _TemplateField.description => TextFormField(
        key: ValueKey('template-description-option-$index'),
        controller: option.controller,
        decoration: InputDecoration(
          labelText: 'Description option ${index + 1}',
          hintText: 'Coffee at {Merchant}',
          helperText: 'Use {Name} for each value you want to fill or choose.',
        ),
        textCapitalization: TextCapitalization.sentences,
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Enter a description option.';
          }
          return _validateDescriptionPattern(value);
        },
        onChanged: (_) => _setState(() {
          _templateBuilderError = null;
          _syncDescriptionPlaceholders(option);
        }),
      ),
      _TemplateField.sourceAccount ||
      _TemplateField.destinationAccount => TransactionAccountSelector(
        label: '$label option ${index + 1}',
        value: option.selection,
        accounts: widget.data.entryFormAccounts,
        data: widget.data,
        requiredSelection: true,
        onChanged: (value) => _setState(() {
          option.selection = value;
          _templateBuilderError = null;
        }),
      ),
      _TemplateField.sourceAmount ||
      _TemplateField.destinationAmount => TextFormField(
        controller: option.controller,
        decoration: InputDecoration(
          labelText: '$label option ${index + 1}',
          prefixText: _templateAmountCurrency(field) == null
              ? null
              : '${_templateAmountCurrency(field)!.symbol} ',
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [ThousandsSeparatorInputFormatter()],
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Enter an amount.';
          }
          final amount = num.tryParse(value.trim().replaceAll(',', ''));
          if (amount == null || !amount.isFinite || amount < 0) {
            return 'Enter a valid amount.';
          }
          return null;
        },
        onChanged: (_) => _setState(() => _templateBuilderError = null),
      ),
      _TemplateField.category => TransactionCategorySelector(
        label: 'Category option ${index + 1}',
        value: option.selection,
        categories: _availableCategories,
        requiredSelection: true,
        onChanged: (value) => _setState(() {
          option.selection = value;
          _templateBuilderError = null;
        }),
      ),
      _TemplateField.tag => DropdownButtonFormField<String>(
        key: ValueKey('template-builder-tag-$index-${option.hashCode}'),
        initialValue: option.selection,
        isExpanded: true,
        decoration: InputDecoration(labelText: 'Tag option ${index + 1}'),
        validator: (value) => value == null ? 'Select a tag.' : null,
        items: [
          for (final tag in widget.data.entryFormTags)
            DropdownMenuItem(value: tag.id, child: Text(tag.name)),
        ],
        onChanged: (value) => _setState(() {
          option.selection = value;
          _templateBuilderError = null;
        }),
      ),
    };
    return Card(
      key: ValueKey('template-option-${field.name}-${option.hashCode}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            control,
            Row(
              children: [
                if (optionCount > 1)
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Default'),
                      value: option.isDefault,
                      onChanged: (value) => _setState(() {
                        for (final item in _templateOptionDrafts[field]!) {
                          item.isDefault = false;
                        }
                        option.isDefault = value ?? false;
                        _templateBuilderError = null;
                      }),
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  tooltip: 'Remove $label option ${index + 1}',
                  onPressed: () => _setState(() {
                    _templateOptionDrafts[field]!.remove(option);
                    option.dispose();
                    _templateBuilderError = null;
                  }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (field == _TemplateField.description)
              for (final placeholder in _descriptionPlaceholders(option))
                _buildPlaceholderOptionSection(option, placeholder, index),
          ],
        ),
      ),
    );
  }

  List<String> _descriptionPlaceholders(_TemplateOptionDraft option) {
    try {
      final pattern = TransactionDescriptionPattern.parse(
        option.controller.text.trim(),
      );
      if (pattern.placeholderOptions.values.any(
        (values) => values.isNotEmpty,
      )) {
        return const [];
      }
      return pattern.placeholders;
    } on FormatException {
      return const [];
    }
  }

  void _syncDescriptionPlaceholders(_TemplateOptionDraft option) {
    try {
      final pattern = TransactionDescriptionPattern.parse(
        option.controller.text.trim(),
      );
      if (pattern.placeholderOptions.values.any(
        (values) => values.isNotEmpty,
      )) {
        return;
      }
      final names = pattern.placeholders.toSet();
      for (final oldName in option.placeholderOptions.keys.toList()) {
        if (names.contains(oldName)) continue;
        for (final draft in option.placeholderOptions.remove(oldName)!) {
          draft.dispose();
        }
      }
      for (final name in names) {
        option.placeholderOptions.putIfAbsent(name, () => []);
      }
    } on FormatException {
      // Keep the last valid placeholder controls while the pattern is edited.
    }
  }

  Widget _buildPlaceholderOptionSection(
    _TemplateOptionDraft description,
    String placeholder,
    int descriptionIndex,
  ) {
    final options = description.placeholderOptions[placeholder]!;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md, top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(placeholder)),
              IconButton(
                tooltip:
                    'Add $placeholder option for description ${descriptionIndex + 1}',
                onPressed: () => _setState(() {
                  options.add(_TemplateOptionDraft());
                  _templateBuilderError = null;
                }),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          for (var index = 0; index < options.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey(
                        'description-$descriptionIndex-placeholder-$placeholder-option-$index',
                      ),
                      controller: options[index].controller,
                      decoration: InputDecoration(
                        labelText: '$placeholder option ${index + 1}',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter a $placeholder option.';
                        }
                        return validateTemplateEntryText(value);
                      },
                      onChanged: (_) =>
                          _setState(() => _templateBuilderError = null),
                    ),
                  ),
                  if (options.length > 1)
                    _placeholderDefaultControl(options, index),
                  IconButton(
                    tooltip: 'Remove $placeholder option ${index + 1}',
                    onPressed: () => _setState(() {
                      final removed = options.removeAt(index);
                      removed.dispose();
                      _templateBuilderError = null;
                    }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholderDefaultControl(
    List<_TemplateOptionDraft> options,
    int index,
  ) {
    void updateDefault(bool? value) => _setState(() {
      for (final item in options) {
        item.isDefault = false;
      }
      options[index].isDefault = value ?? false;
      _templateBuilderError = null;
    });

    return InkWell(
      onTap: () => updateDefault(!options[index].isDefault),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: options[index].isDefault,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: updateDefault,
          ),
          const Text('Default', maxLines: 1, softWrap: false),
        ],
      ),
    );
  }

  CurrencyDefinition? _templateAmountCurrency(_TemplateField field) {
    final accountId = field == _TemplateField.sourceAmount
        ? defaultOrOnlyTemplateOption(
            _templateOptionDrafts[_TemplateField.sourceAccount]!
                .where((option) => option.selection != null)
                .map((option) => TemplateOption(value: option.selection!)),
          )
        : defaultOrOnlyTemplateOption(
            _templateOptionDrafts[_TemplateField.destinationAccount]!
                .where((option) => option.selection != null)
                .map((option) => TemplateOption(value: option.selection!)),
          );
    if (accountId == null) return null;
    final account = widget.data.accountsById[accountId];
    return account == null
        ? null
        : widget.data.currenciesById[account.currencyId];
  }

  String _templateFieldLabel(_TemplateField field) => switch (field) {
    _TemplateField.date => 'Date',
    _TemplateField.description => 'Description',
    _TemplateField.sourceAccount =>
      _destinationRequired ? 'Source Account' : 'Account',
    _TemplateField.sourceAmount =>
      _destinationRequired ? 'Source Amount' : 'Amount',
    _TemplateField.destinationAccount =>
      _sourceRequired ? 'Destination Account' : 'Account',
    _TemplateField.destinationAmount =>
      _sourceRequired ? 'Destination Amount' : 'Amount',
    _TemplateField.category =>
      _categoryRequired ? 'Category' : 'Category (optional)',
    _TemplateField.tag => 'Tag',
  };

  String? _draftValue(_TemplateField field, _TemplateOptionDraft option) =>
      switch (field) {
        _TemplateField.date =>
          option.date == null ? null : _formatDate(option.date!),
        _TemplateField.description => option.controller.text.trim(),
        _TemplateField.sourceAccount ||
        _TemplateField.destinationAccount ||
        _TemplateField.category ||
        _TemplateField.tag => option.selection,
        _TemplateField.sourceAmount || _TemplateField.destinationAmount =>
          option.controller.text.trim().replaceAll(',', ''),
      };

  String? _validateTemplateOptionDrafts() {
    for (final field in _templateFields) {
      final options = _templateOptionDrafts[field]!;
      final values = <String>[];
      for (final option in options) {
        final value = _draftValue(field, option);
        if (value == null || value.isEmpty) {
          return 'Complete every ${_templateFieldLabel(field).toLowerCase()} option.';
        }
        if (field == _TemplateField.description) {
          try {
            final pattern = TransactionDescriptionPattern.parse(value);
            if (pattern.placeholderOptions.values.any(
              (placeholderOptions) => placeholderOptions.isNotEmpty,
            )) {
              return 'Enter placeholder names as {Name}; add their choices below the description.';
            }
            for (final placeholder in pattern.placeholders) {
              final placeholderOptions =
                  option.placeholderOptions[placeholder] ?? const [];
              final placeholderValues = <String>[];
              for (final placeholderOption in placeholderOptions) {
                final placeholderValue = placeholderOption.controller.text
                    .trim();
                if (placeholderValue.isEmpty) {
                  return 'Complete every $placeholder option.';
                }
                final reservedError = validateTemplateEntryText(
                  placeholderValue,
                );
                if (reservedError != null) return reservedError;
                placeholderValues.add(placeholderValue);
              }
              if (placeholderValues.toSet().length !=
                  placeholderValues.length) {
                return '$placeholder options must be unique.';
              }
              if (placeholderOptions
                      .where((choice) => choice.isDefault)
                      .length >
                  1) {
                return 'Choose at most one default $placeholder option.';
              }
            }
          } on FormatException catch (error) {
            return error.message;
          }
        } else {
          final reservedError = validateTemplateEntryText(value);
          if (reservedError != null) return reservedError;
        }
        if (field == _TemplateField.sourceAmount ||
            field == _TemplateField.destinationAmount) {
          final numericValue = num.tryParse(value);
          if (numericValue == null ||
              !numericValue.isFinite ||
              numericValue < 0) {
            return 'Enter a valid ${_templateFieldLabel(field).toLowerCase()} option.';
          }
        }
        values.add(value);
      }
      if (values.toSet().length != values.length) {
        return '${_templateFieldLabel(field)} options must be unique.';
      }
      if (options.where((option) => option.isDefault).length > 1) {
        return 'Choose at most one default ${_templateFieldLabel(field).toLowerCase()}.';
      }
    }

    for (final pair in [
      (_TemplateField.sourceAccount, _TemplateField.sourceAmount),
      (_TemplateField.destinationAccount, _TemplateField.destinationAmount),
    ]) {
      final accounts = (_templateOptionDrafts[pair.$1] ?? const [])
          .map((option) => option.selection)
          .whereType<String>();
      final amounts = (_templateOptionDrafts[pair.$2] ?? const [])
          .map((option) => _draftValue(pair.$2, option))
          .whereType<String>();
      for (final accountId in accounts) {
        final account = widget.data.accountsById[accountId];
        if (account == null) continue;
        final currency = widget.data.currenciesById[account.currencyId]!;
        for (final amount in amounts) {
          try {
            Money.fromMajorUnits(value: amount, currency: currency);
          } on FormatException {
            return 'An amount option is not valid in ${currency.id}.';
          }
        }
      }
    }
    return null;
  }

  TransactionTemplate _buildTemplateFromDrafts() {
    List<TemplateOption<T>> values<T>(
      _TemplateField field,
      T? Function(_TemplateOptionDraft option) valueOf,
    ) {
      final result = <TemplateOption<T>>[];
      for (final option
          in _templateOptionDrafts[field] ?? const <_TemplateOptionDraft>[]) {
        final value = valueOf(option);
        if (value == null) {
          throw StateError('Template option was not validated before saving.');
        }
        result.add(TemplateOption(value: value, isDefault: option.isDefault));
      }
      return result;
    }

    final dates = values<DateTime>(
      _TemplateField.date,
      (option) => option.date,
    );
    final descriptions = values<String>(
      _TemplateField.description,
      _encodeDescriptionDraft,
    );
    final sourceAccounts = values<String>(
      _TemplateField.sourceAccount,
      (option) => option.selection,
    );
    final sourceAmounts = values<String>(
      _TemplateField.sourceAmount,
      (option) => option.controller.text.trim().replaceAll(',', ''),
    );
    final destinationAccounts = values<String>(
      _TemplateField.destinationAccount,
      (option) => option.selection,
    );
    final destinationAmounts = values<String>(
      _TemplateField.destinationAmount,
      (option) => option.controller.text.trim().replaceAll(',', ''),
    );
    final categories = values<String>(
      _TemplateField.category,
      (option) => option.selection,
    );
    final tags = values<String>(
      _TemplateField.tag,
      (option) => option.selection,
    );
    final sourceAccountId = defaultOrOnlyTemplateOption(sourceAccounts);
    final destinationAccountId = defaultOrOnlyTemplateOption(
      destinationAccounts,
    );
    Money? amountFor(List<TemplateOption<String>> choices, String? accountId) {
      final amount = defaultOrOnlyTemplateOption(choices);
      if (amount == null || accountId == null) return null;
      final account = widget.data.accountsById[accountId];
      if (account == null) return null;
      return Money.fromMajorUnits(
        value: amount,
        currency: widget.data.currenciesById[account.currencyId]!,
      );
    }

    final now = DateTime.now().toUtc();
    return TransactionTemplate(
      id: generateTransactionId(widget.data.transactionTemplatesById.keys),
      name: _templateNameController.text.trim(),
      type: widget.type,
      date: defaultOrOnlyTemplateOption(dates),
      dateOptions: dates,
      description: defaultOrOnlyTemplateOption(descriptions),
      descriptionOptions: descriptions,
      categoryId: defaultOrOnlyTemplateOption(categories),
      categoryOptions: categories,
      tagId: defaultOrOnlyTemplateOption(tags),
      tagOptions: tags,
      sourceAccountId: sourceAccountId,
      sourceAccountOptions: sourceAccounts,
      sourceAmount: amountFor(sourceAmounts, sourceAccountId),
      sourceAmountOptions: sourceAmounts,
      destinationAccountId: destinationAccountId,
      destinationAccountOptions: destinationAccounts,
      destinationAmount: amountFor(destinationAmounts, destinationAccountId),
      destinationAmountOptions: destinationAmounts,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  String _encodeDescriptionDraft(_TemplateOptionDraft option) {
    final source = option.controller.text.trim();
    final pattern = TransactionDescriptionPattern.parse(source);
    return TransactionDescriptionPattern.encodePlaceholderOptions(source, {
      for (final name in pattern.placeholders)
        if (option.placeholderOptions[name]?.isNotEmpty == true)
          name: [
            for (final choice in option.placeholderOptions[name]!)
              TemplateOption(
                value: choice.controller.text.trim(),
                isDefault: choice.isDefault,
              ),
          ],
    });
  }

  Future<DateTime?> _pickTemplateDate(DateTime? initialDate) => showDatePicker(
    context: context,
    initialDate: initialDate ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
}

class TransactionTemplateBrowser extends StatefulWidget {
  const TransactionTemplateBrowser({
    super.key,
    required this.data,
    required this.onTemplateUpdated,
    this.allowTemplateManagement = true,
    this.onChoice,
    this.onClose,
  });

  final AppDataSnapshot data;
  final Future<void> Function(TransactionTemplate template) onTemplateUpdated;
  final bool allowTemplateManagement;
  final ValueChanged<AddTransactionChoice>? onChoice;
  final VoidCallback? onClose;

  @override
  State<TransactionTemplateBrowser> createState() =>
      _TransactionTemplateBrowserState();
}

class _TransactionTemplateBrowserState
    extends State<TransactionTemplateBrowser> {
  final _searchController = TextEditingController();
  late final List<TransactionTemplate> _templates = [
    ...widget.data.transactionTemplates,
  ];
  bool _updatingFavorite = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final groups = <TransactionType, List<TransactionTemplate>>{};
    for (final type in TransactionType.values) {
      final matches = _templates.where((template) {
        if (template.type != type) return false;
        final categoryNames = template.effectiveCategoryOptions.isEmpty
            ? ['No category']
            : [
                for (final option in template.effectiveCategoryOptions)
                  widget.data.categoriesById[option.value]?.name ??
                      'Unknown category',
              ];
        return query.isEmpty ||
            template.name.toLowerCase().contains(query) ||
            categoryNames.any((name) => name.toLowerCase().contains(query)) ||
            transactionTypeLabel(type).toLowerCase().contains(query);
      }).toList();
      final favorites = matches.where((template) => template.isFavorite);
      final regular = matches.where((template) => !template.isFavorite).toList()
        ..sort((a, b) {
          final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return byName == 0 ? a.id.compareTo(b.id) : byName;
        });
      groups[type] = [...favorites, ...regular];
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < AppBreakpoints.compact;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              compact
                  ? AppPageSpacing.compactGutter
                  : AppPageSpacing.desktopGutter,
              AppSpacing.sm,
              compact
                  ? AppPageSpacing.compactGutter
                  : AppPageSpacing.desktopGutter,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TransactionEntryHeader(
                  title: 'Add Transaction',
                  onClose: widget.onClose ?? () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search templates',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => _choose(const AddTransactionChoice()),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('New Transaction'),
                ),
                if (widget.allowTemplateManagement) ...[
                  const SizedBox(height: AppSpacing.xs),
                  if (compact)
                    TextButton.icon(
                      onPressed: () => _choose(
                        const AddTransactionChoice(createTemplate: true),
                      ),
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('Create Template'),
                    )
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _choose(
                          const AddTransactionChoice(createTemplate: true),
                        ),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Create Template'),
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: ListView(
                    key: const PageStorageKey<String>('transaction-templates'),
                    children: [
                      for (final type in TransactionType.values)
                        if (groups[type]!.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.xs,
                              AppSpacing.md,
                              AppSpacing.xs,
                              AppSpacing.xs,
                            ),
                            child: Text(
                              transactionTypeLabel(type).toUpperCase(),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: AppColors.mutedText),
                            ),
                          ),
                          for (final template in groups[type]!)
                            _templateTile(template),
                        ],
                      if (groups.values.every((items) => items.isEmpty))
                        Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            query.isEmpty
                                ? widget.allowTemplateManagement
                                      ? 'No templates yet. Use Create Template to create one.'
                                      : 'No templates are available yet.'
                                : 'No templates match “${_searchController.text.trim()}”.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _templateTile(TransactionTemplate template) {
    final categoryOptions = template.effectiveCategoryOptions;
    final category = categoryOptions.isEmpty
        ? 'No category'
        : categoryOptions.length > 1
        ? '${categoryOptions.length} categories'
        : widget.data.categoriesById[categoryOptions.single.value]?.name ??
              'Unknown category';
    final unavailableReason = _templateUnavailableReason(template);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.control),
        side: const BorderSide(color: AppColors.border),
      ),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        onTap: unavailableReason == null
            ? () => _choose(AddTransactionChoice(template: template))
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.name),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      category,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.mutedText),
                    ),
                    if (unavailableReason != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Unavailable: $unavailableReason',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: template.isFavorite
                    ? 'Remove favorite: ${template.name}'
                    : 'Add favorite: ${template.name}',
                onPressed: !widget.allowTemplateManagement || _updatingFavorite
                    ? null
                    : () => _toggleFavorite(template),
                icon: Icon(
                  template.isFavorite ? Icons.star : Icons.star_outline,
                  color: template.isFavorite ? AppColors.warning : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _choose(AddTransactionChoice choice) {
    final onChoice = widget.onChoice;
    if (onChoice != null) {
      onChoice(choice);
    } else {
      Navigator.of(context).pop(choice);
    }
  }

  String? _templateUnavailableReason(TransactionTemplate template) {
    for (final option in template.effectiveDescriptionOptions) {
      try {
        TransactionDescriptionPattern.parse(option.value);
      } on FormatException catch (error) {
        return error.message;
      }
    }
    for (final option in template.effectiveCategoryOptions) {
      final category = widget.data.categoriesById[option.value];
      if (category == null ||
          !category.allowedTransactionTypes.contains(template.type)) {
        return 'category is missing or incompatible';
      }
    }
    for (final option in template.effectiveTagOptions) {
      if (!widget.data.tagsById.containsKey(option.value)) {
        return 'tag is missing';
      }
    }
    for (final option in [
      ...template.effectiveSourceAccountOptions,
      ...template.effectiveDestinationAccountOptions,
    ]) {
      if (!widget.data.accountsById.containsKey(option.value) ||
          !widget.data.entryFormAccounts.any(
            (account) => account.id == option.value,
          )) {
        return 'account ${option.value} is missing or unavailable';
      }
    }
    for (final pair in [
      (
        template.effectiveSourceAmountOptions(widget.data.currenciesById),
        template.effectiveSourceAccountOptions,
      ),
      (
        template.effectiveDestinationAmountOptions(widget.data.currenciesById),
        template.effectiveDestinationAccountOptions,
      ),
    ]) {
      for (final amountOption in pair.$1) {
        final numericValue = num.tryParse(amountOption.value);
        if (numericValue == null ||
            !numericValue.isFinite ||
            numericValue < 0) {
          return 'amount option is invalid';
        }
        for (final accountOption in pair.$2) {
          final account = widget.data.accountsById[accountOption.value];
          if (account == null) continue;
          try {
            Money.fromMajorUnits(
              value: amountOption.value,
              currency: widget.data.currenciesById[account.currencyId]!,
            );
          } on FormatException {
            return 'amount option is invalid for ${account.currencyId}';
          }
        }
      }
    }
    if (template.type == TransactionType.transfer &&
        template.effectiveSourceAccountOptions.length == 1 &&
        template.effectiveDestinationAccountOptions.length == 1 &&
        template.sourceAmountOptions.isEmpty &&
        template.destinationAmountOptions.isEmpty &&
        template.sourceAmount != null &&
        template.destinationAmount != null) {
      final sourceCurrency = widget
          .data
          .accountsById[template.effectiveSourceAccountOptions.single.value]!
          .currencyId;
      final destinationCurrency = widget
          .data
          .accountsById[template
              .effectiveDestinationAccountOptions
              .single
              .value]!
          .currencyId;
      if (sourceCurrency == destinationCurrency &&
          template.sourceAmount!.minorUnits !=
              template.destinationAmount!.minorUnits) {
        return 'same-currency transfer amounts differ';
      }
    }
    return null;
  }

  Future<void> _toggleFavorite(TransactionTemplate template) async {
    final updated = template.copyWith(isFavorite: !template.isFavorite);
    final index = _templates.indexWhere((item) => item.id == template.id);
    if (index < 0) return;
    setState(() {
      _updatingFavorite = true;
      _templates[index] = updated;
    });
    try {
      await widget.onTemplateUpdated(updated);
    } catch (error) {
      if (!mounted) return;
      setState(() => _templates[index] = template);
      showPersistentErrorDialog(context, 'Could not update favorite: $error');
    } finally {
      if (mounted) setState(() => _updatingFavorite = false);
    }
  }
}

/// Keeps template selection, type selection, and transaction entry in one
/// route so quick successive dialog pops/pushes cannot dismiss the next step.
class TransactionEntryFlowDialog extends StatefulWidget {
  const TransactionEntryFlowDialog({
    super.key,
    required this.data,
    required this.onTemplateUpdated,
    this.allowTemplateManagement = true,
  });

  final AppDataSnapshot data;
  final Future<void> Function(TransactionTemplate template) onTemplateUpdated;
  final bool allowTemplateManagement;

  @override
  State<TransactionEntryFlowDialog> createState() =>
      _TransactionEntryFlowDialogState();
}

class _TransactionEntryFlowDialogState
    extends State<TransactionEntryFlowDialog> {
  AddTransactionChoice? _choice;
  TransactionType? _type;
  final _formKey = GlobalKey<_TransactionFormSheetState>();
  bool _allowPop = false;

  @override
  Widget build(BuildContext context) {
    final choice = _choice;
    final type = _type;
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleSystemBack());
      },
      child: Material(
        key: const ValueKey('transaction-entry-flow-content'),
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: SizedBox.expand(
            child: IndexedStack(
              index: choice == null
                  ? 0
                  : type == null
                  ? 1
                  : 2,
              children: [
                TransactionTemplateBrowser(
                  data: widget.data,
                  onTemplateUpdated: widget.onTemplateUpdated,
                  allowTemplateManagement: widget.allowTemplateManagement,
                  onClose: () => unawaited(_closeFlow()),
                  onChoice: (selected) => setState(() {
                    _choice = selected;
                    _type = selected.template?.type;
                  }),
                ),
                TransactionTypeChooser(
                  createTemplate: choice?.createTemplate ?? false,
                  onSelected: (selected) =>
                      setState(() => _type = selected.type),
                  onBack: _returnToTemplates,
                  onClose: () => unawaited(_closeFlow()),
                ),
                if (choice != null && type != null)
                  TransactionFormSheet(
                    key: _formKey,
                    type: type,
                    data: widget.data,
                    template: choice.template,
                    createTemplate: choice.createTemplate,
                    onBack: () => unawaited(_returnFromForm()),
                    onClose: () => unawaited(_closeFlow()),
                    onResult: _complete,
                  )
                else
                  const SizedBox.expand(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _returnToTemplates() {
    setState(() {
      _choice = null;
      _type = null;
    });
  }

  Future<void> _returnFromForm() async {
    if (_formKey.currentState?.hasUnsavedChanges == true &&
        !await _confirmDiscard()) {
      return;
    }
    if (!mounted) return;
    setState(() {
      if (_choice?.template != null) _choice = null;
      _type = null;
    });
  }

  Future<void> _handleSystemBack() async {
    if (_type != null) {
      await _returnFromForm();
    } else if (_choice != null) {
      _returnToTemplates();
    } else {
      await _closeFlow();
    }
  }

  Future<void> _closeFlow() async {
    if (_formKey.currentState?.hasUnsavedChanges == true &&
        !await _confirmDiscard()) {
      return;
    }
    if (mounted) _allowPopAndReturn();
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('Discard changes?'),
          content: const Text('Your transaction has not been added.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ??
      false;

  void _complete(Object result) => _allowPopAndReturn(result);

  void _allowPopAndReturn([Object? result]) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }
}

class TransactionFormSheet extends StatefulWidget {
  const TransactionFormSheet({
    super.key,
    required this.type,
    required this.data,
    this.template,
    this.createTemplate = false,
    this.onBack,
    this.onClose,
    this.onResult,
  });

  final TransactionType type;
  final AppDataSnapshot data;
  final TransactionTemplate? template;
  final bool createTemplate;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final ValueChanged<Object>? onResult;

  @override
  State<TransactionFormSheet> createState() => _TransactionFormSheetState();
}

enum _TemplateField {
  date,
  description,
  sourceAccount,
  sourceAmount,
  destinationAccount,
  destinationAmount,
  category,
  tag,
}

class _TemplateOptionDraft {
  final TextEditingController controller = TextEditingController();
  final Map<String, List<_TemplateOptionDraft>> placeholderOptions = {};
  String? selection;
  DateTime? date;
  bool isDefault = false;

  void dispose() {
    controller.dispose();
    for (final options in placeholderOptions.values) {
      for (final option in options) {
        option.dispose();
      }
    }
  }
}

class _TransactionFormSheetState extends State<TransactionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _dateButtonKey = GlobalKey();
  final _sourceAmountController = TextEditingController();
  final _destinationAmountController = TextEditingController();
  final _sourceFeeController = TextEditingController();
  final _destinationFeeController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _sourceFeeEnabled = false;
  bool _destinationFeeEnabled = false;
  final _templateNameController = TextEditingController();
  final Map<String, TextEditingController> _placeholderControllers = {};
  final Map<String, List<TemplateOption<String>>> _placeholderOptions = {};
  final Map<String, String?> _selectedPlaceholderOptions = {};
  final Map<_TemplateField, List<_TemplateOptionDraft>> _templateOptionDrafts =
      {};

  DateTime? _date;
  String? _sourceAccountId;
  String? _destinationAccountId;
  String? _categoryId;
  String? _tagId;
  TransactionDescriptionPattern? _descriptionPattern;
  String? _descriptionPatternError;
  String? _templateBuilderError;
  late String _initialDraftFingerprint;
  bool _resultSubmitted = false;

  void _setState(VoidCallback callback) => setState(callback);

  bool get hasUnsavedChanges => _draftFingerprint() != _initialDraftFingerprint;

  bool get _sourceRequired => transactionTypeRules[widget.type]!.sourceRequired;
  bool get _destinationRequired =>
      transactionTypeRules[widget.type]!.destinationRequired;
  bool get _categoryRequired =>
      transactionTypeRules[widget.type]!.categoryRequired;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    if (widget.createTemplate) {
      for (final field in _templateFields) {
        _templateOptionDrafts[field] = [];
      }
    }
    _date =
        _selectedTemplateValue(template?.effectiveDateOptions) ??
        (widget.createTemplate ? null : DateTime.now());
    _sourceAccountId = _selectedTemplateValue(
      template?.effectiveSourceAccountOptions,
    );
    _destinationAccountId = _selectedTemplateValue(
      template?.effectiveDestinationAccountOptions,
    );
    _categoryId = _selectedTemplateValue(template?.effectiveCategoryOptions);
    _tagId = _selectedTemplateValue(template?.effectiveTagOptions);
    final descriptionOptions =
        template?.effectiveDescriptionOptions ?? const [];
    final selectedDescription = _selectedTemplateValue(descriptionOptions);
    _descriptionController.text = selectedDescription ?? '';
    if (selectedDescription != null && selectedDescription.isNotEmpty) {
      _setDescriptionPattern(selectedDescription);
    }
    final sourceAmountOptions = _amountOptions(template, source: true);
    final destinationAmountOptions = _amountOptions(template, source: false);
    final sourceValue = _selectedTemplateValue(sourceAmountOptions);
    final destinationValue = _selectedTemplateValue(destinationAmountOptions);
    _sourceAmountController.text =
        sourceValue ?? (_transferSameCurrency ? destinationValue : null) ?? '';
    _destinationAmountController.text = destinationValue ?? '';
    if (_sourceAmountController.text.isEmpty &&
        template?.sourceAmount != null) {
      _sourceAmountController.text = _legacyAmountValue(
        template!.sourceAmount!,
      );
    }
    if (_destinationAmountController.text.isEmpty &&
        template?.destinationAmount != null) {
      _destinationAmountController.text = _legacyAmountValue(
        template!.destinationAmount!,
      );
    }
    _initialDraftFingerprint = _draftFingerprint();
  }

  String _draftFingerprint() => [
    _date?.toIso8601String() ?? '',
    _sourceAccountId ?? '',
    _destinationAccountId ?? '',
    _categoryId ?? '',
    _tagId ?? '',
    _sourceAmountController.text,
    _destinationAmountController.text,
    _sourceFeeController.text,
    _destinationFeeController.text,
    _sourceFeeEnabled.toString(),
    _destinationFeeEnabled.toString(),
    _descriptionController.text,
    _templateNameController.text,
    for (final field in _TemplateField.values)
      for (final option in _templateOptionDrafts[field] ?? const [])
        '${field.name}:${option.date?.toIso8601String() ?? ''}:'
            '${option.selection ?? ''}:${option.controller.text}:${option.isDefault}:',
    for (final field in _TemplateField.values)
      for (final option in _templateOptionDrafts[field] ?? const [])
        for (final entry in option.placeholderOptions.entries)
          for (final placeholderOption in entry.value)
            '${field.name}:${entry.key}=${placeholderOption.controller.text}:${placeholderOption.isDefault}',
    for (final placeholder in _placeholderControllers.keys.toList()..sort())
      '$placeholder=${_placeholderControllers[placeholder]!.text}',
    for (final placeholder in _selectedPlaceholderOptions.keys.toList()..sort())
      '$placeholder=${_selectedPlaceholderOptions[placeholder] ?? ''}',
  ].join('\u0000');

  bool get _transferSameCurrency {
    if (widget.type != TransactionType.transfer ||
        _sourceAccountId == null ||
        _destinationAccountId == null) {
      return false;
    }
    return widget.data.accountsById[_sourceAccountId!]!.currencyId ==
        widget.data.accountsById[_destinationAccountId!]!.currencyId;
  }

  List<TemplateOption<String>> get _sourceAmountOptionsForUse {
    final source = _amountOptions(widget.template, source: true);
    if (source.isNotEmpty || !_transferSameCurrency) return source;
    return _amountOptions(widget.template, source: false);
  }

  bool get _sourceAmountIsFixed => _sourceAmountOptionsForUse.length == 1;

  List<Category> get _availableCategories => widget.data.entryFormCategories
      .where(
        (category) => category.allowedTransactionTypes.contains(widget.type),
      )
      .toList();

  List<_TemplateField> get _templateFields => [
    _TemplateField.date,
    _TemplateField.description,
    if (_sourceRequired) ...[
      _TemplateField.sourceAccount,
      _TemplateField.sourceAmount,
    ],
    if (_destinationRequired) ...[
      _TemplateField.destinationAccount,
      _TemplateField.destinationAmount,
    ],
    if (_categoryRequired || _availableCategories.isNotEmpty)
      _TemplateField.category,
    _TemplateField.tag,
  ];

  List<TemplateOption<String>> _amountOptions(
    TransactionTemplate? template, {
    required bool source,
  }) {
    if (template == null) return const [];
    return source
        ? template.effectiveSourceAmountOptions(widget.data.currenciesById)
        : template.effectiveDestinationAmountOptions(
            widget.data.currenciesById,
          );
  }

  T? _selectedTemplateValue<T>(List<TemplateOption<T>>? options) =>
      options == null ? null : defaultOrOnlyTemplateOption(options);

  String _legacyAmountValue(Money amount) =>
      amount.toMajorUnitsString(widget.data.currenciesById[amount.currencyId]!);

  void _setDescriptionPattern(String source) {
    for (final controller in _placeholderControllers.values) {
      controller.dispose();
    }
    _placeholderControllers.clear();
    _placeholderOptions.clear();
    _selectedPlaceholderOptions.clear();
    try {
      _descriptionPattern = TransactionDescriptionPattern.parse(source);
      _descriptionPatternError = null;
      for (final placeholder in _descriptionPattern!.placeholders) {
        final options =
            _descriptionPattern!.placeholderOptions[placeholder] ?? const [];
        _placeholderOptions[placeholder] = options;
        if (options.isEmpty) {
          _placeholderControllers[placeholder] = TextEditingController();
        } else {
          _selectedPlaceholderOptions[placeholder] =
              defaultOrOnlyTemplateOption(options);
        }
      }
    } on FormatException catch (error) {
      _descriptionPattern = null;
      _descriptionPatternError = error.message;
    }
  }

  @override
  void dispose() {
    _sourceAmountController.dispose();
    _destinationAmountController.dispose();
    _sourceFeeController.dispose();
    _destinationFeeController.dispose();
    _descriptionController.dispose();
    _templateNameController.dispose();
    for (final controller in _placeholderControllers.values) {
      controller.dispose();
    }
    for (final options in _templateOptionDrafts.values) {
      for (final option in options) {
        option.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    final fieldGap = compact && usesCompactVerticalSpacing(context)
        ? AppSpacing.sm + AppSpacing.xs
        : AppSpacing.md;
    final title = widget.createTemplate
        ? 'Create Template'
        : widget.template?.name ?? transactionTypeLabel(widget.type);
    final fields = widget.createTemplate
        ? _buildTemplateBuilder(fieldGap)
        : _buildTransactionFields(fieldGap);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Dialog routes can briefly report a near-zero viewport while opening
        // or while the platform window is being resized. Do not lay out the
        // fixed header/footer column in that transient 1px surface.
        if (constraints.maxWidth < 80 || constraints.maxHeight < 80) {
          return const SizedBox.shrink();
        }

        final horizontalGutter = compact
            ? AppPageSpacing.compactGutter
            : AppPageSpacing.desktopGutter;
        final header = TransactionEntryHeader(
          title: title,
          onBack: widget.onBack ?? () => Navigator.of(context).pop(),
          onClose: widget.onClose ?? () => Navigator.of(context).pop(),
        );
        final footer = Padding(
          key: const ValueKey('transaction-entry-submit-footer'),
          padding: EdgeInsets.fromLTRB(
            horizontalGutter,
            AppSpacing.sm,
            horizontalGutter,
            MediaQuery.viewInsetsOf(context).bottom + AppSpacing.sm,
          ),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _descriptionPatternError == null && !_resultSubmitted
                  ? _submit
                  : null,
              child: Text(
                widget.createTemplate ? 'Save Template' : 'Add Transaction',
              ),
            ),
          ),
        );
        final formPadding = EdgeInsets.fromLTRB(
          horizontalGutter,
          AppSpacing.sm,
          horizontalGutter,
          AppSpacing.md,
        );
        final compactViewport = constraints.maxHeight < 240;
        final content = compactViewport
            ? SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      header,
                      Form(
                        key: _formKey,
                        child: Padding(padding: formPadding, child: fields),
                      ),
                      footer,
                    ],
                  ),
                ),
              )
            : Column(
                children: [
                  header,
                  Expanded(
                    child: Form(
                      key: _formKey,
                      child: SingleChildScrollView(
                        padding: formPadding,
                        child: fields,
                      ),
                    ),
                  ),
                  footer,
                ],
              );

        return SafeArea(
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: content,
          ),
        );
      },
    );
  }

  Widget _buildTemplateSummary(TransactionTemplate template) {
    final entries = <(String label, String value)>[];
    void add(String label, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        entries.add((label, value));
      }
    }

    String? accountName(String? id) =>
        id == null ? null : widget.data.accountsById[id]?.name ?? id;
    String? amountLabel(Money? amount) =>
        amount == null ? null : formatMoney(amount, widget.data.currenciesById);

    if (template.date != null) add('Date', _formatDate(template.date!));
    if (template.description != null && template.description!.isNotEmpty) {
      var hasArguments = false;
      try {
        hasArguments = TransactionDescriptionPattern.parse(
          template.description!,
        ).placeholders.isNotEmpty;
      } on FormatException {
        // Leave malformed patterns to the form's existing validation message.
      }
      if (!hasArguments) add('Description', template.description);
    }
    switch (template.type) {
      case TransactionType.expense:
        add('Account', accountName(template.sourceAccountId));
        add('Amount', amountLabel(template.sourceAmount));
      case TransactionType.income:
      case TransactionType.reimbursement:
        add('Account', accountName(template.destinationAccountId));
        add('Amount', amountLabel(template.destinationAmount));
      case TransactionType.transfer:
        add('Source account', accountName(template.sourceAccountId));
        add('Source amount', amountLabel(template.sourceAmount));
        add('Destination account', accountName(template.destinationAccountId));
        add('Destination amount', amountLabel(template.destinationAmount));
    }
    if (template.categoryId != null) {
      add(
        'Category',
        widget.data.categoriesById[template.categoryId!]?.name ??
            template.categoryId,
      );
    }
    if (template.tagId != null) {
      add('Tag', widget.data.tagsById[template.tagId!]?.name ?? template.tagId);
    }

    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in entries)
            Text(
              '${entry.$1}: ${entry.$2}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _accountDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    List<Account>? accounts,
  }) {
    return TransactionAccountSelector(
      label: label,
      value: value,
      accounts: accounts ?? widget.data.entryFormAccounts,
      data: widget.data,
      requiredSelection: true,
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
      inputFormatters: const [ThousandsSeparatorInputFormatter()],
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter an amount.';
        }
        final parsed = num.tryParse(value.trim().replaceAll(',', ''));
        if (parsed == null || !parsed.isFinite || parsed < 0) {
          return 'Enter a valid amount.';
        }
        return null;
      },
    );
  }

  Widget _categoryDropdown({List<Category>? categories}) {
    return TransactionCategorySelector(
      label: _categoryRequired ? 'Category' : 'Category (optional)',
      value: _categoryId,
      categories: categories ?? _availableCategories,
      requiredSelection: _categoryRequired,
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
    if (_resultSubmitted) return;
    final invalidFields = _formKey.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      _focusFirstInvalidField(invalidFields);
      return;
    }
    if (_descriptionPatternError != null) return;

    if (widget.createTemplate) {
      final error = _validateTemplateOptionDrafts();
      if (error != null) {
        setState(() => _templateBuilderError = error);
        return;
      }
      _deliverResult(_buildTemplateFromDrafts());
      return;
    }

    if (_date == null) {
      final dateContext = _dateButtonKey.currentContext;
      if (dateContext != null) unawaited(Scrollable.ensureVisible(dateContext));
      showPersistentErrorDialog(context, 'Select a date.');
      return;
    }
    final sourceAccount = _sourceAccountId == null
        ? null
        : widget.data.accountsById[_sourceAccountId!];
    final destinationAccount = _destinationAccountId == null
        ? null
        : widget.data.accountsById[_destinationAccountId!];
    var sourceAmount = _parseAmount(
      _sourceAmountController.text,
      sourceAccount,
    );
    var transferDestinationAmount = _parseAmount(
      _destinationAmountController.text,
      destinationAccount,
    );
    if (_transferSameCurrency) {
      if (sourceAmount != null &&
          transferDestinationAmount != null &&
          sourceAmount.minorUnits != transferDestinationAmount.minorUnits &&
          (widget.template?.sourceAmountOptions.length ?? 0) <= 1 &&
          (widget.template?.destinationAmountOptions.length ?? 0) <= 1) {
        showPersistentErrorDialog(
          context,
          'The selected same-currency transfer amounts must match.',
        );
        return;
      }
      // Same-currency transfers have one amount control. If options were
      // stored for both legs, use the source choice for both legs.
      sourceAmount ??= transferDestinationAmount;
      transferDestinationAmount = sourceAmount;
    }
    final entryDescription = _descriptionPattern == null
        ? _descriptionController.text.trim()
        : _descriptionPattern!.compose({
            for (final placeholder in _descriptionPattern!.placeholders)
              placeholder: _placeholderOptions[placeholder]?.isNotEmpty == true
                  ? _selectedPlaceholderOptions[placeholder] ?? ''
                  : _placeholderControllers[placeholder]!.text,
          });
    if (sourceAmount == null && _sourceRequired ||
        transferDestinationAmount == null && _destinationRequired) {
      return;
    }

    if (widget.type == TransactionType.transfer) {
      final sourceFee = _sourceFeeEnabled
          ? _parseAmount(_sourceFeeController.text, sourceAccount)
          : null;
      final destinationFee = _destinationFeeEnabled
          ? _parseAmount(_destinationFeeController.text, destinationAccount)
          : null;
      if ((_sourceFeeEnabled && sourceFee == null) ||
          (_destinationFeeEnabled && destinationFee == null)) {
        return;
      }
      final result = buildTransferTransactions(
        existingIds: widget.data.transactionsById.keys,
        date: _date!,
        description: entryDescription,
        sourceAccountId: _sourceAccountId,
        sourceAmount: sourceAmount,
        destinationAccountId: _destinationAccountId,
        destinationAmount: transferDestinationAmount,
        sourceFee: sourceFee,
        destinationFee: destinationFee,
        sameCurrency: _transferSameCurrency,
        categoryId: _categoryId,
        tagId: _tagId,
        hasFinancialFeesCategory:
            widget
                .data
                .categoriesById['financial_fees']
                ?.allowedTransactionTypes
                .contains(TransactionType.expense) ==
            true,
      );
      if (!result.isValid) {
        showPersistentErrorDialog(context, result.error!);
        return;
      }
      _deliverResult(result.transactions);
      return;
    }

    final transaction = Transaction(
      id: generateTransactionId(widget.data.transactionsById.keys),
      createdAt: DateTime.now().toUtc(),
      date: DateTime.utc(_date!.year, _date!.month, _date!.day),
      type: widget.type,
      sourceAmount: sourceAmount,
      sourceAccountId: _sourceAccountId,
      destinationAmount: transferDestinationAmount,
      destinationAccountId: _destinationAccountId,
      categoryId: _categoryId,
      tagId: _tagId,
      description: entryDescription,
    );
    final errors = transaction.validateForEntry();
    if (errors.isNotEmpty) {
      showPersistentErrorDialog(context, errors.join(' '));
      return;
    }
    _deliverResult(transaction);
  }

  void _deliverResult(Object result) {
    if (_resultSubmitted) return;
    _resultSubmitted = true;
    final onResult = widget.onResult;
    if (onResult != null) {
      onResult(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  void _focusFirstInvalidField(Set<FormFieldState<Object?>> invalidFields) {
    final fields = invalidFields.toList()
      ..sort((a, b) {
        double top(FormFieldState<Object?> field) {
          final renderObject = field.context.findRenderObject();
          return renderObject is RenderBox
              ? renderObject.localToGlobal(Offset.zero).dy
              : double.infinity;
        }

        return top(a).compareTo(top(b));
      });
    final first = fields.first;
    unawaited(
      Scrollable.ensureVisible(
        first.context,
        alignment: 0.2,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      ),
    );

    FocusNode? firstFocus;
    void findEditable(Element element) {
      if (firstFocus != null) return;
      final widget = element.widget;
      if (widget is EditableText) {
        firstFocus = widget.focusNode;
        return;
      }
      element.visitChildElements(findEditable);
    }

    first.context.visitChildElements(findEditable);
    firstFocus?.requestFocus();
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

  String? _validateDescriptionPattern(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    try {
      final pattern = TransactionDescriptionPattern.parse(value);
      if (pattern.placeholderOptions.values.any(
        (options) => options.isNotEmpty,
      )) {
        return 'Enter placeholder names as {Name}; add their choices below the description.';
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? _validateTransactionDescription(String? value) {
    if (value == null || value.trim().isEmpty) return 'Enter a description.';
    return validateTemplateEntryText(value);
  }

  String _descriptionPreview() {
    final pattern = _descriptionPattern!;
    return pattern.compose({
      for (final placeholder in pattern.placeholders)
        placeholder: _placeholderOptions[placeholder]?.isNotEmpty == true
            ? _selectedPlaceholderOptions[placeholder] ?? '{$placeholder}'
            : _placeholderControllers[placeholder]!.text.trim().isEmpty
            ? '{$placeholder}'
            : _placeholderControllers[placeholder]!.text,
    });
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
