# Performance implementation plan

This plan combines the source analysis in [`PERFORMANCE_ANALYSIS.md`](./PERFORMANCE_ANALYSIS.md) with the Chrome trace [`Trace-20261023T001105.json.gz`](./profile_traces/Trace-20261023T001105.json.gz).

## Confirmed decisions

- Include tab keep-alive in addition to data indexing and calculation caching.
- Invalidate all affected caches immediately after writes.
- Target up to 100,000 transactions in one browser session.
- Preserve exact daily graph points and exact point selection.
- Keep performance indexes/results memory-only; rebuild them from the authoritative snapshot after reload.
- `Transactions`, `Analysis`, and `Overview` are the first performance targets.

## Evidence and goals

The trace contained 18,658 renderer tasks totaling approximately 8.53 seconds, with 28 tasks over 16 ms, 2 over 50 ms, and a maximum task of approximately 132 ms. It did not contain multi-second main-thread stalls. Scroll event handlers were comparatively inexpensive: wheel handlers totaled approximately 158 ms with a 4.17 ms maximum.

The source-level goal is to remove repeated full-table work from tab entry and page rebuilds, then confirm the result with isolated profile recordings.

## Architecture

### Snapshot-scoped performance context

Create a memory-only `PerformanceDataContext` associated with one immutable `AppDataSnapshot` instance. It owns:

- A monotonically increasing snapshot version or identity token.
- Transaction indexes.
- Daily-data indexes.
- Exchange-rate indexes.
- Manual-valuation indexes.
- Memoized derived calculations.
- Optional debug counters for cache hits, misses, and build times.

A new snapshot creates a new context. No cache may survive a snapshot replacement.

Avoid putting large mutable caches directly into model objects. Keep indexes in a dedicated context so source-of-truth models remain immutable and serialization-independent.

### Strict invalidation contract

Every repository write that returns a new snapshot must replace the context at the same time. This includes:

- Transactions and transfers.
- Manual valuations.
- Display preferences.
- Templates and income allocations.
- Reloads after Sheets writes.

The UI must never reuse a result produced from an older snapshot identity.

## Priority 0 — instrumentation and benchmark harness

Before optimization, add repeatable measurements:

1. Add debug-only timing around tab construction, transaction filtering, grouping, analysis queries, and Overview balance calculation.
2. Add fixtures with approximately 10,000, 50,000, and 100,000 transactions while retaining small reference tables.
3. Record cold and warm timings separately.
4. Record memory-sensitive index sizes.
5. Capture isolated Chrome traces for:
   - Cold Transactions tab open.
   - Warm Transactions tab return.
   - Transactions scrolling.
   - Cold Analysis tab open.
   - Warm Analysis tab return.
   - Analysis range change.
   - Overview tab open.

The benchmark must compare results against an uncached reference implementation for correctness.

## Priority 1 — keep expensive tab state alive

### Current issue

