const TABLE_NAMES = [
  'Accounts',
  'Categories',
  'Currencies',
  'DailyAccountBalances',
  'DailyExchangeRates',
  'DailyNetWorth',
  'DailyManualValuations',
  'DisplayPreferences',
  'Tags',
  'Transactions',
];

function doGet(event) {
  const action = (event && event.parameter && event.parameter.action) || 'hello';
  try {
    if (action !== 'hello') throw new Error('Use POST for authenticated actions.');
    return jsonResponse({
      ok: true,
      message: 'Accountable Apps Script endpoint is reachable.',
    });
  } catch (error) {
    return jsonResponse({ ok: false, error: errorMessage(error) });
  }
}

function doPost(event) {
  try {
    const request = JSON.parse(event.postData.contents);
    validateIdToken(request.idToken);
    switch (request.action) {
      case 'loadSnapshot':
        return jsonResponse(loadSnapshot());
      case 'appendDisplayPreference':
        return jsonResponse(appendDisplayPreference(request.row));
      default:
        throw new Error('Unsupported action.');
    }
  } catch (error) {
    return jsonResponse({ ok: false, error: errorMessage(error) });
  }
}

function errorMessage(error) {
  return String(error && error.message ? error.message : error);
}

function validateIdToken(idToken) {
  if (!idToken) throw new Error('Missing Google ID token.');
  const response = UrlFetchApp.fetch(
    'https://oauth2.googleapis.com/tokeninfo?id_token=' + encodeURIComponent(idToken),
    { muteHttpExceptions: true },
  );
  if (response.getResponseCode() !== 200) throw new Error('Invalid Google ID token.');
  const claims = JSON.parse(response.getContentText());
  const expectedClientId = PropertiesService.getScriptProperties()
    .getProperty('GOOGLE_CLIENT_ID');
  const expectedEmail = PropertiesService.getScriptProperties()
    .getProperty('ALLOWED_EMAIL');
  if (!expectedClientId || !expectedEmail) {
    throw new Error('Missing GOOGLE_CLIENT_ID or ALLOWED_EMAIL script property.');
  }
  if (claims.aud !== expectedClientId) throw new Error('Invalid token audience.');
  if (claims.iss !== 'https://accounts.google.com' && claims.iss !== 'accounts.google.com') {
    throw new Error('Invalid token issuer.');
  }
  if (claims.email !== expectedEmail || claims.email_verified !== 'true') {
    throw new Error('Google account is not authorized.');
  }
  if (Number(claims.exp) <= Math.floor(Date.now() / 1000)) {
    throw new Error('Google ID token has expired.');
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
  TABLE_NAMES.forEach(function (tableName) {
    const sheet = spreadsheet.getSheetByName(tableName);
    if (!sheet) throw new Error('Missing sheet: ' + tableName);
    tables[tableName] = sheet.getDataRange().getDisplayValues();
  });
  return { ok: true, tables: tables };
}

function appendDisplayPreference(row) {
  const spreadsheetId = PropertiesService.getScriptProperties()
    .getProperty('SPREADSHEET_ID');
  if (!spreadsheetId) throw new Error('Missing SPREADSHEET_ID script property.');
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
