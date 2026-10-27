# Accountable implementation plan

The behavioral source of truth is [`FUNCTIONAL_SPEC.md`](./FUNCTIONAL_SPEC.md). Update it whenever implemented or planned functionality changes.

The app will open on a dashboard. The implementation will use layered architecture so the UI remains independent of CSV parsing, Google Sheets access, and future backend changes.

## Phase 1 — Define the application data model

Create typed Dart models for:

- `Transaction`
- `Account`
- `Category`
- `Tag`
- `ExchangeRate`
- `DailyAccountBalance`
- `DailyNetWorth`

Also define:

- Transaction-type validation rules.
- Currency behavior.
- UTC timestamps.
- Local transaction dates.
- Balance calculation rules.
- Stable category and tag keys.
- CSV parsing and validation errors.

No Google Sheets connection is needed yet.

## Phase 2 — Create the data-access layer

Use repository interfaces so the UI does not know where data comes from:

```text
UI
  ↓
Application services
  ↓
Repository interfaces
  ↓
CSV repository or Google Sheets repository
```

Initial repositories:

- `TransactionRepository`
- `AccountRepository`
- `CategoryRepository`
- `TagRepository`
- `ExchangeRateRepository`
- `DailySnapshotRepository`

The first implementation will use local fixture data from [`test_sheets/`](./test_sheets/).

## Phase 3 — Establish project structure

A maintainable structure could be:

```text
lib/
  app/
    app.dart
    theme/
    routing/
  core/
    errors/
    formatting/
    result/
  data/
    models/
    repositories/
    csv/
  features/
    dashboard/
    transactions/
    accounts/
    analysis/
  config/
    transaction_types.dart
  main.dart
```

Features should depend on repository interfaces, not CSV parsing or Google Sheets details.

## Phase 4 — Build the responsive app shell

Implement:

- Mobile bottom navigation.
- Desktop sidebar or navigation rail.
- Responsive content constraints.
- App theme.
- Loading states.
- Empty states.
- Error states.
- Consistent spacing and typography.

Initial sections:

- Dashboard.
- Transactions.
- Accounts.
- Analysis.
- Settings.

The dashboard will be the initial landing screen.

## Phase 5 — Build the first dashboard

Initial dashboard content:

- Net worth.
- Account balances.
- Spending for the selected period.
- Income for the selected period.
- Net-worth trend.
- Recent transactions.
- Add-transaction button.

The first version can use simple cards and basic charts. The layout will be mobile-first but expand cleanly for desktop web.

## Phase 6 — Build transaction viewing and entry

Implement:

- Transaction list.
- Date filtering.
- Type filtering.
- Account filtering.
- Category filtering.
- Tag filtering.
- Quick expense form.
- Income form.
- Reimbursement form.
- Transfer form.

All forms will produce one canonical transaction model and one row format for Sheets.

## Phase 7 — Add calculations and analysis

Implement tested application services for:

- Account balances.
- Net worth.
- Spending totals.
- Income totals.
- Reimbursements.
- Category breakdowns.
- Tag breakdowns.
- Date-range comparisons.
- Daily trend data.
- Cross-currency display conversion.

Long-range chart views will use the stored daily tables. Current and detailed views will use transactions where appropriate.

## Phase 8 — Add Google Sheets access securely

After the local-data version works:

1. Add direct Google sign-in for the web app.
2. Load runtime configuration from the committed [`assets/config.json`](./assets/config.json) asset.
3. Validate the Google account against the configured allowlist.
4. Read and write Sheets through the Google Sheets API.
5. Keep the same repository interfaces used by the local CSV implementation.

The UI should not need to change when switching from local data to Sheets.

## Phase 9 — Add daily derived-table workflows

Implement:

- Full rebuild of `DailyExchangeRates`.
- Full rebuild of `DailyAccountBalances`.
- Full rebuild of `DailyNetWorth`.
- Daily retrieval of the previous day’s Frankfurter rate.
- Fallback to the most recent available rate.
- Daily insertion into all three derived tables.

The deployment location for the scheduled job can be decided later, but its source code will remain in this repository.

## Phase 10 — Add budgeting later

Budgeting is intentionally not part of the first draft.

The current design will preserve:

