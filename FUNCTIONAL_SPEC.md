# Accountable functional specification

This document is the functional source of truth for Accountable. It describes intended behavior, business rules, data-loading behavior, algorithms, and acceptance criteria. It should be updated whenever functionality changes.

Status labels:

- **Implemented:** present in the current app.
- **Planned:** agreed behavior not implemented yet.
- **Deferred:** intentionally out of scope for the current phase.

## Product scope

Accountable is a mobile-first Flutter web app for a single user. Google Sheets is the planned production data source. Local CSV fixtures are used for development and tests.

The app supports transaction entry, financial balances, historical daily analysis, and future budgeting.

## Data sources

### Local CSV mode — implemented

- CSV fixtures are bundled from [`test_sheets/`](./test_sheets/).
- The asset repository loads the runtime tables into an immutable snapshot.
- Local Chrome mode can persist the complete dataset in browser storage for transaction-entry testing.
- Bundled CSV assets remain read-only.
- Local CSV mode is selected from the committed [`assets/config.json`](./assets/config.json) asset.

### Google Sheets mode — partially implemented

Google Sheets will be the default production data source.

- Direct Google OAuth and Google Sheets API.
- No Firebase services.
- OAuth development origin is loaded from the committed [`assets/config.json`](./assets/config.json) asset.
- Only the configured Google account is authorized.
- Only the Sheets read/write scope is requested; Drive access is not requested.
- The spreadsheet ID, allowed-email value, client ID, OAuth origin, and scope live in checked-in, non-secret configuration.
- Editing and deletion are deferred; appending transactions is supported first.

## Daily manual valuations — planned

Add a `DailyManualValuations` table for externally observed asset and liability balances:

```text
valuation_id,date,account_id,value
```

The account's currency is inferred from `Accounts.currency`. The account's `account_type` determines whether its balance is valuation-derived.

For now:

- `cash` and `credit` accounts use transaction-derived balances.
- `asset` and `liability` accounts use `DailyManualValuations`.
- The Assets & liabilities app section lists only accounts with `uses_manual_valuations=TRUE`.
- `Accounts.account_type` values are `cash`, `liability`, or `asset`; `uses_manual_valuations=TRUE` is valid only for `asset` or `liability` accounts.
- `uses_manual_valuations` accepts Google Sheets boolean output (`TRUE`/`FALSE`, including normalized casing) and rejects other values.
- Valuation dates use the user's local calendar timezone for every account.
- The valuation form order is account, date, valuation.
- The valuation is entered in the selected account's currency.
- Daily valuation batch saves are all-or-nothing; blank, malformed, negative, duplicate, or out-of-range values prevent the entire batch from saving.
- Manual valuation values are stored with their actual sign in Sheets; liability values are negative and displayed negative without additional sign inversion.
- Duplicate account/date valuation entries are prevented.
- Dates before an account's opening date and after its closing date are disabled.
- Existing account/date valuation dates are disabled.
- If account selection changes and the selected date becomes invalid or duplicated, the date is cleared.
- If a valuation is missing on a date, carry forward the latest prior valuation and mark it stale.
- `DailyAccountBalances` remains limited to open `cash` and `credit` accounts.
- `DailyNetWorth` combines ledger-derived balances with manual valuations for `asset` and `liability` accounts.
- Future UI work may color-code positive account classes (`cash`, `asset`) and negative account classes (`liability`) and show explanatory subtext.
- Transfer account-type pairs are allowed without validation restrictions; transfer interpretation will be designed when transfer analysis is implemented.

## Account schema and ledger balance

`Accounts` now contains:

```text
account_id,name,account_type,currency,opening_balance,opening_date,closing_date,uses_manual_valuations
```

- `account_type` is `cash`, `liability`, or `asset`.
- `uses_manual_valuations` is case-sensitive `TRUE` or `FALSE`.
- Manual valuation accounts must have `opening_balance=0`.
- Current ledger balances are calculated from opening balances plus transaction effects.
- `current_balance` is not stored in Accounts.

## Runtime table schemas

Current column order is part of the Sheets/CSV contract:

```text
Currencies: currency_id, currency_symbol, decimal_places
Transactions: transaction_id, date, description, category, transaction_type, source_amount, source_account_id, dest_amount, dest_account_id, tag, created_at
DailyExchangeRates: rate_id, rate_date, currency, rate_to_usd, source_rate_date, retrieved_at
DailyManualValuations: valuation_id, date, account_id, value
DisplayPreferences: entity_type, entity_id, display_order, show_in_app, show_in_entry_forms
```

`source_rate_date` records the actual Frankfurter date used when the requested sequential rate date fell on a weekend or holiday. Legacy local data without this column is read compatibly by treating `rate_date` as the source date. Google Sheets serial-number dates are normalized to calendar dates before freshness checks and parsing.

The runtime data snapshot contains:

- Accounts
- Categories
- Currencies
- Tags
- Transactions
- DailyExchangeRates
- DailyAccountBalances
- DailyNetWorth
- DailyManualValuations
- DisplayPreferences

`TransactionTypes.csv` is not runtime data. Transaction types and their validation rules are defined in Dart.

## Transaction model

### Supported transaction types

The first version supports:

- `expense`
- `income`
- `reimbursement`
- `transfer`

The rules are extensible so future transaction types can define their own requirements.

### Required sides

| Type | Source account and amount | Destination account and amount | Category |
|---|---|---|---|
| Expense | Required | Empty | Required |
| Income | Empty | Required | Optional |
| Reimbursement | Empty | Required | Required |
| Transfer | Required | Required | Empty |

Missing values are represented as `null` in Dart. A numeric zero remains distinct from a missing value.

### Entry-only requirements

New transactions entered through the app require:

- A manually selected transaction date.
- A non-empty description.
- A selected tag.
- Valid required account and amount sides.
- A valid category when required by the transaction type.

Existing legacy rows may have blank descriptions or tags while migration is pending. Parsing legacy data is less strict than validating new entries.

### Timestamps and dates

- `created_at` is generated automatically using the current UTC timestamp.
- New timestamps use ISO 8601 with a `Z` suffix.
- The transaction `date` is selected manually by the user and represents a local calendar date.
- The transaction date is never inferred from `created_at`.
- `created_at` is not displayed in the UI.

### IDs and currencies

- New transaction IDs are unique 12-character base62 values generated by the app.
- The generator checks all existing transaction IDs and regenerates on collision.
- Existing transaction IDs from imported or historical data are preserved unchanged.
- Category and tag values use stable keys.
- Each account has one currency; selecting an account determines the currency for that side.
- Cross-currency transfers store separately entered source and destination amounts.
- A transfer-specific exchange-rate field is not required initially.

### Monetary arithmetic

- Monetary values are stored internally as integer minor units.
- Currency metadata defines decimal places.
- Exchange rates use decimal arithmetic.
- Preserve the full exchange rate during calculations.
- Round only the final converted monetary result to the target currency's minor unit.

## Navigation and screen behavior

### Responsive shell — implemented

- Dashboard/Overview is the initial section.
- Compact widths use a bottom `NavigationBar`.
- Wider layouts use a `NavigationRail`; extended widths show labels.
- Sections are Overview, Transactions, Accounts, Analysis, and Settings.
- Loading and data-load error states are displayed before the main content.

### Overview — implemented

The Overview page shows:

- Amounts use currency symbols with a separating space and thousands separators.
- Main positive amounts are green and main negative amounts are red.
- Menu labels and screen titles use title capitalization.
- Chart x-axis labels use `dd-MMM` dates; y-axis labels and tooltips use grouped amounts.
- Chart limits are not labeled; positive/negative lines and tooltip foregrounds use green/red by value.
- Positive main amounts are green; negative main amounts are red.
- Current Account Balances excludes manual valuation accounts.
- A Latest Assets & Liabilities Valuation section appears after current account balances with an as-of subtitle.
- Individual valuation rows do not repeat the section-level as-of subtitle.

1. Latest daily net worth.
2. An `As of YYYY-MM-DD` subtitle for that net-worth value.
3. `Unavailable` when no daily net-worth row exists; no fallback estimate is calculated.
4. Current account balances calculated from `Accounts.opening_balance` plus all transactions.
5. A label explaining that account values are current ledger balances through the latest transaction.

The Overview page does not currently show current-month spending, income, category totals, charts, or recent transactions as headline content.

### Transactions — implemented

