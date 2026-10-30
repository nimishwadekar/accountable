# Accountable code-review guide

This document is the repeatable guide for performing a comprehensive code review of Accountable. It is intended for future maintainers and coding assistants.

## Product and architecture context

Accountable is a mobile-first Flutter app backed by Google Sheets. Local CSV fixtures support development and tests.

Primary layers:

```text
Flutter UI
  → application/calculation services
  → repository interfaces
  → local CSV persistence or Google Sheets API
```

The canonical behavioral documentation is [`FUNCTIONAL_SPEC.md`](./FUNCTIONAL_SPEC.md). Visual and responsive intent is documented in [`DESIGN.md`](./DESIGN.md). Implementation history and architectural decisions are in [`implementation.md`](./implementation.md).

## Review rules

- Review the entire repository, not only the tagged file.
- Prioritize correctness of financial data over UI polish.
- Treat transactions, accounts, currencies, and manual valuations as source-of-truth data.
- Treat daily balances, exchange-rate snapshots, and daily net worth as derived data.
- Look for duplicated sources of truth before proposing new abstractions.
- Do not silently change financial semantics; ask for clarification when behavior is ambiguous.
- Do not commit or push unless explicitly requested.
- Do not expose access tokens, credentials, private spreadsheet data, or other secrets.
- Make surgical changes only after the user approves the finding.
- Update directly related documentation when behavior changes.

### Tool-output redaction caveat

The tool display layer may redact strings matching `Bearer <token>` as `******`, including harmless test values and source-code examples. Do not infer that an authorization header is missing or malformed from redacted tool output alone. Verify the saved file through a non-redacting path before reporting a bearer-header finding, and never expose real credentials while doing so.

## Review sequence

### 1. Establish the baseline

Run:

```bash
/Users/nwadekar/flutter/bin/flutter analyze
/Users/nwadekar/flutter/bin/flutter test --coverage --concurrency=1
LOGIC_MIN=80 FINANCIAL_MIN=90 FLUTTER_BIN=/Users/nwadekar/flutter/bin/flutter ./tool/check_coverage.sh
COVERAGE_OUTPUT_DIR=coverage/financial_flows FLUTTER_BIN=/Users/nwadekar/flutter/bin/flutter ./tool/analyze_financial_coverage.sh
/Users/nwadekar/flutter/bin/flutter build web --release --base-href /accountable/
```

Record:

- Analyzer errors and warnings.
- Full test count and failures.
- Application-logic coverage.
- Per-feature/per-flow financial line coverage (95% minimum per target file) and branch coverage diagnostics.
- Web build status.

Use targeted tests during implementation, then rerun the complete suite before declaring the review complete.

### 2. Inventory the repository

Inspect:

- `lib/`
- `test/`
- `test_sheets/`
- `assets/config.json`
- `pubspec.yaml`
- `analysis_options.yaml`
- `.github/workflows/`
- `FUNCTIONAL_SPEC.md`
- `DESIGN.md`
- `implementation.md`
- `README.md`

Search for:

```text
TODO FIXME HACK XXX
USD
DateTime.now
DateTime.utc
setState
appendRow
appendRows
replaceRange
batchUpdate
TextOverflow.ellipsis
catch (
ignore:
```

Identify large files and concentrated responsibilities. Large files are not automatically bugs, but they should be checked for embedded business rules, duplicated UI patterns, and difficult-to-test logic.

### 3. Verify source-of-truth boundaries

Confirm that:

- `Transactions` is the authoritative ledger.
- `Accounts` contains opening values and account metadata, not duplicated current balances.
- `Currencies`, `Categories`, and `Tags` are authoritative reference data.
- `DailyManualValuations` stores original-currency valuation inputs.
- `DailyExchangeRates`, `DailyAccountBalances`, and `DailyNetWorth` are rebuildable derived tables.
- Display preferences, templates, and income allocations are loaded consistently from local and Sheets modes.
- Runtime table schemas are centralized in [`table_schema.dart`](./lib/data/table_schema.dart).
- UI filtering and ordering use [`app_data_snapshot.dart`](./lib/data/app_data_snapshot.dart), rather than reimplementing preference logic.