- Stable category keys.
- Stable tag keys.
- One category per transaction.
- One optional tag per transaction.

That will allow future budget rules to group categories and tags without redesigning the transaction ledger.

## Validation strategy

For each layer:

- Unit-test CSV parsing.
- Unit-test transaction validation.
- Unit-test balance calculations.
- Unit-test cross-currency display calculations.
- Widget-test responsive navigation.
- Widget-test transaction forms.
- Test the dashboard with empty, normal, and malformed data.
- Run the app in Chrome at desktop and narrow mobile-sized widths.

## Important web-data detail

A Flutter web app cannot directly read an arbitrary local directory path such as `/Users/.../test_sheets/`. Local CSV data must either be bundled as app assets or selected through a browser file picker. This must be decided before implementing the local CSV repository.

## Step 1 decisions recorded

- Monetary values will use integer minor units internally, with currency decimal places defined in currency metadata.
- `Currencies.csv` will remain in Sheets and will gain a `decimal_places` column.
- `created_at` will default to the current UTC date-time.
- The transaction `date` will be manually selected by the user rather than automatically derived from `created_at`.
- `Categories.csv` will retain `allowed_transaction_types` so category/type rules remain editable in Sheets.
- The first version will load all available tables at startup, while repository boundaries will preserve the option for future lazy or selective loading.
- Loans, investments, non-forex units, investment rates, and loan-interest modeling are deferred; the first draft stays with the original account and transaction types.
- Account sign behavior remains driven by the existing opening/initial balance and ordinary transaction effects; no special credit-account logic is added in the first draft.
- Missing transaction-side values will be `null` in Dart; numeric zero remains distinct from missing data.
- The first draft supports exactly four transaction types—expense, income, reimbursement, and transfer—with rules in Dart and an extension point for future types.

### Step 1 decisions recorded

- Exchange rates will use decimal arithmetic for intermediate calculations; converted monetary results will be rounded only to the target currency's minor unit.
- Local CSV fixtures will be bundled as Flutter assets and reused by the test infrastructure; fixture rows can be expanded later to cover edge cases.
- New UTC timestamps will use ISO 8601 with an explicit `Z` suffix; readers will accept the existing timestamp format during migration.
- The existing `opening_balance` column name will be preserved; no rename to `initial_amount` is planned for the first draft.

Step 1 is complete. Step 2 has started with the model and CSV parsing layer.

## Step 2 decisions recorded

- Use separate repository responsibilities coordinated by one combined immutable `AppDataSnapshot`.
- Startup loading fails the complete snapshot if a required table is missing or malformed; errors include table, row, and field context when available.
- Load all runtime tables once at startup. Refresh only after a user mutation or an explicit reload action.
- Use a typed JSON-backed data-source configuration with Google Sheets as the default and local asset mode selected by editing `assets/config.json`.
- Treat bundled CSV assets as read-only fixtures. The initial asset repository is read-only; local persistence for mutations will be designed when transaction-entry work begins.
- Exclude `TransactionTypes.csv` from runtime loading because transaction types and rules are defined in Dart. It will be deleted later.

Step 2 planning is complete. The immutable snapshot, asset-backed repositories, data-source configuration, and repository tests are implemented. Browser persistence will be addressed later with transaction entry.

## Phase 3 UI decisions recorded

- Use a clean native-finance visual direction with light surfaces, subtle borders, and restrained color.
- Use deep navy as the primary accent, with teal/green positive-state accents.
- Build a light-first theme; dark mode is deferred.
- Keep executable UI values in [`lib/app/theme/`](./lib/app/theme/).
- Maintain high-level visual and interaction principles in [`DESIGN.md`](./DESIGN.md).
- Use Dashboard as the initial landing section with responsive bottom navigation on compact widths and a navigation rail/sidebar on wider widths.
- Keep the initial Transactions, Analysis, and Settings sections intentionally lightweight until their feature phases.

The first responsive app shell is implemented and uses the local asset snapshot at startup.

## Transactions page decisions recorded

