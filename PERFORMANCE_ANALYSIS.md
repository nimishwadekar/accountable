# Performance analysis

This document records the source-code performance analysis for Accountable. It is theoretical and should be compared with Flutter DevTools/profile-mode measurements before implementation decisions are finalized.

## Workload model

- `N`: transaction count; expected to be the largest table.
- `D`: daily derived rows/dates.
- `A`: account count.
- `R`: exchange-rate rows.
- `V`: manual valuation rows.
- `C`: categories and income-allocation groups.

Twenty days of daily data does not imply a small workload: transaction-heavy operations still scale with the full transaction table.

## Ranked bottlenecks

### 1. Transaction tab: full-table filtering, sorting, and regrouping

[`TransactionsPage._filteredTransactions`](./lib/app/pages/transactions_page.dart#L290) scans all transactions and sorts the result on every page build. [`_buildGroupedList`](./lib/app/pages/transactions_page.dart#L366) then scans and groups the result, and eagerly creates a row-widget wrapper for every transaction before `ListView` lazily builds visible rows.

Estimated cost: `O(N log N)` for the sort plus `O(N)` grouping.

Recommended direction:

- Sort once when the snapshot is created.
- Return a cached pre-sorted list when no filters are active.
- Cache filtered results by snapshot identity and filter values.
- Replace the eager `children` list with a lazy flattened row model and `ListView.builder`/slivers.
- Consider precomputed transaction presentation data for repeated account/category/tag/amount formatting.

### 2. Tab navigation recreates page subtrees

[`AppShell`](./lib/app/app_shell.dart#L279) builds only the currently selected page. Switching away and back recreates page state and repeats page calculations. `PageStorageKey` preserves scroll offsets but does not retain page widgets or computed results.

Recommended direction:

- Use a lazily initialized tab cache with `IndexedStack`, `Offstage`, or equivalent keep-alive containers.
- Prioritize Transactions and Analysis tabs to control memory usage.
- Keep the existing repository snapshot cache; [`GoogleSheetsAppDataRepository.load`](./lib/data/repositories/google_sheets_repository.dart#L46) already caches the loaded snapshot.

### 3. Analysis page recomputes all queries on every build

[`AnalysisPage.build`](./lib/features/analysis/analysis_page.dart#L88) recomputes net-worth, account, spending, and income results on every rebuild. [`AnalysisCalculator.allHistoryRange`](./lib/features/analysis/analysis_calculator.dart#L43) repeatedly sorts transaction dates.

Recommended direction:

- Add an analysis view-model/cache keyed by snapshot identity and query parameters.
- Cache graph series independently from category results.
- Cache the earliest transaction date instead of sorting it repeatedly.

### 4. Category and allocation analysis repeatedly scans transactions

[`CategoryAnalysisCalculator.spending`](./lib/features/analysis/category_analysis.dart#L37) and `income` scan all transactions. Currency conversion can scan all exchange rates for each matching transaction.

[`CategoryAnalysisSection._buildAllocationRows`](./lib/features/analysis/category_analysis_section.dart#L219) invokes [`IncomeAllocationAnalyzer.analyze`](./lib/features/analysis/income_allocation_analysis.dart#L26) per income category. Allocation analysis scans the transaction table multiple times per allocation.

Potential cost can approach `O(C * A * N)` for categories and allocations, plus exchange-rate lookup work.

Recommended direction:

- Build indexes by month, transaction type, tag, category, and account.
- Index exchange rates by currency/date and use direct lookup or binary search.
- Compute allocation progress for all categories/accounts in one pass per month.
- Memoize results by month and tag.

### 5. Overview recalculates all account balances

[`OverviewPage.build`](./lib/app/pages/app_pages.dart#L19) calculates balances from every transaction using `AccountBalanceCalculator` on each build.

Estimated cost: `O(N)` per rebuild.

Recommended direction:

- Cache balances in the immutable snapshot or repository-level derived cache.
- Invalidate only when transactions/accounts change.

### 6. Manual account analysis has nested daily scans

[`AnalysisCalculator._manualAccountBalanceSeries`](./lib/features/analysis/analysis_calculator.dart#L130) searches all valuations for each date and repeatedly searches exchange rates.

Estimated cost: approximately `O(D * V + D * R)`.

Recommended direction:

- Sort valuations once by account/date and carry the latest value forward with cursors.
- Index rates by currency/date.
- Use binary search or forward cursors for date lookups.

### 7. Daily maintenance has avoidable historical scans

[`DailyMaintenanceService._balancesThrough`](./lib/data/repositories/daily_maintenance_service.dart#L222) filters the full transaction list for every date, approximately `O(D * N)`. Net-worth generation repeatedly searches valuations, rates, and open accounts.

This primarily affects startup, refresh, and rebuild operations rather than ordinary tab switching.

Recommended direction:

- Index transactions by normalized date.
- Precompute account lifetime ranges.
- Index rates by currency/date.
- Carry balances and valuations forward incrementally.
- Cache earliest/latest source dates.

### 8. Chart rendering scales with daily points

The chart performs point scanning and coordinate calculations in [`analysis_chart_widgets.dart`](./lib/features/analysis/analysis_chart_widgets.dart#L170), paints a custom gradient path, and renders all daily points through `fl_chart`.

Twenty daily points should be inexpensive. Long all-history ranges may become costly.

Recommended direction:

- Cache chart coordinates.
- Use binary search for selected-point lookup.
- Avoid repeated coordinate conversion during rebuilds.
- Downsample only the rendered path for very long ranges while retaining raw points for exact selection/tooltips.

## Lower-priority costs

- [`AppDataSnapshot`](./lib/data/app_data_snapshot.dart#L93) repeatedly sorts and filters small account/category/tag tables when ordered/visible getters are accessed. Cache these lists in the snapshot; reference tables are expected to be small.
- [`MigrationAssistancePage`](./lib/features/migration_assistance/migration_assistance_page.dart#L31) calculates migration changes once, but account drill-down rescans and sorts migration transactions per account.
- Browser/session preference writes occur only when filters change, not on every scroll event. `PageStorageKey` scroll restoration is in-memory and is not expected to cause scrolling lag.

## Recommended implementation order

1. Optimize Transactions filtering/grouping and lazy row construction.
2. Keep expensive tab pages alive or cache their view models.
3. Add Analysis query/result caching.
4. Add transaction, allocation, and exchange-rate indexes.
5. Cache Overview balances.
6. Optimize manual analysis and daily maintenance.
7. Optimize chart rendering if profiling confirms it.

## Expected profiler signatures

Compare profiling results against these expected hotspots:

- Transaction entry: `_filteredTransactions`, `_buildGroupedList`, and visible `TransactionListRow` layout.
- Analysis entry: `AnalysisPage.build`, category analysis, and income allocation analysis.
- Overview entry: `AccountBalanceCalculator.calculate`.
- Long graph ranges: `LineChartWidget` and `_ChartAreaGradientPainter.paint`.
- Startup/refresh only: Sheets parsing and `DailyMaintenanceService`.
