import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionUiPreferences {
  SessionUiPreferences._();

  static final instance = SessionUiPreferences._();
  static const _storageKey = 'accountable.session_ui_preferences.v1';

  String? analysisAccountId;
  String? analysisAccountUnit;
  String? netWorthRangePreset;
  String? accountRangePreset;
  String? analysisMonth;
  String? analysisTagId;
  String? transactionType;
  String? transactionAccountId;
  String? transactionCategoryId;
  String? transactionTagId;
  String? transactionDateStart;
  String? transactionDateEnd;

  Future<void> startSession() async {
    analysisAccountId = null;
    analysisAccountUnit = null;
    netWorthRangePreset = null;
    accountRangePreset = null;
    analysisMonth = null;
    analysisTagId = null;
    transactionType = null;
    transactionAccountId = null;
    transactionCategoryId = null;
    transactionTagId = null;
    transactionDateStart = null;
    transactionDateEnd = null;
    try {
      await SharedPreferencesAsync().remove(_storageKey);
    } on StateError {
      // Browser storage is unavailable in pure widget-test environments.
    }
  }

  Future<void> persist() async {
    final values = <String, String>{};
    void add(String key, String? value) {
      if (value != null) values[key] = value;
    }

    add('analysis_account_id', analysisAccountId);
    add('analysis_account_unit', analysisAccountUnit);
    add('net_worth_range_preset', netWorthRangePreset);
    add('account_range_preset', accountRangePreset);
    add('analysis_month', analysisMonth);
    add('analysis_tag_id', analysisTagId);
    add('transaction_type', transactionType);
    add('transaction_account_id', transactionAccountId);
    add('transaction_category_id', transactionCategoryId);
    add('transaction_tag_id', transactionTagId);
    add('transaction_date_start', transactionDateStart);
    add('transaction_date_end', transactionDateEnd);
    try {
      await SharedPreferencesAsync().setString(_storageKey, jsonEncode(values));
    } on StateError {
      // Browser storage is unavailable in pure widget-test environments.
    }
  }
}