Flag any duplicated schema, currency rule, account rule, category visual rule, date rule, or serialization contract.

### 4. Review financial correctness

Check:

#### Transactions

- Required and forbidden sides match transaction type.
- Amount currencies match account currencies.
- Amounts cannot be negative unless the domain explicitly allows signed values.
- Category and tag references exist.
- Categories are compatible with transaction types.
- IDs are unique.
- New entries require description and tag.
- Transaction dates are local calendar dates.
- Account lifetime boundaries are inclusive and validated.
- Same-currency transfers use one effective amount.
- Source fees reduce the transferred amount where specified.
- Destination fees are separate expense transactions.
- Transfer batches preserve ordering and are written atomically.

Transfer construction belongs in [`transaction_builder.dart`](./lib/app/pages/transaction_builder.dart), not in widget layout code.

#### Money and conversion

- Monetary values use integer minor units.
- Exchange-rate intermediate calculations use decimal arithmetic.
- Rounding occurs only at the final target-currency result.
- Currency decimal precision is read from `Currencies`.
- No hardcoded conversion multiplier is used.
- The configurable base currency is currently deferred; USD-specific behavior must not be generalized without following the migration plan in [`FUNCTIONAL_SPEC.md`](./FUNCTIONAL_SPEC.md).

#### Manual valuations

- User-entered values are non-negative.
- Liability values are stored negative; users enter positive values.
- Asset values remain positive.
- Account/date duplicates are rejected.
- Opening and closing dates are enforced.
- Batch writes are all-or-nothing.
- Missing dates use the latest prior valuation for analysis and derived net-worth calculations.

#### Derived tables

- Daily catch-up reconciles deterministic row IDs, not only latest dates.
- Partial writes can resume without duplicates.
- Rebuilds derive all values from source-of-truth data.
- Rebuilding all derived tables uses a single Sheets batch update where possible.
- Missing rates are visible and never silently represented as a false zero.

### 5. Review repository and API boundaries

Check that repositories:

- Validate writes at the repository boundary.
- Reload snapshots after successful writes.
- Reject duplicate IDs and invalid references before mutation.
- Preserve local and Sheets behavioral parity.
- Do not expose Sheets/API details to widgets.
- Do not clear production data before a replacement write succeeds.
- Use access tokens only in request headers and never in logs or tests beyond safe fake values.
- Retry expired access tokens only once and safely replay request bodies.

Check that API adapters:

- Use centralized table schemas.
- Correctly coerce numeric and boolean values.
- Preserve empty trailing cells.
- Handle HTTP errors with useful, non-sensitive messages.

### 6. Review parsing and validation

Inspect [`model_parsers.dart`](./lib/data/csv/model_parsers.dart), [`csv_table.dart`](./lib/data/csv/csv_table.dart), and [`parse_helpers.dart`](./lib/data/csv/parse_helpers.dart).

Verify:

- Headers are present and unique.
- Row widths are validated.
- Blank rows are handled intentionally.
- IDs are unique.
- Dates are validated as calendar dates.
- Timestamps are normalized consistently.
- Dependencies are respected by [`table_dependencies.dart`](./lib/data/repositories/table_dependencies.dart).
- Invalid upstream tables prevent unsafe dependent parsing.
- Errors include table, row, field, and technical details where useful.

### 7. Review UI and responsive behavior

Check mobile and desktop layouts for:

- Flex overflows.
- Fixed widths derived from viewport width instead of parent constraints.
- Truncated account/category names.
- Ellipsis where whole-word wrapping is required.
- Touch targets and reachable primary actions.
- Dialog and bottom-sheet sizing with keyboard insets.
- Loading, empty, error, stale, and unavailable states.
- No optimistic financial UI updates before persistence succeeds.