- Shows all transactions by default, newest first.
- Groups rows by manually assigned transaction date.
- Does not display `created_at`.
- Compact rows show description, amount, category/tag, and account information.
- Transfers show both source and destination sides.
- Mobile filters use a bottom sheet.
- Desktop filters appear inline.
- Date ranges include both start and end dates.
- Filters include date range, type, account, category, and tag.
- A scroll-to-top action appears after scrolling down.
- Tapping a row opens read-only details.
- Editing and deletion are deferred.
- The Transactions page has the Add Transaction action; other sections do not currently have it.

### Transaction entry — implemented

- One Add Transaction action opens a type chooser.
- The chooser uses a bottom sheet on compact widths and a dialog on desktop.
- One shared form supports all four transaction types.
- Description appears at the top of the form and is mandatory.
- Date defaults to today's local date but remains editable.
- Tag is mandatory and selected from existing Tags data.
- New tags are currently added in Sheets rather than from the form.
- Successful submission returns to the list and shows confirmation feedback.
- Local mode persists the complete test dataset in browser storage.

Specialized quick-entry forms may later reuse the same transaction builder and validation rules.

### Assets & liabilities — implemented

The Assets & liabilities page lists only `asset` and `liability` accounts and provides an Add valuation action.

The form order is:

1. Account
2. Date
3. Valuation

The date picker disables dates before opening, after closing, or already used for that account. Liability values are entered as positive amounts and signed negatively only during net-worth calculation.

### Accounts — implemented

Shows account rows with:

- Account name
- Account type
- Current ledger balance
- Account currency formatting

### Analysis — implemented

The first Analysis page contains:

- Manual valuation accounts use DailyManualValuations for individual history charts.
- Graph ranges begin at the first transaction date and end yesterday, both inclusive.
- Liability valuation signs are preserved from the source data.
- Chart tooltips use a light theme-compatible background.

- Net-worth history from `DailyNetWorth`.
- Selectable account history from `DailyAccountBalances`.
- Native-currency account values by default.
- A USD toggle using `balance_usd`.
- Date presets: 30 days, 90 days, year-to-date, and all history.
- All history as the initial selection.
- Inclusive calendar-date ranges.
- Missing-data warnings above affected charts.
- Interactive line charts using `fl_chart`.

Analysis uses daily tables, never current ledger calculations, for historical charts.

For closed accounts:

- The account series ends on `closing_date`, inclusive.
- Dates after closing are not considered missing.
- The chart subtitle indicates `Closed on YYYY-MM-DD`.

### Settings — partially implemented

Settings currently contains:

- A confirmed full rebuild action for derived daily tables when connected to Google Sheets.
- Rebuild progress and success/error feedback.

Future Settings work:

- Google account status and sign-out.
- Data-source status.
- Manual reload actions.

## Algorithms and business rules

### Inclusive date range

For a date-only range:

```text
include transaction or daily point when:
  date >= startDate AND date <= endDate
```

Comparisons normalize values to calendar dates so time-of-day and timezone offsets do not exclude boundary dates.

### Current net worth

The Overview value is:

```text
latest DailyNetWorth row by net_worth_date
```

If no row exists, display `Unavailable`.

### Current account balance display

The Overview account value is calculated as:

```text
Accounts.opening_balance + all transaction effects
```

This is intentionally different from historical daily account snapshots. It reflects the ledger through the latest transaction.

### Historical account balance

Analysis uses:

```text
DailyAccountBalances.balance       // native currency
DailyAccountBalances.balance_usd   // USD toggle
```

It does not use current ledger calculations for historical values.

### Global history start date

The global analysis and daily-table start date is the earliest `Transactions.date` currently present. This is the cutover date for the current dataset and expands backward automatically as older transactions are migrated.

- `Accounts.opening_date` does not determine the global analysis or graph period.
- Manual valuations dated before the earliest transaction date are ignored for daily net-worth construction.
- Account opening/closing dates still determine whether an account is eligible on an individual daily date.
- The current `opening_balance` is the account balance at the cutover/start of the current transaction history.
- During initial cutover, account opening dates may be set to the global transaction cutoff date; migration can move them earlier as historical transactions are added.

## Daily table inclusion rules

- Add exchange rates only for currencies used by at least one account open on that date.
- Add daily account balances only for accounts open on that date.
- An account is open when `opening_date <= date` and either `closing_date` is empty or `date <= closing_date`.
- Rebuilds apply the same rules, replacing any stale rows for closed accounts or unused currencies.

