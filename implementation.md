# Accountable implementation plan

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

1. Add Firebase Google sign-in.
2. Add one secure backend path for Sheets.
3. Validate the Firebase user.
4. Read and write Sheets only through the backend.
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
- Use a typed data-source configuration with local asset mode as the default and a future Google Sheets mode behind the same interfaces.
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