- Use a compact mobile-first list grouped by manually assigned transaction `date`.
- Show newest transactions first by default and include all transactions.
- Collapsed rows show description, amount, category/tag, and account.
- Transfers show both source and destination sides.
- Mobile filters open in a bottom sheet; desktop filters appear inline.
- Add a convenience scroll-to-top action when the list is scrolled down.
- Never display `created_at` in the UI.
- Tapping a row may show read-only details; edit and delete remain out of scope for now.

The transaction list, responsive filters, grouped rows, read-only detail sheet, and scroll-to-top action are implemented.

## Transaction entry decisions recorded

- Use one Add Transaction button on the Transactions page only.
- Keep one shared transaction form flow for all four transaction types; specialized quick-entry forms can be added later on top of the same transaction builder and validation rules.
- Present the type chooser as a bottom sheet on compact widths and a dialog/menu on desktop.
- Prefill the transaction date with today's local calendar date while keeping it editable.
- Generate `created_at` automatically as the current UTC timestamp.
- Return to the Transactions list with a confirmation message after successful submission.
- In local Chrome mode, persist the complete test dataset in browser storage while leaving bundled CSV fixtures unchanged.
- Select existing tags only; add new tags in Sheets for now.

Transaction entry is implemented with local Chrome persistence, shared validation, unique 12-character base62 transaction IDs, collision checks against existing transaction IDs, and asset fixtures kept read-only.

- New transaction entries require both a tag and a non-empty description.
- The description field appears at the top of the transaction form.
- Existing fixture rows may remain blank for these fields during migration; entry validation is stricter than legacy-data parsing.

## Analysis planning decisions recorded

- Spending is defined as expenses minus reimbursements; reimbursements are not a separate headline metric.
- Detailed current-month spending, income, and category totals are deferred until their calculation and presentation are designed properly.
- The first dashboard should focus on current net worth and account balances.
- Current net worth should use the latest `DailyNetWorth` value.
- Account cards should calculate balances from `Accounts.opening_balance` plus all transactions and label them as current ledger balances.
- Daily account snapshots are historical and may be one day stale; they should not replace current ledger balances on the first dashboard.
- The dashboard design remains flexible and can be expanded later with period metrics, category breakdowns, charts, and comparisons.
- If no daily net-worth row exists, show `Unavailable` rather than estimate it from account balances.
- Show an `As of YYYY-MM-DD` subtitle under the net-worth value.

## Analysis planning decisions recorded

- The first Analysis page focuses on net-worth trends and account-balance history from daily tables.
- Net-worth trend defaults to all available history.
- Account history is selectable one account at a time.
- Account history uses daily values, never current ledger calculations.
- Account history shows native currency by default with a USD toggle using `balance_usd`.
- Net-worth history uses the USD values in `DailyNetWorth`.
- Missing daily rows are not inferred or interpolated; charts use available rows and show the missing dates.
- The Analysis page includes a date-range selector with All history as the default.
- Initial fixed presets are 30 days, 90 days, year-to-date, and all history.
- Analysis date ranges include both selected calendar-date boundaries.
- Use `fl_chart` for interactive line charts; internal monetary calculations remain decimal/minor-unit based, with conversion to display values only at the chart boundary.
- Missing-data warnings appear above the affected chart.

The first Analysis page and its daily-series calculation services are implemented, including responsive account controls.

## Testing policy decisions recorded

- OAuth live testing is excluded from automated tests and remains a manual smoke test.
- Financial calculations require unit tests for rounding, currency conversion, signed balances, transaction effects, daily aggregation, and retry/idempotency behavior.
- Google Sheets API calls use deterministic fake clients in tests.
- Rebuild and catch-up tests cover partial-write failures and retry behavior.
- Daily maintenance tests verify that only currencies with open accounts receive rates and only open accounts receive daily balances.

## Daily valuation planning decisions recorded

