import 'dart:async';
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../../app/amount_input_formatter.dart';
import '../../app/error_dialog.dart';
import '../../app/pages/transaction_entry_layout.dart';
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
  late final String _initialDraftFingerprint;
  bool _allowPop = false;
  bool _closing = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _initialDraftFingerprint = _draftFingerprint;
  }

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < AppBreakpoints.compact;
        final maxHeight = (constraints.maxHeight - AppSpacing.lg * 2)
            .clamp(280.0, 760.0)
            .toDouble();
        final surfaceConstraints = compact
            ? BoxConstraints.tightFor(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
              )
            : BoxConstraints(maxWidth: 560, maxHeight: maxHeight);
        return Semantics(
          role: SemanticsRole.dialog,
          child: Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: surfaceConstraints,
              child: Material(
                key: const ValueKey('income-allocation-surface'),
                color: Theme.of(context).colorScheme.surface,
                elevation: compact ? 0 : 24,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(compact ? 0 : 28),
                ),
                child: _buildForm(context, compact, incomeCategories, accounts),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildForm(
    BuildContext context,
    bool compact,
    List<Category> incomeCategories,
    List<Account> accounts,
  ) {
    final fieldGap = compact && usesCompactVerticalSpacing(context)
        ? AppSpacing.sm + AppSpacing.xs
        : AppSpacing.md;
    return PopScope<IncomeAllocation>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: SafeArea(
        child: Column(
          children: [
            TransactionEntryHeader(
              title: 'Add Income Allocation',
              onClose: () => unawaited(_requestClose()),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: _required,
                      ),
                      SizedBox(height: fieldGap),
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
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                      ),
                      SizedBox(height: fieldGap),
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
                      SizedBox(height: fieldGap),
                      TextFormField(
                        controller: _amount,
                        decoration: const InputDecoration(
                          labelText: 'Expected amount',
                          helperText: 'Amount to expect each time this income is received.',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [
                          ThousandsSeparatorInputFormatter(),
                        ],
                        validator: _amountValidator,
                      ),
                      SizedBox(height: fieldGap),
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
                      SizedBox(height: fieldGap),
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
            Padding(
              key: const ValueKey('income-allocation-actions'),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 380 ||
                      MediaQuery.textScalerOf(context).scale(14) > 18;
                  final cancel = TextButton(
                    onPressed: _closing ? null : _requestClose,
                    child: const Text('Cancel'),
                  );
                  final save = FilledButton(
                    onPressed: _submitted ? null : _submit,
                    child: const Text('Save'),
                  );
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        save,
                        const SizedBox(height: AppSpacing.xs),
                        cancel,
                      ],
                    );
                  }
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      cancel,
                      const SizedBox(width: AppSpacing.sm),
                      save,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
    final parsed = num.tryParse(value!.trim().replaceAll(',', ''));
    return parsed == null || parsed <= 0 ? 'Enter a positive amount.' : null;
  }

  String get _draftFingerprint => [
    _name.text,
    _amount.text,
    _categoryId ?? '',
    _incomeAccountId ?? '',
    _transferCategoryId ?? '',
    _startDate.toIso8601String(),
    _endDate?.toIso8601String() ?? '',
  ].join('\u0000');

  Future<void> _requestClose() async {
    if (_allowPop || _closing) return;
    if (_draftFingerprint != _initialDraftFingerprint) {
      setState(() => _closing = true);
      final discard =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: const Text('Discard changes?'),
              content: const Text('Your allocation has not been saved.'),
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
      if (!mounted) return;
      if (!discard) {
        setState(() => _closing = false);
        return;
      }
    }
    if (mounted) _allowPopAndClose();
  }

  void _allowPopAndClose() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _submit() {
    if (_submitted || !_formKey.currentState!.validate()) return;
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      showPersistentErrorDialog(context, 'End date must be after start date.');
      return;
    }
    final now = DateTime.now().toUtc();
    final incomeAccount = widget.data.accountsById[_incomeAccountId!]!;
    final currency = widget.data.currenciesById[incomeAccount.currencyId]!;
    final allocation = IncomeAllocation(
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
    );
    _submitted = true;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(allocation);
    });
  }
}
