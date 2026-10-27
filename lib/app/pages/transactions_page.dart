import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';
import 'transaction_form.dart';
import 'transaction_review_sheet.dart';
import '../session_ui_preferences.dart';
import 'transaction_list_widgets.dart';

bool isTransactionDateInRange(DateTime transactionDate, DateTimeRange range) {
  final date = _dateOnlyUtc(transactionDate);
  final start = _dateOnlyUtc(range.start);
  final end = _dateOnlyUtc(range.end);
  return !date.isBefore(start) && !date.isAfter(end);
}

DateTime _dateOnlyUtc(DateTime value) {
  return DateTime.utc(value.year, value.month, value.day);
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.data,
    required this.onTransactionAdded,
    required this.onTransactionsAdded,
    required this.onTemplateAdded,
    this.restrictedStartup = false,
    this.onStartupSignIn,
    this.startupError,
    this.onRetryOutbox,
    this.onTransactionFormActiveChanged,
  });

  final AppDataSnapshot data;
  final Future<void> Function(Transaction transaction) onTransactionAdded;
  final Future<void> Function(List<Transaction> transactions)
  onTransactionsAdded;
  final Future<void> Function(TransactionTemplate template) onTemplateAdded;
  final bool restrictedStartup;
  final Future<void> Function()? onStartupSignIn;
  final String? startupError;
  final Future<void> Function()? onRetryOutbox;
  final ValueChanged<bool>? onTransactionFormActiveChanged;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final ScrollController _scrollController = ScrollController();

  TransactionType? _transactionType;
  String? _accountId;
  String? _categoryId;
  String? _tagId;
  DateTimeRange? _dateRange;
  bool _showScrollToTop = false;
  AppDataSnapshot? _cachedFilterData;
  String? _cachedFilterKey;
  List<Transaction>? _cachedFilteredTransactions;
  List<_TransactionListItem>? _cachedListItems;
  List<Transaction>? _cachedListSource;

  @override
  void initState() {
    super.initState();
    final session = SessionUiPreferences.instance;
    _transactionType = _transactionTypeFromName(session.transactionType);
    _accountId =
        widget.data.accountsById.containsKey(session.transactionAccountId)
        ? session.transactionAccountId
        : null;
    _categoryId =
        widget.data.categoriesById.containsKey(session.transactionCategoryId)
        ? session.transactionCategoryId
        : null;
    _tagId = widget.data.tagsById.containsKey(session.transactionTagId)
        ? session.transactionTagId
        : null;
    final start = DateTime.tryParse(session.transactionDateStart ?? '');
    final end = DateTime.tryParse(session.transactionDateEnd ?? '');
    if (start != null && end != null) {
      _dateRange = DateTimeRange(start: start, end: end);
    }
    _scrollController.addListener(_handleScroll);
  }

  TransactionType? _transactionTypeFromName(String? value) {
    for (final type in TransactionType.values) {
      if (type.name == value) return type;
    }
    return null;
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < AppBreakpoints.compact;
    final transactions = _filteredTransactions;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddTransaction,
        icon: const Icon(Icons.add),
        label: const Text('Add transaction'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.maxContentWidth,
              ),
              child: SizedBox(
                height: constraints.maxHeight,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transactions',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.restrictedStartup
                            ? '${transactions.length} pending local transactions'
                            : '${transactions.length} of ${widget.data.transactions.length} transactions',
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: AppColors.mutedText),
                      ),
                      if (widget.restrictedStartup &&
                          (widget.startupError != null ||
                              widget.onStartupSignIn != null ||
                              widget.onRetryOutbox != null)) ...[
                        const SizedBox(height: AppSpacing.sm),
                        if (widget.startupError != null)
                          Text(
                            'Pending upload issue: ${widget.startupError}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            if (widget.onStartupSignIn != null)
                              TextButton.icon(
                                onPressed: widget.onStartupSignIn,
                                icon: const Icon(Icons.login),
                                label: const Text('Sign in to sync'),
                              ),
                            if (widget.onRetryOutbox != null)
                              TextButton.icon(
                                onPressed: widget.onRetryOutbox,
                                icon: const Icon(Icons.sync),
                                label: const Text('Retry upload'),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      if (isCompact)
                        _buildCompactFilterButton(context)
                      else
                        _buildDesktopFilters(context),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(
                        child: Stack(
                          children: [
                            if (transactions.isEmpty)
                              const EmptyTransactionsState()
                            else
                              _buildGroupedList(transactions),
                            if (_showScrollToTop)
                              Positioned(
                                right: AppSpacing.md,
                                bottom: AppSpacing.md,
                                child: FloatingActionButton.small(
                                  onPressed: _scrollToTop,
                                  tooltip: 'Back to top',
                                  child: const Icon(Icons.arrow_upward),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<T?> _showTransactionDialog<T>(Widget child) {
    return showDialog<T>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _openAddTransaction() async {
    widget.onTransactionFormActiveChanged?.call(true);
    try {
      await _openAddTransactionFlow();
    } finally {
      if (mounted) widget.onTransactionFormActiveChanged?.call(false);
    }
  }

  Future<void> _openAddTransactionFlow() async {
    final choice = await _showTransactionDialog<AddTransactionChoice>(
      TransactionTypeChooser(data: widget.data),
    );
    if (!mounted || choice == null) return;

    AddTransactionChoice resolved = choice;
    if (choice.createTemplate) {
      resolved =
          await _showTransactionDialog<AddTransactionChoice>(
            const TransactionTypeChooser(createTemplate: true),
          ) ??
          choice;
    }
    if (!mounted || resolved.type == null) return;
    final result = await _showTransactionDialog<Object>(
      TransactionFormSheet(
        type: resolved.type!,
        data: widget.data,
        template: resolved.template,
        createTemplate: choice.createTemplate,
      ),
    );
    if (!mounted || result == null) return;

    if (result is Transaction && resolved.template != null) {
      final reviewed = await _showTransactionDialog<bool>(
        TransactionReviewSheet(transaction: result, data: widget.data),
      );
      if (reviewed != true) return;
    }

    try {
      if (result is List<Transaction>) {
        await widget.onTransactionsAdded(result);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Transfer added.')));
        return;
      }
      if (result is TransactionTemplate) {
        await widget.onTemplateAdded(result);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Template saved.')));
        return;
      }
      await widget.onTransactionAdded(result as Transaction);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Transaction added.')));
    } catch (error) {
      if (!mounted) return;
      final message = error is TransactionSavedHistoryRepairException
          ? error.toString()
          : 'Could not add transaction: $error';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<Transaction> get _filteredTransactions {
    final filterKey = [
      _transactionType?.name ?? '',
      _accountId ?? '',
      _categoryId ?? '',
      _tagId ?? '',
      _dateRange?.start.toIso8601String() ?? '',
      _dateRange?.end.toIso8601String() ?? '',
    ].join('|');
    if (identical(_cachedFilterData, widget.data) &&
        _cachedFilterKey == filterKey &&
        _cachedFilteredTransactions != null) {
      return _cachedFilteredTransactions!;
    }

    final hasFilters =
        _transactionType != null ||
        _accountId != null ||
        _categoryId != null ||
        _tagId != null ||
        _dateRange != null;
    final filtered = hasFilters
        ? widget.data.transactionsByDisplayOrder
              .where((transaction) {
                if (_transactionType != null &&
                    transaction.type != _transactionType) {
                  return false;
                }
                if (_accountId != null &&
                    transaction.sourceAccountId != _accountId &&
                    transaction.destinationAccountId != _accountId) {
                  return false;
                }
                if (_categoryId != null &&
                    transaction.categoryId != _categoryId) {
                  return false;
                }
                if (_tagId != null && transaction.tagId != _tagId) {
                  return false;
                }
                if (_dateRange != null &&
                    !isTransactionDateInRange(transaction.date, _dateRange!)) {
                  return false;
                }
                return true;
              })
              .toList(growable: false)
        : widget.data.transactionsByDisplayOrder;
    _cachedFilterData = widget.data;
    _cachedFilterKey = filterKey;
    _cachedFilteredTransactions = filtered;
    _cachedListItems = null;
    _cachedListSource = null;
    return filtered;
  }

  Widget _buildCompactFilterButton(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _openFilterSheet,
          icon: const Icon(Icons.filter_list),
          label: Text(_filterButtonLabel),
        ),
        if (_hasFilters) ...[
          const SizedBox(width: AppSpacing.sm),
          TextButton(onPressed: _clearFilters, child: const Text('Clear')),
        ],
      ],
    );
  }

  Widget _buildDesktopFilters(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 180, child: _buildTypeDropdown()),
            SizedBox(width: 220, child: _buildAccountDropdown()),
            SizedBox(width: 220, child: _buildCategoryDropdown()),
            SizedBox(width: 180, child: _buildTagDropdown()),
            OutlinedButton.icon(
              onPressed: _selectDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(_dateRangeLabel),
            ),
            if (_hasFilters)
              TextButton(
                onPressed: _clearFilters,
                child: const Text('Clear Filters'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList(List<Transaction> transactions) {
    final items = _listItemsFor(transactions);
    return ListView.separated(
      key: const PageStorageKey<String>('transactions-list'),
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return item.date == null
            ? TransactionListRow(
                transaction: item.transaction!,
                data: widget.data,
                onTap: () => _showTransactionDetails(item.transaction!),
              )
            : TransactionDateHeader(date: item.date!);
      },
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.xs),
    );
  }

  List<_TransactionListItem> _listItemsFor(List<Transaction> transactions) {
    if (identical(_cachedListSource, transactions) &&
        _cachedListItems != null) {
      return _cachedListItems!;
    }
    final items = <_TransactionListItem>[];
    DateTime? lastDate;
    for (final transaction in transactions) {
      final date = DateTime.utc(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      if (lastDate != date) {
        items.add(_TransactionListItem.header(date));
        lastDate = date;
      }
      items.add(_TransactionListItem.transaction(transaction));
    }
    _cachedListSource = transactions;
    _cachedListItems = List.unmodifiable(items);
    return _cachedListItems!;
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<TransactionType?>(
      initialValue: _transactionType,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Type'),
      items: [
        const DropdownMenuItem<TransactionType?>(
          value: null,
          child: Text('All Types'),
        ),
        for (final type in TransactionType.values)
          DropdownMenuItem<TransactionType?>(
            value: type,
            child: Text(transactionTypeLabel(type)),
          ),
      ],
      onChanged: (value) {
        setState(() => _transactionType = value);
        _persistFilters();
      },
    );
  }

  Widget _buildAccountDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _accountId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Account'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Accounts'),
        ),
        for (final account in widget.data.visibleAccounts)
          DropdownMenuItem<String?>(
            value: account.id,
            child: Text(account.name),
          ),
      ],
      onChanged: (value) {
        setState(() => _accountId = value);
        _persistFilters();
      },
    );
  }

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _categoryId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Categories'),
        ),
        for (final category in widget.data.visibleCategories)
          DropdownMenuItem<String?>(
            value: category.id,
            child: Text(category.name),
          ),
      ],
      onChanged: (value) {
        setState(() => _categoryId = value);
        _persistFilters();
      },
    );
  }

  Widget _buildTagDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _tagId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Tag'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All Tags')),
        for (final tag in widget.data.visibleTags)
          DropdownMenuItem<String?>(value: tag.id, child: Text(tag.name)),
      ],
      onChanged: (value) {
        setState(() => _tagId = value);
        _persistFilters();
      },
    );
  }

  Future<void> _openFilterSheet() async {
    final filters = await showModalBottomSheet<_TransactionFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _TransactionFilterSheet(
        data: widget.data,
        initialFilters: _TransactionFilters(
          transactionType: _transactionType,
          accountId: _accountId,
          categoryId: _categoryId,
          tagId: _tagId,
          dateRange: _dateRange,
        ),
      ),
    );
    if (!mounted || filters == null) return;
    setState(() {
      _transactionType = filters.transactionType;
      _accountId = filters.accountId;
      _categoryId = filters.categoryId;
      _tagId = filters.tagId;
      _dateRange = filters.dateRange;
    });
    _persistFilters();
  }

  Future<void> _selectDateRange() async {
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (!mounted || selectedRange == null) return;
    setState(() => _dateRange = selectedRange);
    _persistFilters();
  }

  void _clearFilters() {
    setState(() {
      _transactionType = null;
      _accountId = null;
      _categoryId = null;
      _tagId = null;
      _dateRange = null;
    });
    _persistFilters();
  }

  void _persistFilters() {
    final session = SessionUiPreferences.instance;
    session
      ..transactionType = _transactionType?.name
      ..transactionAccountId = _accountId
      ..transactionCategoryId = _categoryId
      ..transactionTagId = _tagId
      ..transactionDateStart = _dateRange?.start.toIso8601String()
      ..transactionDateEnd = _dateRange?.end.toIso8601String();
    unawaited(session.persist());
  }

  void _handleScroll() {
    final shouldShow = _scrollController.offset > 300;
    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _showTransactionDetails(Transaction transaction) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          TransactionDetailsSheet(transaction: transaction, data: widget.data),
    );
  }

  bool get _hasFilters =>
      _transactionType != null ||
      _accountId != null ||
      _categoryId != null ||
      _tagId != null ||
      _dateRange != null;

  String get _filterButtonLabel {
    if (!_hasFilters) return 'Filters';
    final count = [
      _transactionType,
      _accountId,
      _categoryId,
      _tagId,
      _dateRange,
    ].where((value) => value != null).length;
    return 'Filters ($count)';
  }

  String get _dateRangeLabel {
    if (_dateRange == null) return 'All Dates';
    return '${formatDate(_dateRange!.start)} – ${formatDate(_dateRange!.end)}';
  }
}