- Keep the existing `Accounts.account_type` column with values `cash`, `asset`, and `liability`.
- Infer balance source from `account_type` initially: `cash` uses transaction-derived balances; `asset` and `liability` use manual valuations.
- Add a new `DailyManualValuations` table.
- Initial columns are exactly: `valuation_id`, `date`, `account_id`, `value`.
- The valuation currency is inferred from the referenced account.
- Manual asset/liability valuation snapshots will be used for net-worth calculations.
- The Assets & liabilities section lists only accounts with `uses_manual_valuations=TRUE`.
- `Accounts.account_type` values are `cash`, `liability`, or `asset`; `uses_manual_valuations=TRUE` is valid only for `asset` or `liability` accounts.
- `uses_manual_valuations` validates Google Sheets boolean output (`TRUE`/`FALSE`, including normalized casing) and rejects other values.
- Valuation dates use the user's local calendar timezone; manual valuation values preserve their stored signs, including negative liability values.
- The valuation form order is account, date, valuation.
- Duplicate account/date dates and dates outside account opening/closing bounds are disabled; changing account clears an invalid selected date.
- If a valuation is missing for a date, carry forward the latest prior valuation and mark it stale.
- `DailyAccountBalances` remains limited to open `cash` accounts.
- `DailyNetWorth` combines ledger-derived balances with manual valuations for `asset` and `liability` accounts.
- Future color coding/subtext for positive and negative account classes is planned.
- Transfer account-type pairs are allowed without validation restrictions; transfer interpretation will be designed when transfer analysis is implemented.
- Daily valuation batch saves use all-or-nothing validation: blank, malformed, negative, duplicate, or out-of-range values prevent the entire batch from saving.

The Assets & liabilities page, DailyManualValuations model/parser/repositories, manual valuation entry, valuation date constraints, and valuation-aware daily net-worth calculation are implemented.

- Future account visibility metadata (`show_in_app`, `is_favorite`, `display_order`) is deferred until after migration work.
- The current Sheets/CSV schema contract includes `Accounts.uses_manual_valuations`, no stored `Accounts.current_balance`, `Currencies.decimal_places`, the reordered Transactions columns, `DailyExchangeRates.source_rate_date`, and `DailyManualValuations(valuation_id,date,account_id,value)`.
- The global daily/analysis history starts at the earliest transaction date; account opening dates do not define the global period. Manual valuations before that transaction cutoff are ignored.
- Every production bug must receive a regression test.
- Coverage is measured with [`tool/check_coverage.sh`](./tool/check_coverage.sh).
- Current coverage thresholds are 80% application logic and 90% for financial logic files. Application-logic coverage excludes UI composition, visual theme code, OAuth UI, and low-level external HTTP adapters; those areas use widget/manual smoke tests.
- Data validation errors are aggregated at the repository boundary and displayed in a full-screen grouped validation page with a Reload data action and expandable technical details.
- Repeated errors are grouped by table/field/message and summarized with row numbers; valid rows are retained during collection while the app remains blocked until the dataset is fully valid.
- Table parsing uses a dependency DAG; dependent tables are skipped when upstream validation fails, and future circular dependencies are detected and rejected.

- Closed accounts are charted only through their closing date, inclusive, and show a `Closed on YYYY-MM-DD` subtitle.
- Chart x-axes use actual calendar-day positions with adaptive, sensible date intervals based on chart width and period span, avoiding repeated or overcrowded labels.

## Google Sheets integration decisions recorded

