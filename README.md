# Accountable

Accountable is a mobile-first Flutter web app backed by Google Sheets.

## Configuration

The app reads runtime settings from the committed [`assets/config.json`](./assets/config.json) asset. Set `dataSource` to `"csv"` for local fixture mode or `"sheets"` for Google Sheets mode, then restart the app.

`oauthOrigin` is the production GitHub Pages origin. `additionalOauthOrigins` keeps the local development origin available. Add both origins as authorized JavaScript origins for the Google OAuth client.

Set `migration_assistance` to `true` to append the read-only Migration Assistance tab. It requires a `TransactionsToMigrate` sheet (or bundled CSV fixture) with the same columns as `Transactions`.

The web client ID and spreadsheet ID are not secrets; OAuth access tokens are never stored in this file.

## Daily history Sheets

Google Sheets mode requires a `Metadata` sheet with `metadata_key,metadata_value` headers and a `daily_processed_through` date containing the last fully processed day. Daily maintenance reports an error if that checkpoint is missing; set it to the latest date covered by all three daily history sheets before connecting.

The `DailyAccountBalances` sheet uses `balance_id,balance_date,account_id,balance,retrieved_at`; remove the old `balance_usd` column and place `retrieved_at` in column E. USD balances are calculated from the native balance and the applicable exchange rate. Daily exchange rates, account balances, and net worth are stored as change points; readers carry the last value forward through the metadata checkpoint. Use **Settings → Rebuild daily tables** to compact existing dense history.

## Local development

```bash
/Users/nwadekar/flutter/bin/flutter pub get
/Users/nwadekar/flutter/bin/flutter run -d chrome --web-port 9000
```

## GitHub Pages deployment

A push to `main` runs [`.github/workflows/deploy-pages.yml`](./.github/workflows/deploy-pages.yml) and publishes the app at:

`https://nimishwadekar.github.io/accountable/`

Before the first deployment:

1. In the repository’s **Settings → Pages**, select **GitHub Actions** as the source.
2. In Google Cloud OAuth client settings, add `https://nimishwadekar.github.io` and `http://localhost:9000` as authorized JavaScript origins.
3. Confirm the Google OAuth client allows the deployed site to use the configured Sheets scope.

The workflow builds with `/accountable/` as the Flutter web base path. The `oauthOrigin` value must contain only the origin, not `/accountable/`.