Repeated visual behavior should use shared components and tokens in [`lib/app/theme/`](./lib/app/theme/).

Current extracted UI boundaries include:

- [`analysis_chart_widgets.dart`](./lib/features/analysis/analysis_chart_widgets.dart)
- [`category_analysis_section.dart`](./lib/features/analysis/category_analysis_section.dart)
- [`transaction_builder.dart`](./lib/app/pages/transaction_builder.dart)
- [`transaction_list_widgets.dart`](./lib/app/pages/transaction_list_widgets.dart)
- [`category_visuals.dart`](./lib/app/pages/category_visuals.dart)

### 8. Review authentication and platform adapters

Inspect both web and non-web implementations:

- [`google_auth_service_web.dart`](./lib/data/sources/google_auth_service_web.dart)
- [`google_auth_service_stub.dart`](./lib/data/sources/google_auth_service_stub.dart)
- [`sheets_authorization_web.dart`](./lib/data/sources/sheets_authorization_web.dart)
- [`sheets_authorization_stub.dart`](./lib/data/sources/sheets_authorization_stub.dart)
- [`bearer_client.dart`](./lib/data/sources/bearer_client.dart)

Verify:

- Web and native behavior remains equivalent at the repository boundary.
- Shared auth exceptions remain centralized in [`google_auth_errors.dart`](./lib/data/sources/google_auth_errors.dart).
- OAuth origins and scopes come from [`AccountableConfig`](./lib/config/accountable_config.dart).
- The allowed account is checked before Sheets access.
- Tokens are memory-only and never persisted or logged.
- Sign-out clears cached authorization state.
- Interactive consent is required when silent Sheets authorization cannot proceed.

### 9. Review tests

Tests should cover:

- Money arithmetic and rounding.
- Transaction validation and serialization.
- Same- and cross-currency transfer fees.
- Atomic transaction and valuation batches.
- Parser dependency failures.
- Account lifetimes and duplicate natural keys.
- Daily catch-up gaps and partial writes.
- Missing exchange-rate behavior.
- Base-currency migration once implemented.
- Responsive navigation and important mobile forms.
- Configured CSV and Sheets startup paths.

When adding a test for a bug, assert the business rule—not merely implementation details.

## Reporting format

Report findings in priority order:

| # | Priority | File | Lines | Finding | Impact | Recommendation |
|---|---|---|---|---|---|---|
| 1 | High | `lib/...` | `x` | Concise issue | Financial/user impact | Minimal fix |

Use these priorities:

- **Critical:** data loss, unauthorized access, corrupt financial writes, or production authentication failure.
- **High:** incorrect financial calculations, broken writes, inconsistent source-of-truth behavior, or common-user crashes.
- **Medium:** incomplete validation, stale derived data, significant maintainability risks, or recurring UI failures.
- **Low:** documentation drift, dead code, minor duplication, or non-critical test gaps.

For every finding, include:

1. Exact file and line.
2. Reproduction or affected path.
3. Why it violates the documented behavior.
4. Whether it affects source-of-truth or derived data.
5. A minimal fix proposal.
6. A targeted test plan.

## Completion checklist

Before finishing a review:

- [ ] Entire repository inventory completed.
- [ ] Source-of-truth boundaries checked.
- [ ] Financial calculations and date semantics checked.
- [ ] Repository writes and Sheets API behavior checked.
- [ ] Authentication and token handling checked.
- [ ] Mobile and desktop UI risks checked.
- [ ] Documentation drift checked.
- [ ] Findings ranked by impact and confidence.
- [ ] User approval requested before each code change.
- [ ] Targeted tests pass after each fix.
- [ ] Full tests, analyzer, coverage gate, and web build pass at completion.
- [ ] No secrets, tokens, or private data were added to output or source.