### Missing daily data

For a requested date range:

1. Enumerate every calendar date inclusively.
2. Collect the dates present in the relevant daily table.
3. Report dates present in the requested range but absent from the table.
4. Do not carry values forward or interpolate.
5. Display a warning above the affected chart.

Closed account ranges stop at the closing date before missing-date detection.

### Chart x-axis

Charts use the actual day offset from the first point/date as the x-coordinate rather than the point’s list index. This preserves gaps.

Label intervals adapt to chart width and date span using sensible day intervals such as:

```text
1, 2, 3, 5, 7, 14, 21, 30, 60, 90, 120, 180, 365, ...
```

The goal is readable labels without repeated or overcrowded dates.

### Spending — planned

Spending will be defined as:

```text
expenses - reimbursements
```

Reimbursements are not a separate headline metric.

Detailed current-month totals, income totals, category breakdowns, and period comparisons are deferred until their currency-conversion and presentation rules are finalized.

### Currency conversion — planned for detailed analysis

The intended rule is to convert each transaction using the exchange rate for its transaction date. The full rate is preserved and only the final display amount is rounded.

Missing-rate fallback:

1. Query the requested date.
2. If unavailable, use the most recent prior available rate.
3. Keep the requested sequential date on the generated daily row.

## Google Sheets startup lifecycle — implemented

OAuth configuration, account gating, the Sheets-backed runtime repository, and daily catch-up are implemented.

### Authentication refinement — implemented

- Wait up to 3 seconds for silent browser-session restoration before showing interactive sign-in.
- Attempt Sheets-scope authorization silently after account restoration.
- Combine account restoration and Sheets authorization as early as the platform permits.
- Provide explicit account switching/sign-out.
- Show state-specific messages for restoration, sign-in, Sheets consent, data loading, unauthorized accounts, and configuration errors.

Expired-token retry remains a follow-up integration task.

Normal production startup will be:

1. Attempt silent Google OAuth.
2. If needed, show interactive Google sign-in/consent.
3. Validate the returned account against the configured allowed email.
4. Reject unauthorized accounts before any Sheets request.
5. Query only daily date columns using a batch request.
6. Compare stored daily dates with yesterday in the user's local calendar.
7. If current through yesterday, skip catch-up writes.
8. Otherwise catch up sequentially:
   - DailyExchangeRates
   - DailyAccountBalances
   - DailyNetWorth
9. Reload the runtime tables.
10. Show the main app only after the initial snapshot is consistent.

Catch-up is idempotent:

- Daily row IDs are deterministic.
- Existing IDs are checked before insertion, not only the latest date.
- Concurrent startup connection/catch-up attempts are guarded so only one runs per app instance.
- If a failure occurs partway through, completed rows remain and the next launch retries from each table's latest date.
- UTC is used for retrieval timestamps; daily dates use the user's local calendar date.

## Google Sheets writes — partially implemented

- New transactions append one row through the Sheets-backed repository.
- After appending, the repository reloads the full Transactions table as the initial strategy.
- Editing and deletion are deferred.
- Manual full rebuild is available from Settings after explicit confirmation.
- Full rebuild replaces all rows in `DailyExchangeRates`, `DailyAccountBalances`, and `DailyNetWorth` with freshly calculated results.
- After rebuilding, only those three daily tables are reloaded.
- Transaction refresh is a separate full-table pull.

## Future Apps Script backend option

A future no-cost alternative to direct browser Sheets access may be an Apps Script backend:

```text
Flutter web app → Apps Script web endpoint → Google Sheets
```

Potential responsibilities:

- Server-side Sheets reads and writes.
- Transaction append operations.
- Daily catch-up.
- Manual daily-table rebuild.
- Google authorization stored on the Apps Script side.

Before implementation, the following must be designed and tested:

- Endpoint authentication and single-user authorization.
- CORS behavior for Flutter web.
- Script Properties for spreadsheet configuration.
- Abuse protection if the endpoint is publicly reachable.
- Apps Script execution and daily quotas.

This is a future alternative and does not replace the current direct Google OAuth/Sheets implementation yet.

## Future account visibility

Keep all accounts available for calculations and historical analysis, but later add UI visibility metadata to `Accounts`:

