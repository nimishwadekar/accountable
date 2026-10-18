const TABLE_RANGES = {
  Accounts: 'A:H',
  Categories: 'A:C',
  Currencies: 'A:C',
  DailyAccountBalances: 'A:F',
  DailyExchangeRates: 'A:F',
  DailyNetWorth: 'A:D',
  DailyManualValuations: 'A:D',
  DisplayPreferences: 'A:E',
  Tags: 'A:B',
  Transactions: 'A:K',
};

function doGet(event) {
  const action = (event && event.parameter && event.parameter.action) || 'hello';
  try {
    switch (action) {
      case 'hello':
        return jsonResponse({
          ok: true,
          message: 'Accountable Apps Script endpoint is reachable.',
        });
      case 'loadSnapshot':
        return jsonResponse(loadSnapshot());
      case 'appendDisplayPreference':
        return jsonResponse(appendDisplayPreference(event));
      default:
        throw new Error('Unsupported action.');
    }
  } catch (error) {
    return jsonResponse({
      ok: false,
      error: String(error && error.message ? error.message : error),
    });
  }
}

function loadSnapshot() {
  const spreadsheetId = PropertiesService.getScriptProperties()
    .getProperty('SPREADSHEET_ID');
  if (!spreadsheetId) {
    throw new Error('Missing SPREADSHEET_ID script property.');
  }

  const spreadsheet = SpreadsheetApp.openById(spreadsheetId);
  const tables = {};
  Object.keys(TABLE_RANGES).forEach(function (tableName) {
    const sheet = spreadsheet.getSheetByName(tableName);
    if (!sheet) throw new Error('Missing sheet: ' + tableName);
    const range = sheet.getRange(TABLE_RANGES[tableName]);
    tables[tableName] = range.getDisplayValues();
  });
  return { ok: true, tables: tables };
}

function appendDisplayPreference(event) {
  const spreadsheetId = PropertiesService.getScriptProperties()
    .getProperty('SPREADSHEET_ID');
  if (!spreadsheetId) throw new Error('Missing SPREADSHEET_ID script property.');
  const rawRow = event && event.parameter && event.parameter.row;
  const row = rawRow ? JSON.parse(rawRow) : null;
  if (!Array.isArray(row) || row.length !== 5) {
    throw new Error('Display preference row must contain five values.');
  }
  const spreadsheet = SpreadsheetApp.openById(spreadsheetId);
  const sheet = spreadsheet.getSheetByName('DisplayPreferences');
  if (!sheet) throw new Error('Missing sheet: DisplayPreferences');
  sheet.appendRow(row);
  return { ok: true };
}

function jsonResponse(value) {
  return ContentService
    .createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}
