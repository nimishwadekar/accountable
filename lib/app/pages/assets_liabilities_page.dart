import 'package:flutter/material.dart';

import '../../data/data.dart';
import 'app_pages.dart';
import '../formatters.dart';
import '../theme/design_tokens.dart';

String manualValuationId(DateTime date, String accountId) =>
    '${_dateString(date)}-$accountId';

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
    required this.onValuationAdded,
  });

  final AppDataSnapshot data;
  final Future<void> Function(DailyManualValuation valuation) onValuationAdded;

  @override
  State<AssetsLiabilitiesPage> createState() => _AssetsLiabilitiesPageState();
}

class _AssetsLiabilitiesPageState extends State<AssetsLiabilitiesPage> {
  bool _submitting = false;

  List<Account> get _valuationAccounts => widget.data.visibleAccounts
      .where((account) => account.isValuationAccount)
      .toList();

  @override
  Widget build(BuildContext context) {
    return AppPageFrame(
      title: 'Assets & liabilities',
      subtitle: 'Track manually observed values for loans and investments.',
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
          if (_valuationAccounts.isEmpty)
            const EmptyState(message: 'No asset or liability accounts yet.')
          else
            Card(
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < _valuationAccounts.length;
                    index++
                  ) ...[
                    if (index > 0) const Divider(height: 1),
                    _AccountValuationRow(
                      account: _valuationAccounts[index],
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
      for (final valuation in valuations) {
        await widget.onValuationAdded(valuation);
      }
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

  // Kept for future single-entry correction support.
  // ignore: unused_element
  DailyManualValuation? _submitValuation(
    String? accountId,
    DateTime? date,
    String value,
  ) {
    final account = accountId == null
        ? null
        : widget.data.accountsById[accountId];
    final currency = account == null
        ? null
        : widget.data.currenciesById[account.currencyId];
    if (account == null || currency == null || date == null) return null;
    final normalizedDate = DateTime.utc(date.year, date.month, date.day);
    if (!isManualValuationDateAllowed(
      date: normalizedDate,
      account: account,
      existing: widget.data.dailyManualValuationsById.values,
    )) {
      return null;
    }
    final money = Money.fromMajorUnits(value: value, currency: currency);
    return DailyManualValuation(
      id: manualValuationId(normalizedDate, account.id),
      date: normalizedDate,
      accountId: account.id,
      value: money,
    );
  }
}

class _ValuationForm extends StatefulWidget {
  const _ValuationForm({required this.data, required this.onSubmit});

  final AppDataSnapshot data;
  final DailyManualValuation? Function(
    String? accountId,
    DateTime? date,
    String value,
  )
  onSubmit;

  @override
  State<_ValuationForm> createState() => _ValuationFormState();
}

class _ValuationFormState extends State<_ValuationForm> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  String? _accountId;
  DateTime? _date;
  String? _error;

  List<Account> get _accounts => widget.data.visibleAccounts
      .where((account) => account.isValuationAccount)
      .toList();

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = _accountId == null
        ? null
        : widget.data.accountsById[_accountId!];
    final currency = account == null
        ? null
        : widget.data.currenciesById[account.currencyId];
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
                'Add valuation',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: const InputDecoration(labelText: 'Account'),
                items: [
                  for (final item in _accounts)
                    DropdownMenuItem(
                      value: item.id,
                      child: Text('${item.name} (${item.currencyId})'),
                    ),
                ],
                validator: (value) =>
                    value == null ? 'Select an account.' : null,
                onChanged: (value) {
                  setState(() {
                    _accountId = value;
                    if (_date != null && !_isSelectable(_date!, value)) {
                      _date = null;
                    }
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: account == null ? null : _selectDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_date == null ? 'Select date' : formatDate(_date!)),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _valueController,
                decoration: InputDecoration(
                  labelText: 'Valuation',
                  suffixText: currency?.id,
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a valuation.';
                  }
                  final parsed = num.tryParse(value.trim());
                  if (parsed == null) {
                    return 'Enter a valid valuation.';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _submit,
                child: const Text('Add valuation'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (date) => _isSelectable(date, _accountId),
    );
    if (!mounted || selected == null) return;
    setState(() => _date = selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      setState(() => _error = 'Select a date.');
      return;
    }
    final valuation = widget.onSubmit(_accountId, _date, _valueController.text);
    if (valuation == null) {
      setState(
        () => _error = 'That date already has a valuation or is invalid.',
      );
      return;
    }
    Navigator.of(context).pop(valuation);
  }

  bool _isSelectable(DateTime date, String? accountId) {
    if (accountId == null) return true;
    final account = widget.data.accountsById[accountId];
    if (account == null) return false;
    return isManualValuationDateAllowed(
      date: date,
      account: account,
      existing: widget.data.dailyManualValuationsById.values,
    );
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
                'Add daily valuations',
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
                  child: const Text('Save valuations'),
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
        helperText:
            '${account.accountType} · ${currency?.id ?? account.currencyId}',
        suffixText: currency?.id,
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Enter a valuation.';
        }
        final parsed = num.tryParse(value.trim());
        return parsed == null ? 'Enter a valid value.' : null;
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
      final value = Money.fromMajorUnits(
        value: _controllers[account.id]!.text.trim(),
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

class _AccountValuationRow extends StatelessWidget {
  const _AccountValuationRow({required this.account, required this.data});

  final Account account;
  final AppDataSnapshot data;

  @override
  Widget build(BuildContext context) {
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
    final valueColor = latest == null
        ? null
        : latest.value.minorUnits > 0
        ? AppColors.success
        : latest.value.minorUnits < 0
        ? Theme.of(context).colorScheme.error
        : null;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
        foregroundColor: AppColors.navy,
        child: const Icon(Icons.account_balance_wallet_outlined),
      ),
      title: Text(account.name),
      subtitle: Text(accountSubtitle(account, data.currenciesById)),
      trailing: Text(
        latest == null || currency == null
            ? '—'
            : formatMoney(latest.value, data.currenciesById),
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: valueColor, fontWeight: FontWeight.w700),
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
