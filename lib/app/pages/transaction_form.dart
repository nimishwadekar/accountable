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
        final categoryName = template.categoryId == null
            ? 'No category'
            : widget.data.categoriesById[template.categoryId!]?.name ??
                  'Unknown category';
        return query.isEmpty ||
            template.name.toLowerCase().contains(query) ||
            categoryName.toLowerCase().contains(query) ||
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
    final category = template.categoryId == null
        ? 'No category'
        : widget.data.categoriesById[template.categoryId!]?.name ??
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
    if (template.description != null && template.description!.isNotEmpty) {
      try {
        TransactionDescriptionPattern.parse(template.description!);
      } on FormatException catch (error) {
        return error.message;
      }
    }
    final categoryId = template.categoryId;
    if (categoryId != null) {
      final category = widget.data.categoriesById[categoryId];
      if (category == null ||
          !category.allowedTransactionTypes.contains(template.type)) {
        return 'category is missing or incompatible';
      }
    }
    if (template.tagId != null &&
        !widget.data.tagsById.containsKey(template.tagId)) {
      return 'tag is missing';
    }
    for (final accountId in [
      template.sourceAccountId,
      template.destinationAccountId,
    ]) {
      if (accountId != null &&
          !widget.data.accountsById.containsKey(accountId)) {
        return 'account $accountId is missing';
      }
    }
    if (template.type == TransactionType.transfer &&
        template.sourceAccountId != null &&
        template.destinationAccountId != null &&
        template.sourceAmount != null &&
        template.destinationAmount != null) {
      final sourceCurrency =
          widget.data.accountsById[template.sourceAccountId]!.currencyId;
      final destinationCurrency =
          widget.data.accountsById[template.destinationAccountId]!.currencyId;
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

  DateTime? _date;
  String? _sourceAccountId;
  String? _destinationAccountId;
  String? _categoryId;
  String? _tagId;
  TransactionDescriptionPattern? _descriptionPattern;
  String? _descriptionPatternError;
  late String _initialDraftFingerprint;
  bool _resultSubmitted = false;

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
    _date = template?.date ?? (widget.createTemplate ? null : DateTime.now());
    _descriptionController.text = template?.description ?? '';
    if (!widget.createTemplate && template?.hasDescription == true) {
      try {
        _descriptionPattern = TransactionDescriptionPattern.parse(
          template!.description!,
        );
        for (final placeholder in _descriptionPattern!.placeholders) {
          _placeholderControllers[placeholder] = TextEditingController();
        }
      } on FormatException catch (error) {
        _descriptionPatternError = error.message;
      }
    }
    _sourceAccountId = template?.sourceAccountId;
    _destinationAccountId = template?.destinationAccountId;
    _categoryId = template?.categoryId;
    _tagId = template?.tagId;
    final fixedSourceAmount =
        template?.sourceAmount ??
        (_transferSameCurrency ? template?.destinationAmount : null);
    if (fixedSourceAmount != null) {
      _sourceAmountController.text = fixedSourceAmount
          .toMajorUnits(
            widget.data.currenciesById[fixedSourceAmount.currencyId]!,
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
    for (final placeholder in _placeholderControllers.keys.toList()..sort())
      '$placeholder=${_placeholderControllers[placeholder]!.text}',
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

  bool get _sourceAmountIsFixed =>
      widget.template?.sourceAmount != null ||
      (_transferSameCurrency && widget.template?.destinationAmount != null);

  List<Category> get _availableCategories => widget.data.entryFormCategories
      .where(
        (category) => category.allowedTransactionTypes.contains(widget.type),
      )
      .toList();

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
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.template != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildTemplateSummary(widget.template!),
        ],
        if (widget.createTemplate) ...[
          SizedBox(height: fieldGap),
          TextFormField(
            controller: _templateNameController,
            decoration: const InputDecoration(labelText: 'Template Name'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a template name.'
                : null,
          ),
        ],
        SizedBox(height: fieldGap),
        if (widget.createTemplate)
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description pattern',
              hintText: 'Coffee at {Merchant}',
              helperText: 'Use {Label} to ask for a value each time.',
            ),
            validator: _validateDescriptionPattern,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
          ),
        if (!widget.createTemplate && _descriptionPatternError != null)
          Text(
            'This template cannot be used: $_descriptionPatternError. Fix its description in Sheets.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!widget.createTemplate &&
            widget.template?.hasDescription != true) ...[
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description'),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter a description.'
                : null,
          ),
          SizedBox(height: fieldGap),
        ],
        if (!widget.createTemplate &&
            _descriptionPattern != null &&
            _descriptionPattern!.placeholders.isNotEmpty) ...[
          for (final placeholder in _descriptionPattern!.placeholders)
            Padding(
              padding: EdgeInsets.only(bottom: fieldGap),
              child: TextFormField(
                controller: _placeholderControllers[placeholder],
                decoration: InputDecoration(labelText: placeholder),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter $placeholder.'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
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
        if (widget.createTemplate || widget.template?.date == null)
          SizedBox(height: fieldGap),
        if (widget.template == null || widget.template!.date == null)
          OutlinedButton.icon(
            key: _dateButtonKey,
            onPressed: _selectDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_date == null ? 'Select date' : _formatDate(_date!)),
          ),
        SizedBox(height: fieldGap),
        if (_sourceRequired &&
            (widget.template == null ||
                widget.template!.sourceAccountId == null)) ...[
          _accountDropdown(
            label: _destinationRequired ? 'Source Account' : 'Account',
            value: _sourceAccountId,
            onChanged: (value) => setState(() => _sourceAccountId = value),
          ),
          SizedBox(height: fieldGap),
        ],
        if (_sourceRequired && !_sourceAmountIsFixed) ...[
          _amountField(
            controller: _sourceAmountController,
            label: _destinationRequired ? 'Source Amount' : 'Amount',
            accountId: _sourceAccountId,
          ),
          if (_destinationRequired) SizedBox(height: fieldGap),
        ],
        if (widget.type == TransactionType.transfer &&
            !widget.createTemplate) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _sourceFeeEnabled,
            title: const Text('Source Account Fee'),
            onChanged: (value) =>
                setState(() => _sourceFeeEnabled = value ?? false),
          ),
          if (_sourceFeeEnabled)
            _amountField(
              controller: _sourceFeeController,
              label: 'Source Fee',
              accountId: _sourceAccountId,
            ),
          SizedBox(height: fieldGap),
        ],
        if (_destinationRequired &&
            (widget.template == null ||
                widget.template!.destinationAccountId == null)) ...[
          _accountDropdown(
            label: _sourceRequired ? 'Destination Account' : 'Account',
            value: _destinationAccountId,
            onChanged: (value) => setState(() => _destinationAccountId = value),
          ),
          SizedBox(height: fieldGap),
        ],
        if (_destinationRequired &&
            !_transferSameCurrency &&
            (widget.template == null ||
                widget.template!.destinationAmount == null))
          _amountField(
            controller: _destinationAmountController,
            label: _sourceRequired ? 'Destination Amount' : 'Amount',
            accountId: _destinationAccountId,
          ),
        if (widget.type == TransactionType.transfer &&
            !widget.createTemplate) ...[
          SizedBox(height: fieldGap),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _destinationFeeEnabled,
            title: const Text('Destination Account Fee'),
            onChanged: (value) =>
                setState(() => _destinationFeeEnabled = value ?? false),
          ),
          if (_destinationFeeEnabled)
            _amountField(
              controller: _destinationFeeController,
              label: 'Destination Fee',
              accountId: _destinationAccountId,
            ),
        ],
        if ((widget.template == null || widget.template!.categoryId == null) &&
            (_categoryRequired || _availableCategories.isNotEmpty)) ...[
          SizedBox(height: fieldGap),
          _categoryDropdown(),
        ],
        if (widget.template == null || widget.template!.tagId == null) ...[
          SizedBox(height: fieldGap),
          _tagDropdown(),
        ],
      ],
    );

    return SafeArea(
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
          children: [
            TransactionEntryHeader(
              title: title,
              onBack: widget.onBack ?? () => Navigator.of(context).pop(),
              onClose: widget.onClose ?? () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    compact
                        ? AppPageSpacing.compactGutter
                        : AppPageSpacing.desktopGutter,
                    AppSpacing.sm,
                    compact
                        ? AppPageSpacing.compactGutter
                        : AppPageSpacing.desktopGutter,
                    AppSpacing.md,
                  ),
                  child: fields,
                ),
              ),
            ),
            Padding(
              key: const ValueKey('transaction-entry-submit-footer'),
              padding: EdgeInsets.fromLTRB(
                compact
                    ? AppPageSpacing.compactGutter
                    : AppPageSpacing.desktopGutter,
                AppSpacing.sm,
                compact
                    ? AppPageSpacing.compactGutter
                    : AppPageSpacing.desktopGutter,
                MediaQuery.viewInsetsOf(context).bottom + AppSpacing.sm,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      _descriptionPatternError == null && !_resultSubmitted
                      ? _submit
                      : null,
                  child: Text(
                    widget.createTemplate ? 'Save Template' : 'Add Transaction',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
      inputFormatters: const [ThousandsSeparatorInputFormatter()],
      validator: (value) {
        if (widget.createTemplate &&
            value != null &&
            value.trim().isNotEmpty &&
            account == null) {
          return 'Select an account to save this amount.';
        }
        if (widget.createTemplate && (value == null || value.trim().isEmpty)) {
          return null;
        }
        if (value == null || value.trim().isEmpty) {
          return 'Enter an amount.';
        }
        final parsed = num.tryParse(value.trim().replaceAll(',', ''));
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
    if (_resultSubmitted) return;
    final invalidFields = _formKey.currentState!.validateGranularly();
    if (invalidFields.isNotEmpty) {
      _focusFirstInvalidField(invalidFields);
      return;
    }
    if (_descriptionPatternError != null) return;

    if (!widget.createTemplate && _date == null) {
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
          sourceAmount.minorUnits != transferDestinationAmount.minorUnits) {
        showPersistentErrorDialog(
          context,
          'This same-currency template has conflicting saved amounts. Fix it in Sheets.',
        );
        return;
      }
      sourceAmount ??= transferDestinationAmount;
      transferDestinationAmount = sourceAmount;
    }
    final entryDescription = _descriptionPattern == null
        ? _descriptionController.text.trim()
        : _descriptionPattern!.compose({
            for (final entry in _placeholderControllers.entries)
              entry.key: entry.value.text,
          });
    if (!widget.createTemplate &&
        (sourceAmount == null && _sourceRequired ||
            transferDestinationAmount == null && _destinationRequired)) {
      return;
    }
    if (widget.createTemplate) {
      final now = DateTime.now().toUtc();
      _deliverResult(
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
          destinationAmount: transferDestinationAmount,
          isFavorite: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
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
      TransactionDescriptionPattern.parse(value);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String _descriptionPreview() {
    final pattern = _descriptionPattern!;
    return pattern.compose({
      for (final placeholder in pattern.placeholders)
        placeholder: _placeholderControllers[placeholder]!.text.trim().isEmpty
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
