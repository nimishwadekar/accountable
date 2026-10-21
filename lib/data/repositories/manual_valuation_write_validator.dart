import '../app_data_snapshot.dart';
import '../models/models.dart';

List<String> validateManualValuationsForWrite(
  Iterable<DailyManualValuation> valuations,
  AppDataSnapshot data,
) {
  final errors = <String>[];
  final knownIds = data.dailyManualValuationsById.keys.toSet();
  final knownAccountDates = <String>{
    for (final valuation in data.dailyManualValuations)
      '${valuation.accountId}:${_dateKey(valuation.date)}',
  };

  for (final valuation in valuations) {
    if (!knownIds.add(valuation.id)) {
      errors.add('Duplicate valuation ID: ${valuation.id}.');
    }
    final account = data.accountsById[valuation.accountId];
    if (account == null) {
      errors.add('Unknown valuation account: ${valuation.accountId}.');
      continue;
    }
    if (!account.isValuationAccount) {
      errors.add('Account ${account.id} does not use manual valuations.');
    }
    if (valuation.value.currencyId != account.currencyId) {
      errors.add(
        'Valuation currency ${valuation.value.currencyId} does not match '
        'account currency ${account.currencyId}.',
      );
    }
    if (account.isLiability && valuation.value.minorUnits > 0) {
      errors.add('Liability valuations must be stored as negative values.');
    }
    if (!account.isLiability && valuation.value.minorUnits < 0) {
      errors.add('Asset valuations cannot be negative.');
    }
    final date = _dateOnly(valuation.date);
    if (date.isBefore(_dateOnly(account.openingDate))) {
      errors.add('Valuation date is before account ${account.id} opened.');
    }
    if (account.closingDate != null &&
        date.isAfter(_dateOnly(account.closingDate!))) {
      errors.add('Valuation date is after account ${account.id} closed.');
    }
    final key = '${account.id}:${_dateKey(date)}';
    if (!knownAccountDates.add(key)) {
      errors.add('Duplicate valuation for ${account.id} on ${_dateKey(date)}.');
    }
  }

  return errors;
}

DateTime _dateOnly(DateTime value) => DateTime.utc(value.year, value.month, value.day);

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