- Use direct Google OAuth and the Google Sheets API; do not use Firebase Authentication or Firebase services.
- Google OAuth configuration gate, account restriction, Sheets API client, Sheets-backed repository reads, and transaction append support are implemented.
- Daily catch-up and manual full rebuild are implemented through the Google Sheets startup gate and Settings action.
- Do not use scheduled triggers for daily derived-table updates initially.
- On app startup, after OAuth authorization, perform event-based daily catch-up through the previous completed day.
- Query only the date columns of the daily tables using a Sheets API batch request; do not load entire daily sheets just to check freshness.
- Do not use browser storage for daily synchronization state.
- Do not add a `SyncState` table yet.
- Treat the daily Sheets data as authoritative for determining the latest processed date.
- Make catch-up idempotent with deterministic daily row IDs and checks against existing rows before inserting.
- Restrict the Sheets integration to the user's specific Google account; other signed-in accounts must be rejected.
- Use Flutter's `google_sign_in` package for browser OAuth rather than implementing Google Identity Services manually.
- Keep the configured spreadsheet ID and OAuth settings in a checked-in non-secret Dart configuration file; no private credentials belong in the repository.
- Request only the Google Sheets read/write OAuth scope; do not request Drive permissions.
- Reject unauthorized accounts before any Sheets request and show a sign-out/retry action.
- The planned startup outbox flow may show the normal shell with loading states before OAuth and full Sheets loading complete; only Add Transaction is active until initialization finishes.
- Use row-level Sheets operations rather than rewriting the entire Transactions sheet for future mutation support.
- The first integration supports appending new transactions only; editing and deletion are deferred.
- Include the user-invoked full rebuild action in Settings in the first Sheets integration; it is not part of daily startup catch-up.
- The full rebuild requires explicit confirmation, then replaces all rows in the three derived daily tables with freshly calculated results.
- Google Sheets mode will be the default data source.
- Local CSV mode is selected from the committed [`assets/config.json`](./assets/config.json) asset; otherwise Sheets mode is used.
- The release build will not expose a runtime data-source toggle and will default to Sheets.
- Standardize Google OAuth Flutter web testing on `http://localhost:9000`; authorize this origin in the Google Cloud OAuth client.
- Tests and local development can inject the asset repository directly; normal app runs follow the committed runtime config unless a repository is injected.
- Attempt silent Google authentication on startup while the restricted shell remains visible; debug startup scenarios can delay or simulate authentication outcomes.
- After account restoration, attempt Sheets scope authorization silently; request interactive consent only when needed.
- Where Google permits it, combine account restoration and Sheets authorization into the earliest possible flow.
- On expired/invalid Sheets tokens, retry once after silently reacquiring authorization; show reauthorization only if that fails.
- Provide an explicit account-switch/sign-out action.
- Use distinct UI states for restoring session, signing in, granting Sheets access, loading data, unauthorized account, configuration errors, restricted startup, pending local uploads, and uncertain uploads.
- Expired-token retry remains a follow-up integration task.

## Startup transaction outbox — implemented

See the behavior in [`FUNCTIONAL_SPEC.md`](./FUNCTIONAL_SPEC.md). The browser-persisted form snapshot contains only Accounts, Categories, Currencies, Tags, TransactionTemplates, and DisplayPreferences. A separate transaction outbox stores entries made before authentication and full synchronization complete. Batches are verified against freshly loaded Sheets rows before removal; ambiguous uploads require explicit recovery. Web Locks serialize writes across tabs in the same browser origin; other devices are not coordinated.

## Future Apps Script backend option

A possible future zero-cost architecture is an Apps Script backend between Flutter and Sheets. It could own Sheets authorization, reads/writes, daily catch-up, and manual rebuilds. Authentication, CORS, endpoint protection, Script Properties, and Apps Script quotas must be planned before implementation. The current direct OAuth/Sheets architecture remains active for now.
- Separate a Google OAuth/Sheets API service from repositories; the service handles tokens, range reads, batch reads, row appends, and full-rebuild writes, while repositories map API data into domain models.
- Use A1 ranges based on current tab names and headers, such as `Transactions!A:K`, `Accounts!A:H`, and daily date-column ranges; spreadsheet ID is the only spreadsheet-specific configuration value.
- After authentication and startup catch-up, read all current runtime tables; support appending new transactions and the confirmed manual full rebuild, while editing and deletion remain deferred.
- Run startup catch-up sequentially: catch up `DailyExchangeRates` first, then `DailyAccountBalances`, then `DailyNetWorth`.
- If catch-up fails partway through, leave completed rows untouched and retry idempotently from each table's latest date on the next launch.
- Catch up through yesterday using the user's local calendar date; store retrieval timestamps in UTC.
- For missing Frankfurter dates, use the most recent prior available rate while still writing the rate row under the requested sequential date.
- Include a confirmed Settings action for rebuilding daily tables; after completion, reload only the three rebuilt daily tables. Transaction refreshes remain a separate operation that pulls the Transactions table.
- Initially, after appending a transaction, pull the full Transactions table again rather than updating only in memory; keep the repository boundary flexible for later optimization.
- Startup should perform one silent OAuth attempt, validate the returned account locally, request interactive Sheets consent only when needed, and run catch-up only when daily tables are behind yesterday.
- If daily tables are current through yesterday, skip catch-up writes and proceed to runtime-table loading.
- Store the allowed Google email as a replaceable placeholder in the checked-in non-secret configuration file.
