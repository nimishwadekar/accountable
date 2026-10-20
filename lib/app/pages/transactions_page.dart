import 'package:flutter/material.dart';

import '../../data/data.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';
import 'transaction_form.dart';
import 'transaction_review_sheet.dart';

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
  });

  final AppDataSnapshot data;
  final Future<void> Function(Transaction transaction) onTransactionAdded;
  final Future<void> Function(List<Transaction> transactions) onTransactionsAdded;
  final Future<void> Function(TransactionTemplate template) onTemplateAdded;

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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
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
                        '${transactions.length} of ${widget.data.transactions.length} transactions',
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: AppColors.mutedText),
                      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer added.')),
        );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add transaction: $error')),
      );
    }
  }

  List<Transaction> get _filteredTransactions {
    final filtered = widget.data.transactions.where((transaction) {
      if (_transactionType != null && transaction.type != _transactionType) {
        return false;
      }
      if (_accountId != null &&
          transaction.sourceAccountId != _accountId &&
          transaction.destinationAccountId != _accountId) {
        return false;
      }
      if (_categoryId != null && transaction.categoryId != _categoryId) {
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
    }).toList();

    filtered.sort((a, b) {
      final dateComparison = b.date.compareTo(a.date);
      if (dateComparison != 0) return dateComparison;
      return b.createdAt.compareTo(a.createdAt);
    });
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
    final groups = <DateTime, List<Transaction>>{};
    for (final transaction in transactions) {
      final date = DateTime.utc(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      groups.putIfAbsent(date, () => []).add(transaction);
    }

    final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final children = <Widget>[];
    for (final date in dates) {
      children.add(_DateHeader(date: date));
      for (final transaction in groups[date]!) {
        children.add(
          TransactionListRow(
            transaction: transaction,
            data: widget.data,
            onTap: () => _showTransactionDetails(transaction),
          ),
        );
      }
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.xs),
    );
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
      onChanged: (value) => setState(() => _transactionType = value),
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
      onChanged: (value) => setState(() => _accountId = value),
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
      onChanged: (value) => setState(() => _categoryId = value),
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
      onChanged: (value) => setState(() => _tagId = value),
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

  void _clearFilters() {
    setState(() {
      _transactionType = null;
      _accountId = null;
      _categoryId = null;
      _tagId = null;
      _dateRange = null;
    });
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

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        formatDate(date),
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class TransactionListRow extends StatelessWidget {
  const TransactionListRow({
    super.key,
    required this.transaction,
    required this.data,
    required this.onTap,
  });

  final Transaction transaction;
  final AppDataSnapshot data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sourceAccount = transaction.sourceAccountId == null
        ? null
        : data.accountsById[transaction.sourceAccountId!];
    final destinationAccount = transaction.destinationAccountId == null
        ? null
        : data.accountsById[transaction.destinationAccountId!];
    final category = transaction.categoryId == null
        ? null
        : data.categoriesById[transaction.categoryId!];
    final tag = transaction.tagId == null
        ? null
        : data.tagsById[transaction.tagId!];

    final detailParts = <String>[
      if (category != null) category.name,
      if (tag != null) tag.name,
      if (transaction.type != TransactionType.transfer &&
          sourceAccount != null &&
          destinationAccount != null)
        '${sourceAccount.name} → ${destinationAccount.name}'
      else if (transaction.type != TransactionType.transfer &&
          sourceAccount != null)
        sourceAccount.name
      else if (transaction.type != TransactionType.transfer &&
          destinationAccount != null)
        destinationAccount.name,
    ];

    return Card(
      clipBehavior: Clip.hardEdge,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: _backgroundColor(context),
          foregroundColor: _foregroundColor(context),
          child: Icon(_icon),
        ),
        title: Text(
          transaction.description.isEmpty
              ? transactionTypeLabel(transaction.type)
              : transaction.description,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          detailParts.isEmpty
              ? transactionTypeLabel(transaction.type)
              : detailParts.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildAmount(context),
      ),
    );
  }

  Widget _transferLine({
    required String accountName,
    required String amount,
    required Color color,
    required TextStyle? style,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            accountName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(amount, style: style?.copyWith(color: color)),
      ],
    );
  }

  Widget _buildAmount(BuildContext context) {
    if (transaction.type == TransactionType.transfer &&
        transaction.sourceAmount != null &&
        transaction.destinationAmount != null) {
      final source = transaction.sourceAccountId == null
          ? null
          : data.accountsById[transaction.sourceAccountId!];
      final destination = transaction.destinationAccountId == null
          ? null
          : data.accountsById[transaction.destinationAccountId!];
      final amountStyle = Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w700);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _transferLine(
              accountName: source?.name ?? 'Source',
              amount:
                  '-${formatMoney(transaction.sourceAmount!, data.currenciesById)}',
              color: Theme.of(context).colorScheme.error,
              style: amountStyle,
            ),
            _transferLine(
              accountName: destination?.name ?? 'Destination',
              amount:
                  '+${formatMoney(transaction.destinationAmount!, data.currenciesById)}',
              color: AppColors.success,
              style: amountStyle,
            ),
          ],
        ),
      );
    }

    final amount = transaction.sourceAmount ?? transaction.destinationAmount;
    if (amount == null) return const Text('—');
    final isExpense = transaction.type == TransactionType.expense;
    final prefix = isExpense ? '-' : '+';
    return Text(
      '$prefix${formatMoney(amount, data.currenciesById)}',
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: isExpense
            ? Theme.of(context).colorScheme.error
            : AppColors.success,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Color _backgroundColor(BuildContext context) {
    final categoryColor = _categoryColor;
    if (categoryColor != null) return categoryColor.withValues(alpha: 0.14);
    return switch (transaction.type) {
      TransactionType.expense => Theme.of(context).colorScheme.errorContainer,
      TransactionType.income => Theme.of(
        context,
      ).colorScheme.secondaryContainer,
      TransactionType.reimbursement => Theme.of(
        context,
      ).colorScheme.tertiaryContainer,
      TransactionType.transfer => Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest,
    };
  }

  Color _foregroundColor(BuildContext context) =>
      _categoryColor ??
      switch (transaction.type) {
        TransactionType.expense => Theme.of(
          context,
        ).colorScheme.onErrorContainer,
        TransactionType.income => Theme.of(
          context,
        ).colorScheme.onSecondaryContainer,
        TransactionType.reimbursement => Theme.of(
          context,
        ).colorScheme.onTertiaryContainer,
        TransactionType.transfer => Theme.of(
          context,
        ).colorScheme.onSurfaceVariant,
      };

  Color? get _categoryColor {
    final category = transaction.categoryId == null
        ? null
        : data.categoriesById[transaction.categoryId!];
    if (category == null) return null;
    final categoryText = '${category.id} ${category.name}'.toLowerCase();
    if (_containsAny(categoryText, ['dining', 'restaurant', 'food', 'meal'])) {
      return const Color(0xFFE76F51);
    }
    if (_containsAny(categoryText, ['shopping', 'groceries', 'clothing'])) {
      return const Color(0xFF7B61FF);
    }
    if (_containsAny(categoryText, ['personal', 'beauty'])) {
      return const Color(0xFFE07A5F);
    }
    if (_containsAny(categoryText, ['transport', 'travel', 'fuel', 'car'])) {
      return const Color(0xFF2A9D8F);
    }
    if (_containsAny(categoryText, ['health', 'medical', 'dental'])) {
      return const Color(0xFFD1495B);
    }
    if (_containsAny(categoryText, ['housing', 'rent', 'home'])) {
      return const Color(0xFF457B9D);
    }
    if (_containsAny(categoryText, ['utilities', 'internet', 'phone'])) {
      return const Color(0xFFF4A261);
    }
    if (_containsAny(categoryText, ['entertainment', 'leisure', 'hobby'])) {
      return const Color(0xFF6A4C93);
    }
    if (_containsAny(categoryText, ['education', 'school', 'course'])) {
      return const Color(0xFF277DA1);
    }
    if (_containsAny(categoryText, ['tax', 'government', 'fee'])) {
      return const Color(0xFF606C38);
    }
    return AppColors.teal;
  }

  IconData get _icon {
    final category = transaction.categoryId == null
        ? null
        : data.categoriesById[transaction.categoryId!];
    if (category != null) {
      final categoryText = '${category.id} ${category.name}'.toLowerCase();
      if (_containsAny(categoryText, [
        'dining',
        'restaurant',
        'food',
        'meal',
      ])) {
        return Icons.restaurant;
      }
      if (_containsAny(categoryText, ['shopping', 'groceries', 'clothing'])) {
        return Icons.shopping_bag;
      }
      if (_containsAny(categoryText, ['personal', 'beauty'])) {
        return Icons.spa;
      }
      if (_containsAny(categoryText, ['transport', 'travel', 'fuel', 'car'])) {
        return Icons.directions_car;
      }
      if (_containsAny(categoryText, ['health', 'medical', 'dental'])) {
        return Icons.health_and_safety;
      }
      if (_containsAny(categoryText, ['housing', 'rent', 'home'])) {
        return Icons.home;
      }
      if (_containsAny(categoryText, ['utilities', 'internet', 'phone'])) {
        return Icons.receipt_long;
      }
      if (_containsAny(categoryText, ['entertainment', 'leisure', 'hobby'])) {
        return Icons.movie;
      }
      if (_containsAny(categoryText, ['education', 'school', 'course'])) {
        return Icons.school;
      }
      if (_containsAny(categoryText, ['tax', 'government', 'fee'])) {
        return Icons.account_balance;
      }
      return Icons.category_outlined;
    }
    return switch (transaction.type) {
      TransactionType.expense => Icons.arrow_upward,
      TransactionType.income => Icons.arrow_downward,
      TransactionType.reimbursement => Icons.replay,
      TransactionType.transfer => Icons.swap_horiz,
    };
  }

  static bool _containsAny(String value, List<String> terms) =>
      terms.any(value.contains);
}