[`AppShell`](./lib/app/app_shell.dart#L279) constructs only the selected page. Switching tabs recreates page state and repeats calculations. `PageStorageKey` preserves scroll offsets but does not preserve computed page state.

### Implementation

Introduce a lazy tab host:

- Keep a stable keyed page instance for each visited section.
- Use `IndexedStack` or `Offstage` so inactive pages are not rebuilt on every navigation.
- Build a page only on first visit.
- Preserve the restricted-startup rule so only Transactions is available before authentication.
- Ensure callbacks and repository snapshots update safely when the active snapshot changes.

Do not keep every tab alive before it has been visited. This avoids paying initial build cost for all pages.

### Acceptance criteria

- Returning to a visited tab does not rerun its initial full-table calculations.
- Scroll position and page-local selection state remain intact.
- A new snapshot invalidates page view-model caches without leaving stale data visible.

## Priority 2 — transaction index and lazy list

### Current issue

[`TransactionsPage._filteredTransactions`](./lib/app/pages/transactions_page.dart#L290) scans and sorts all transactions on every build. [`_buildGroupedList`](./lib/app/pages/transactions_page.dart#L366) groups them and eagerly allocates row widgets.

### Index design

Build once per snapshot:

```text
transactionsByDisplayOrder: List<Transaction>
transactionsByDate: Map<DateOnly, List<Transaction>>
transactionsByType: Map<TransactionType, BitSet/ID set>
transactionsBySourceAccount: Map<AccountId, ID set>
transactionsByDestinationAccount: Map<AccountId, ID set>
transactionsByCategory: Map<CategoryId?, ID set>
transactionsByTag: Map<TagId?, ID set>
```

For 100,000 transactions, prefer compact integer indexes or stable transaction positions rather than duplicating full transaction objects in every index.

The canonical display order should be computed once:

```text
(date descending, createdAt descending)
```

### Query design

Represent active filters as an immutable `TransactionFilterKey`. Query by intersecting candidate ID/position sets, then iterate results in canonical display order. This avoids sorting each query result.

Special-case the no-filter query to return the canonical list directly.

Memoize recent filter results by `TransactionFilterKey`, with bounded capacity to avoid retaining every historical combination.

### Rendering design

Replace the eager `children` list with a lazy row descriptor list or a sliver builder:

```text
TransactionRowDescriptor.header(date)
TransactionRowDescriptor.transaction(transactionId)
```

Build only visible rows. Keep the existing `TransactionListRow` visuals, but resolve presentation data from precomputed lightweight view data where useful.

### Acceptance criteria

- No-filter tab entry is linear index access plus visible-row layout, not `O(N log N)` sorting.
- Filter changes do not rebuild unrelated data.
- 100,000 transactions remain scrollable without large frame drops.
- Results match the current filter implementation exactly.

## Priority 3 — memoized Analysis view model

### Current issue

[`AnalysisPage.build`](./lib/features/analysis/analysis_page.dart#L88) computes net-worth, account, spending, and income results together on every rebuild.

### Implementation

Create an `AnalysisViewModel` backed by `PerformanceDataContext` with independent memoized queries:

```text
netWorthSeries(range)
accountRange(accountId, requestedRange)
accountBalanceSeries(accountId, range)
categorySpending(month, tagId)
categoryIncome(month, tagId)
incomeAllocationProgress(month, categoryId)
```

Cache keys must include all semantic inputs and snapshot identity.

Do not invalidate graph series when only the category tag changes. Do not invalidate category results when only an account graph range changes.

### Date and daily indexes

Build once:

```text
dailyNetWorthByDate
balancesByAccountAndDate
manualValuationsByAccountAndDate
ratesByCurrencyAndDate
```

Keep daily data sorted at index construction time. Range queries should use binary-search bounds and list slices rather than filtering and sorting the full daily table.

### `allHistoryRange`

Replace the repeated transaction-date sort in [`analysis_calculator.dart`](./lib/features/analysis/analysis_calculator.dart#L43) with a cached earliest transaction date and cached latest derived date.

### Acceptance criteria

- Rebuilding the Analysis widget does not recompute unchanged queries.
- Switching between previously visited analysis ranges hits the memoized result.
- Exact daily points and selected-point behavior remain unchanged.

## Priority 4 — category, FX, and allocation indexes

### Current issue

[`CategoryAnalysisCalculator`](./lib/features/analysis/category_analysis.dart#L37) scans all transactions, and currency conversion searches exchange rates repeatedly. [`IncomeAllocationAnalyzer`](./lib/features/analysis/income_allocation_analysis.dart#L26) rescans transactions for each allocation/category.

### Implementation

Build monthly and semantic transaction buckets in one pass:

```text
transactionsByMonth
transactionsByMonthAndTag
incomeByMonthCategoryAccount
transfersByMonthSourceAccountCategory
```

Build a rate lookup with one entry per `(currencyId, date)` and a carry-forward structure for latest-prior-rate lookup.

Compute all income allocation progress for one month in one pass over the relevant transaction buckets. Do not invoke a full-table analyzer once per visible income category.

Memoize category results by `(month, tagId, snapshotVersion)`.

### Acceptance criteria

- Category analysis cost depends on the selected month and indexed candidates, not all historical transactions.
- FX lookup is `O(1)` or `O(log R)` rather than a full rate scan per transaction.
- Allocation rows show the same totals and missing-rate behavior as today.

## Priority 5 — Overview balance cache

### Current issue

[`OverviewPage`](./lib/app/pages/app_pages.dart#L19) runs `AccountBalanceCalculator.calculate()` across all transactions every build.

### Implementation

Add a snapshot-scoped cached result:

```text
ledgerBalancesByAccount
```

Calculate it once per snapshot, or build it incrementally while constructing the transaction index. Invalidate on transaction/account snapshot replacement.

Use the same cached map for Overview and any other ledger-balance consumer.

## Priority 6 — manual valuation and maintenance indexes

### Manual analysis

Optimize [`AnalysisCalculator._manualAccountBalanceSeries`](./lib/features/analysis/analysis_calculator.dart#L130) with:

- Per-account valuations sorted once.
- A forward cursor for latest-prior valuation.
- Indexed exchange-rate lookup.

### Daily maintenance

Optimize [`DailyMaintenanceService._balancesThrough`](./lib/data/repositories/daily_maintenance_service.dart#L222) with:

- `transactionsByDate` instead of filtering all transactions for every date.
- Precomputed account lifetime ranges.
- Rate lookup by currency/date.
- Forward-carry valuation lookup.

These changes primarily improve startup, refresh, and rebuild operations rather than ordinary tab navigation, so they follow UI-tab optimizations in priority.

## Priority 7 — graph rendering

For long daily histories, optimize [`analysis_chart_widgets.dart`](./lib/features/analysis/analysis_chart_widgets.dart#L170) by:

- Caching converted chart coordinates.
- Replacing linear selected-point lookup with binary search.
- Avoiding repeated X-position calculations during rebuilds.
- Optionally decimating only the rendered path for very long ranges while retaining exact daily points for selection and tooltips.

The 20-day case should not require visual downsampling.

## Testing and correctness

For every cache/index:

1. Compare cached results against the existing uncached implementation.
2. Test empty and single-row datasets.
3. Test duplicate dates and missing dates.
4. Test currency/rate gaps.
5. Test liability and manual-valuation semantics.
6. Test strict invalidation after each write type.
7. Test 10k/50k/100k transaction fixtures.
8. Add widget tests for tab return, scroll restoration, and filter equivalence.

## Profiling checkpoints

After each priority phase, capture isolated profile recordings for:

- Cold Transactions open.
- Warm Transactions return.
- Transaction scrolling.
- Cold Analysis open.
- Warm Analysis return.
- Analysis range/tag changes.
- Overview open.

Compare frame count, long tasks, CPU time, and memory against the original trace. The current trace showed a maximum renderer task of approximately 132 ms but no multi-second main-thread stall; the implementation goal is to remove the repeated full-table work that can produce those frame spikes at larger data volumes.