```text
show_in_app,is_favorite,display_order
```

Planned behavior:

- Dashboard shows favorites by default.
- Forms show favorites first, with an expandable all-accounts option.
- Accounts page shows favorites first and supports all accounts.
- Analysis can select any account.
- Daily calculations include all open accounts regardless of UI visibility.
- Multiple Wise currency balances remain separate accounts and may later use provider/group metadata.

This is deferred until after the current migration work.

## Deferred functionality

- Transaction editing.
- Transaction deletion.
- Current-month spending and income cards.
- Spending and income category breakdowns.
- Period comparisons.
- Optional transaction-form defaults managed alongside display preferences.
- Transaction templates: create a template by filling selected form fields, then show only the remaining unfilled fields when using the template.
- Budget groups, monthly limits, and account-transfer goals.
- Loans, investments, non-forex units, investment rates, and loan-interest modeling.
- Detailed investment holdings and valuation.
- Dark theme.
- Lazy/selective loading optimization.

## Data validation dependency graph

Current parser dependencies form a directed acyclic graph:

```text
Currencies → Accounts → Transactions
Currencies → DailyAccountBalances
Currencies → DailyNetWorth
Accounts + Currencies → DailyManualValuations
```

A dependent table is not parsed when any dependency has validation errors. Valid independent tables continue to be checked. Future dependency additions should use the cycle detector; circular dependencies are rejected rather than silently recursed.

## Data validation failure behavior

- Validation runs at the repository/data boundary for every initial load and refresh.
- The app does not remain usable with validation errors.
- A full-screen validation page replaces the current content immediately when a refresh fails.
- Errors are grouped by table with concise messages and table/row/field locations.
- Repeated identical errors are collapsed into one item with row numbers; after the first three rows, the UI reports how many additional rows share the error.
- Valid rows are parsed and retained during validation collection, while the app remains blocked until all validation errors are resolved.
- Technical parser/API details are available in an expandable section.
- `Reload data` retries source loading and validation.

## Testing policy

- OAuth live testing is excluded from automated tests; it remains a manual smoke test.
- Financial calculations require unit tests for rounding, currency conversion, signed balances, transaction effects, daily aggregation, and retry/idempotency behavior.
- Google Sheets API calls are tested through deterministic fake clients.
- Rebuild and catch-up tests include partial-write failures and retry behavior.
- Every production bug must add a regression test before the fix is considered complete.
- Run [`tool/check_coverage.sh`](./tool/check_coverage.sh) regularly.
- Current coverage policy: at least 80% application-logic line coverage and at least 90% for financial logic files. Application-logic coverage excludes UI composition, visual theme code, OAuth UI, and low-level external HTTP adapters; those areas use widget/manual smoke tests.

## Verification checklist

### Data and calculations

- [ ] All runtime CSV tables parse into typed models.
- [ ] Missing transaction-side values remain `null`.
- [ ] Transaction type validation matches the table above.
- [ ] Date ranges include both boundaries.
- [ ] Current net worth uses the latest daily net-worth row.
- [ ] Missing net worth displays `Unavailable`.
- [ ] Overview accounts use current ledger balances.
- [ ] Analysis accounts use daily values.
- [ ] Closed accounts stop on their inclusive closing date.
- [ ] Missing daily dates are warned about and not interpolated.
- [ ] Chart x-axis preserves real date gaps and uses readable intervals.

### UI

- [ ] Dashboard is the initial section.
- [ ] Compact navigation uses the bottom navigation bar.
- [ ] Wider navigation uses the navigation rail.
- [ ] Transactions support all agreed filters.
- [ ] Add Transaction supports all four transaction types.
- [ ] Description and tag are mandatory for new entries.
- [ ] Analysis shows both daily chart types.
- [ ] Analysis controls remain usable at mobile width.

### Sheets integration

- [ ] Silent OAuth is attempted first.
- [ ] Unauthorized accounts are rejected before Sheets access.
- [ ] OAuth uses the authorized localhost port 9000 during development.
- [ ] Daily freshness checks read only date columns.
- [ ] Catch-up is sequential and idempotent.
- [ ] Transaction append is row-based.
- [ ] Full rebuild requires confirmation.
- [ ] Rebuilt daily tables are reloaded independently.