class _TransactionListItem {
  const _TransactionListItem.header(this.date) : transaction = null;

  const _TransactionListItem.transaction(this.transaction) : date = null;

  final DateTime? date;
  final Transaction? transaction;
}

class _TransactionFilters {
  const _TransactionFilters({
    this.transactionType,
    this.accountId,
    this.categoryId,
    this.tagId,
    this.dateRange,
  });

  final TransactionType? transactionType;
  final String? accountId;
  final String? categoryId;
  final String? tagId;
  final DateTimeRange? dateRange;
}

class _TransactionFilterSheet extends StatefulWidget {
  const _TransactionFilterSheet({
    required this.data,
    required this.initialFilters,
  });

  final AppDataSnapshot data;
  final _TransactionFilters initialFilters;

  @override
  State<_TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<_TransactionFilterSheet> {
  late TransactionType? _transactionType =
      widget.initialFilters.transactionType;
  late String? _accountId = widget.initialFilters.accountId;
  late String? _categoryId = widget.initialFilters.categoryId;
  late String? _tagId = widget.initialFilters.tagId;
  late DateTimeRange? _dateRange = widget.initialFilters.dateRange;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Filters', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              _buildTypeDropdown(),
              const SizedBox(height: AppSpacing.md),
              _buildAccountDropdown(),
              const SizedBox(height: AppSpacing.md),
              _buildCategoryDropdown(),
              const SizedBox(height: AppSpacing.md),
              _buildTagDropdown(),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.date_range),
                label: Text(_dateRangeLabel),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _apply,
                child: const Text('Apply filters'),
              ),
              TextButton(onPressed: _clear, child: const Text('Clear Filters')),
            ],
          ),
        ),
      ),
    );
  }

  DropdownButtonFormField<TransactionType?> _buildTypeDropdown() {
    return DropdownButtonFormField<TransactionType?>(
      initialValue: _transactionType,
      decoration: const InputDecoration(labelText: 'Type'),
      items: [
        const DropdownMenuItem<TransactionType?>(
          value: null,
          child: Text('All Types'),
        ),
        for (final type in TransactionType.values)
          DropdownMenuItem<TransactionType?>(
            value: type,
            child: Text(transactionTypeLabel(type)),
          ),
      ],
      onChanged: (value) => setState(() => _transactionType = value),
    );
  }

  DropdownButtonFormField<String?> _buildAccountDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _accountId,
      decoration: const InputDecoration(labelText: 'Account'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Accounts'),
        ),
        for (final account in widget.data.visibleAccounts)
          DropdownMenuItem<String?>(
            value: account.id,
            child: Text(account.name),
          ),
      ],
      onChanged: (value) => setState(() => _accountId = value),
    );
  }

  DropdownButtonFormField<String?> _buildCategoryDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _categoryId,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('All Categories'),
        ),
        for (final category in widget.data.visibleCategories)
          DropdownMenuItem<String?>(
            value: category.id,
            child: Text(category.name),
          ),
      ],
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }

  DropdownButtonFormField<String?> _buildTagDropdown() {
    return DropdownButtonFormField<String?>(
      initialValue: _tagId,
      decoration: const InputDecoration(labelText: 'Tag'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('All Tags')),
        for (final tag in widget.data.visibleTags)
          DropdownMenuItem<String?>(value: tag.id, child: Text(tag.name)),
      ],
      onChanged: (value) => setState(() => _tagId = value),
    );
  }

  Future<void> _selectDateRange() async {
    final selectedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (!mounted || selectedRange == null) return;
    setState(() => _dateRange = selectedRange);
  }

  void _apply() {
    Navigator.of(context).pop(
      _TransactionFilters(
        transactionType: _transactionType,
        accountId: _accountId,
        categoryId: _categoryId,
        tagId: _tagId,
        dateRange: _dateRange,
      ),
    );
  }

  void _clear() {
    setState(() {
      _transactionType = null;
      _accountId = null;
      _categoryId = null;
      _tagId = null;
      _dateRange = null;
    });
  }

  String get _dateRangeLabel {
    if (_dateRange == null) return 'All Dates';
    return '${formatDate(_dateRange!.start)} – ${formatDate(_dateRange!.end)}';
  }
}
