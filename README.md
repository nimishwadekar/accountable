# accountable

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

The app reads its runtime settings from the committed [`assets/config.json`](./assets/config.json) asset. Update that file to switch between local CSV data and Google Sheets, then restart the app.

```json
{
  "dataSource": "sheets",
  "googleClientId": "YOUR_WEB_CLIENT_ID.apps.googleusercontent.com",
  "spreadsheetId": "YOUR_SPREADSHEET_ID",
  "allowedEmail": "YOUR_EMAIL@example.com",
  "oauthOrigin": "http://localhost:9000",
  "sheetsScope": "https://www.googleapis.com/auth/spreadsheets"
}
```

Set `dataSource` to `"csv"` for local fixture mode. The web client ID and spreadsheet ID are not secrets; OAuth access tokens are never stored in this file.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
