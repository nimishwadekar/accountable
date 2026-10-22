import 'package:flutter/material.dart';

import '../../data/data.dart';
import 'app_pages.dart';
import 'account_visuals.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';

String manualValuationId(DateTime date, String accountId) =>
    '${_dateString(date)}-$accountId';

String _displayAccountType(Account account) {
  if (account.isLiability) return AccountType.liability.displayName;
  return account.accountTypeKind.displayName;
}

DateTime defaultManualValuationDate(AppDataSnapshot data) {
  final dates =
      data.dailyManualValuationsById.values
          .map((valuation) => valuation.date)
          .toList()
        ..sort();
  final latest = dates.isEmpty ? DateTime.now() : dates.last;
  return DateTime.utc(
    latest.year,
    latest.month,
    latest.day,
  ).add(const Duration(days: 1));
}

List<Account> eligibleManualValuationAccounts(
  AppDataSnapshot data,
  DateTime date,
) {
  return data.visibleAccounts.where((account) {
    if (!account.isValuationAccount) return false;
    if (date.isBefore(account.openingDate)) return false;
    if (account.closingDate != null && date.isAfter(account.closingDate!)) {
      return false;
    }
    return !data.dailyManualValuationsById.values.any(
      (valuation) =>
          valuation.accountId == account.id && _sameDate(valuation.date, date),
    );
  }).toList();
}

bool isManualValuationDateAllowed({
  required DateTime date,
  required Account account,
  required Iterable<DailyManualValuation> existing,
}) {
  final normalized = DateTime.utc(date.year, date.month, date.day);
  final opening = DateTime.utc(
    account.openingDate.year,
    account.openingDate.month,
    account.openingDate.day,
  );
  final closing = account.closingDate == null
      ? null
      : DateTime.utc(
          account.closingDate!.year,
          account.closingDate!.month,
          account.closingDate!.day,
        );
  if (normalized.isBefore(opening)) return false;
  if (closing != null && normalized.isAfter(closing)) return false;
  return !existing.any(
    (valuation) =>
        valuation.accountId == account.id &&
        _sameDate(valuation.date, normalized),
  );
}

class AssetsLiabilitiesPage extends StatefulWidget {
  const AssetsLiabilitiesPage({
    super.key,
    required this.data,
    required this.onValuationsAdded,
  });

  final AppDataSnapshot data;
  final Future<void> Function(List<DailyManualValuation> valuations)
  onValuationsAdded;

  @override
  State<AssetsLiabilitiesPage> createState() => _AssetsLiabilitiesPageState();
}

class _AssetsLiabilitiesPageState extends State<AssetsLiabilitiesPage> {
  bool _submitting = false;

  List<Account> get _assetLiabilityAccounts => widget.data.visibleAccounts
      .where((account) => account.accountTypeKind != AccountType.cash)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AppPageFrame(
      title: 'Assets & Liabilities',
      subtitle: 'View current assets and liabilities; add manual valuations for accounts that use them.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _openAddValuation,
              icon: const Icon(Icons.add),
              label: const Text('Add valuation'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_assetLiabilityAccounts.isEmpty)
            const EmptyState(message: 'No Asset or Liability accounts yet.')
          else
            Card(
              clipBehavior: Clip.hardEdge,
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < _assetLiabilityAccounts.length;
                    index++
                  ) ...[
                    if (index > 0) const Divider(height: 1),
                    _AssetLiabilityRow(
                      account: _assetLiabilityAccounts[index],
                      data: widget.data,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openAddValuation() async {
    final valuations = await showModalBottomSheet<List<DailyManualValuation>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DailyValuationsForm(data: widget.data),
    );
    if (!mounted || valuations == null || valuations.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await widget.onValuationsAdded(valuations);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Valuations added.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add valuations: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _DailyValuationsForm extends StatefulWidget {
  const _DailyValuationsForm({required this.data});

  final AppDataSnapshot data;

  @override
  State<_DailyValuationsForm> createState() => _DailyValuationsFormState();
}

class _DailyValuationsFormState extends State<_DailyValuationsForm> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _date = defaultManualValuationDate(widget.data);
  final Map<String, TextEditingController> _controllers = {};

  List<Account> get _eligibleAccounts =>
      eligibleManualValuationAccounts(widget.data, _date);

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _eligibleAccounts;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add Daily Valuations',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('For ${formatDate(_date)}'),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _selectDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(formatDate(_date)),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (accounts.isEmpty)
                const EmptyState(
                  message: 'No accounts need a valuation on this date.',
                )
              else
                for (final account in accounts) ...[
                  _valuationField(account),
                  const SizedBox(height: AppSpacing.md),
                ],
              if (accounts.isNotEmpty)
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Save Valuations'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _valuationField(Account account) {
    final controller = _controllers.putIfAbsent(
      account.id,
      TextEditingController.new,
    );
    final currency = widget.data.currenciesById[account.currencyId];
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: account.name,
        filled: true,
        fillColor: account.isLiability
            ? AppColors.danger.withValues(alpha: 0.06)
            : AppColors.success.withValues(alpha: 0.06),
        helperText:
            '${_displayAccountType(account)} · ${currency?.id ?? account.currencyId}',
        suffixText: currency?.id,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter a valuation.';
        }
        final parsed = num.tryParse(value.trim());
        return parsed == null || !parsed.isFinite || parsed < 0
            ? 'Enter a non-negative valuation.'
            : null;
      },
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
    setState(() {
      _date = DateTime.utc(selected.year, selected.month, selected.day);
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final valuations = <DailyManualValuation>[];
    for (final account in _eligibleAccounts) {
      final currency = widget.data.currenciesById[account.currencyId]!;
      final rawValue = _controllers[account.id]!.text.trim();
      final enteredValue = account.isLiability && !rawValue.startsWith('-')
          ? '-$rawValue'
          : rawValue;
      final value = Money.fromMajorUnits(
        value: enteredValue,
        currency: currency,
      );
      valuations.add(
        DailyManualValuation(
          id: manualValuationId(_date, account.id),
          date: _date,
          accountId: account.id,
          value: value,
        ),
      );
    }
    Navigator.of(context).pop(valuations);
  }
}

class _AssetLiabilityRow extends StatelessWidget {
  const _AssetLiabilityRow({required this.account, required this.data});

  final Account account;
  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
    final balances = const AccountBalanceCalculator().calculate(
      accounts: data.accounts,
      transactions: data.transactions,
    );
    final latest = data.dailyManualValuationsById.values
        .where((valuation) => valuation.accountId == account.id)
        .fold<DailyManualValuation?>(
          null,
          (current, valuation) =>
              current == null || valuation.date.isAfter(current.date)
              ? valuation
              : current,
        );
    final currency = data.currenciesById[account.currencyId];
    final value = account.isValuationAccount
        ? latest?.value
        : balances[account.id];
    final valueColor = value == null
        ? null
        : value.minorUnits > 0
        ? AppColors.success
        : value.minorUnits < 0
        ? Theme.of(context).colorScheme.error
        : null;
    return Container(
      color: accountTypeColor(account).withValues(alpha: 0.06),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: CircleAvatar(
          backgroundColor: accountTypeColor(account).withValues(alpha: 0.14),
          foregroundColor: accountTypeColor(account),
          child: AccountVisualIcon(account: account, currencies: data.currenciesById),
        ),
        title: Text(account.name),
        subtitle: Text(accountSubtitle(account, data.currenciesById)),
        trailing: Text(
          value == null || currency == null
              ? '—'
              : formatMoney(value, data.currenciesById),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: valueColor, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