class TransactionDetailsSheet extends StatelessWidget {
  const TransactionDetailsSheet({
    super.key,
    required this.transaction,
    required this.data,
  });

  final Transaction transaction;
  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transaction.description.isEmpty
                    ? transactionTypeLabel(transaction.type)
                    : transaction.description,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(formatDate(transaction.date)),
              const SizedBox(height: AppSpacing.lg),
              _DetailLine(
                label: 'Type',
                value: transactionTypeLabel(transaction.type),
              ),
              _DetailLine(
                label: 'Category',
                value: transaction.categoryId == null
                    ? '—'
                    : data.categoriesById[transaction.categoryId!]?.name ??
                          transaction.categoryId!,
              ),
              _DetailLine(
                label: 'Tag',
                value: transaction.tagId == null
                    ? '—'
                    : data.tagsById[transaction.tagId!]?.name ??
                          transaction.tagId!,
              ),
              const SizedBox(height: AppSpacing.md),
              if (transaction.sourceAccountId != null)
                _DetailLine(
                  label: 'Source',
                  value: _accountAmount(
                    transaction.sourceAccountId!,
                    transaction.sourceAmount,
                  ),
                ),
              if (transaction.destinationAccountId != null)
                _DetailLine(
                  label: 'Destination',
                  value: _accountAmount(
                    transaction.destinationAccountId!,
                    transaction.destinationAmount,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _accountAmount(String accountId, Money? amount) {
    final accountName = data.accountsById[accountId]?.name ?? accountId;
    if (amount == null) return accountName;
    return '$accountName · ${formatMoney(amount, data.currenciesById)}';
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.mutedText),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class EmptyTransactionsState extends StatelessWidget {
  const EmptyTransactionsState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 48,
            color: AppColors.mutedText,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No Transactions Match These Filters.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Try Clearing One or More Filters.'),
        ],
      ),
    );
  }
}
