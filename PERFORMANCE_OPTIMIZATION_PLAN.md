# Performance optimization implementation plan

Date: 2026-10-29. Based on [PERFORMANCE_AUDIT.md](./PERFORMANCE_AUDIT.md).
Status: **implementation in progress**. The progress table below reflects the
current working tree; phases not listed as complete still need work.

This is the current execution plan. The earlier `PERFORMANCE_IMPLEMENTATION_PLAN.md`
describes an older implementation; several of its proposed indexes and caches
already exist. Retain its goals of memory-only indexes, visited-tab retention,
exact chart selection, and testing toward 100,000 transactions. Do not repeat
already-completed work or treat old trace summaries as current measurements.

## Implementation progress

| Phase | Status | Work completed so far |
|---|---|---|
| 0. Baselines | Partial | Synthetic VM/Chrome harness measures before/after paths; opt-in 10k/50k/100k transaction cases are available with `PERFORMANCE_STRESS=true`. Added and ran a source-mapped profile-mode UI harness and Chrome trace capture. No production-device trace or retained-heap profile yet. |
| 1. History lookups | Implemented | Exact-date maintenance FX index; forward valuation/rate cursors; binary-search latest-prior lookups. Regression coverage passes. |
| 2. Sync/reloads | Partial | Reconciliation reports whether tables changed; startup no longer reconciles twice; refresh/save use the returned final snapshot; save targets 2 source reads without repair / 3 with repair; rebuild and migration avoid an extra caller reload. Remaining template/valuation/outbox read audit and failure-path counters. |
| 3. Row parsing | Partial | Issue-collecting and strict row parsing share map-based converters; removed per-row CSV encode/decode, including migration rows. Google Sheets rows still take the outer whole-table CSV encode/decode path. |
| 4. Snapshot work | Partial | Ledger balances and per-transaction balances are lazy; one chronological sort is shared with display order; hidden balance rows do not request balances. No broad snapshot-context/index sharing yet. |
| 5. UI state | Partial | Visited pages keep stable keys/state during data refresh; refresh shows progress; transaction arrow and balance visibility rebuild only their local listeners. Needs broader navigation/error/scroll profile verification. |
| 6. Analysis/charts | Partial | Manual series use forward cursors; category FX uses binary search; visible income-allocation progress for all categories aggregates a month in one pass; chart points/extrema/spots cache by list identity; point selection uses binary search and ignores unchanged fl_chart selections. Overlay geometry is not fully isolated from chart rebuilds. |
| 7. Secondary paths | Partial | Overview/Accounts valuation lookups use per-account sorted indexes; account/date eligibility uses a set; migration date extrema use scans and migration page calculations cache by snapshot; local CSV appends batch into one encode and unchanged stored tables are not rewritten; milestone reevaluation skips the no-reset pass. |
| 8. FX network | Partial | Successful source-date responses cache per maintenance operation; provider requests have a configurable 20-second timeout; operation-owned HTTP clients are closed by the Sheets gate. No bounded concurrency/progress or USD-only request elimination. |
| 9. Derived writes | Partial | Missing display preferences append in a batch. Coordinated full replacement remains unchanged; no incremental/delta repair was enabled. |
| 10. Workers | Deferred | Requires a profile/release trace after earlier optimizations; no worker introduced. |

### Early synthetic results

Same Apple M3 Pro / Flutter test harness as `PERFORMANCE_AUDIT.md`; these are
test-runtime CPU measurements, not release guarantees or device FPS.

| Operation | Before (VM) | After (VM) | Before (Chrome test) | After (Chrome test) |
|---|---:|---:|---:|---:|
| No-op reconcile, 650 transactions / 1,095 days | 230 ms | 26 ms | 1,279 ms | 249 ms |
| Full repository reload, 650 / 1,095 | 138 ms | 80 ms | 292 ms | 112 ms |
| Manual account all-history series, 650 / 1,095 | 15.9 ms | 1.8 ms | 105 ms | 21.5 ms |
| Issue-collecting transaction parser, 650 / 1,095 | 6.7 ms | 2.8 ms | 16.3 ms | 4.3 ms |

These changes reduce the measured operations by about 5–9× for no-op repair,
4–6× for manual series, and 2–4× for issue-collecting parsing. The candidate
FX-only map lookup remains a microbenchmark, not a full-workflow result. The
transaction widget diagnostic still mounts 6–8 rows, but its pump timings are
not a browser rendering profile. Do not use these measurements to close phase 0.

### Local Chrome profile trace (synthetic UI, headless)

Captured with `tool/performance_profile_app.dart` in a `--profile --source-maps`
build and `tool/capture_profile_trace.mjs`: 650 generated transactions, 365 daily
points, 1440×1000 viewport, no account/API access. This is a real Chrome renderer
trace but **not** a profile of the user's machine or device; headless rendering,
CanvasKit initialization, and injected wheel events affect the measurements.
Trace files were kept outside the repository under the approved temporary folder.

| Scenario | RunTasks over 16.7 ms | Longest RunTask |
|---|---:|---:|
| First startup/render | 8 | 81 ms |
| Transactions, balances hidden, 24 wheel events at 16 ms intervals | 3 | 28 ms |
| Show-balances toggle only | 0 | <16.7 ms |
| Transactions, balances visible, 24 wheel events at 16 ms intervals | 1 | 21 ms |
| First Analysis render | 3 | 43 ms |
| Change net-worth range to MAX | 1 | 19 ms |
| 20 chart-hover moves at 16 ms intervals | 0 | <16.7 ms |

Source-mapped CPU samples point mainly to Flutter rendering/layout, rather than a
full-ledger filter on every scroll: during the hidden-balance scroll recording,
`RenderViewport.performLayout` / `RenderSliverList.performLayout` accumulated
roughly 171 ms and `BuildOwner.buildScope` about 128 ms inclusive across the entire
recording; `TransactionListRow.build` accumulated about 2.8 ms. This is cumulative
across many frames, not one 171 ms stall. The balance toggle itself was not a long
task, and scrolling with balances shown was similar to hidden. For chart hover,
`flushPaint`/`flushLayout` accumulated roughly 134/112 ms across the 20 pointer
moves; `_ChartAreaGradientPainter.paint`, chart build/overlay work, and Y-axis
label measurement were visible contributors. Hover did not exceed 16.7 ms in the
latest capture (an earlier run had one 37 ms outlier). Analysis initial render and
MAX range had 19–43 ms tasks. These are useful leads, but require confirmation in
a normal headed browser on the affected device before tuning raster/layout or
changing UI.

The local profile trace can be repeated without connecting to the configured Sheet:

```sh
PROFILE_DIR=/private/var/folders/cq/8w4pbwbj0vd6pjrchp9xh6280000gn/T/opencode/accountable-profile-build
flutter build web --profile --source-maps --target=tool/performance_profile_app.dart --output-dir="$PROFILE_DIR" --base-href /
python3 -m http.server 9001 --bind 127.0.0.1 --directory "$PROFILE_DIR"
# In a second terminal:
PROFILE_URL=http://127.0.0.1:9001 \
PROFILE_OUTPUT_DIR=/private/var/folders/cq/8w4pbwbj0vd6pjrchp9xh6280000gn/T/opencode/accountable-profile-traces \
CDP_PORT=9231 node tool/capture_profile_trace.mjs
node tool/map_profile_trace.mjs \
  /private/var/folders/cq/8w4pbwbj0vd6pjrchp9xh6280000gn/T/opencode/accountable-profile-traces/02-transactions-scroll-hidden.cpu.json \
  "$PROFILE_DIR/main.dart.js.map"
```

This headless profile is useful for repeatable code-path comparisons, not actual
device FPS. Use normal Chrome DevTools on the affected device for real GPU, display
refresh, browser profile, and network behavior.

## Objective and delivery rules

Make startup, saving, navigation, filtering, charts, and scrolling faster without
changing financial results, stored data contracts, validation, or workflows.

- Implement one independently reviewable change at a time, with its regression
  tests in the same change. Measure before and after on the same fixture/runtime.
- Prioritize confirmed CPU/reload costs over speculative rendering rewrites.
- Use the current implementation and `FUNCTIONAL_SPEC.md` as behavioral references.
  Where they disagree, capture the discrepancy and resolve it separately; do not
  silently change functionality as part of a performance refactor.
- Preserve a test-only, straightforward reference calculation before replacing an
  algorithm. Compare outputs against it, not just against optimized caches.
- Do not trade correctness for a read-count target, an FPS target, or a cache hit.
- Keep expensive diagnostics opt-in; do not log financial contents or credentials.
- No backend migration, new OAuth scopes, persistent financial-history cache,
  schema change, pagination requirement, or visual redesign is included.

## Non-negotiable functional invariants

### Financial data and calculations

- Preserve integer minor units and full-precision Decimal FX arithmetic. Round at
  the same points as today; never replace financial calculations with doubles.
- Preserve opening balances, transaction effects, signed liabilities, account
  opening/closing inclusivity, the earliest-transaction history cutoff, daily
  coverage through yesterday, and empty-ledger derived-table clearing.
- Maintenance requires the appropriate exact-date daily FX row. Analysis uses
  the latest available rate on or before the date. Never conflate these queries
  or use a future rate. Preserve missing-data errors and source-rate metadata.
- Manual valuations remain native-currency values, allow partial saves, exclude
  accounts already valued on the selected date, and carry forward per account.
- Running balances include the full ledger, not the filtered list. Preserve
  chronological `(date, created_at, ID)` tie-breaking, both transfer sides,
  same-account transfers, and exclusion of manual-valuation accounts from subtext.

### Persistence, synchronization, and failure handling

- Sheets remains authoritative. Startup/explicit refresh must detect additions,
  edits, deletions, opening-balance changes, and valuation changes made directly
  in Sheets. A transaction count or latest timestamp is not a change detector.
- Keep the existing cross-tab write coordinator, fresh write validation, ID
  collision checks, and outbox verification before removal. Do not nest the same
  non-reentrant browser lock or make uncertain appends automatically retryable.
- Keep transfer-plus-fee outbox batches intact, IDs stable, and statuses durable.
  Do not claim stronger cross-client atomicity than the Sheets API provides.
- Preserve the distinction between a failed append and a successful append whose
  history repair failed. Never invite a duplicate transaction submission because
  a later reload or repair failed. Keep persistent errors until OK.
- Retain current schemas, headers, legacy parsing compatibility, validation
  locations, row numbers, accumulated errors, and dependency-error handling.
- The browser form snapshot remains the approved six metadata tables only; no
  transactions, daily tables, rates, valuations, or credentials are added to it.

### Features and UI

- Balances remain hidden by default on a newly mounted transaction page; the eye
  control, `Balance: ` subtext, filters, row minimum heights, growing transfer
  rows, transaction details, and reachable scroll-to-top button remain intact.
- Keep page-local selections and filters according to their existing lifetime;
  do not introduce new persisted preferences or new default selections.
- Preserve account/category/tag visibility and ordering, template favorites and
  entry rules, thousands separators/caret behavior, and responsive layouts.
- Graphs retain every daily value, missing/unavailable dates, liabilities,
  markers, tooltips, and exact point-selection rules. No downsampling in this plan.
- Milestones retain complete-calendar-month coverage, start-date clamping,
  partial-first-month exclusion, latest-completed-month display, historical
  qualification, earned-state reset rules, ascending celebrations, and durable
  acknowledgment. Stale or incomplete derived data must not trigger celebrations.
- Migration keeps its 9,999-row cap, Sheet-row finalization order, MIG IDs,
  ten-second timestamps, source-row preservation, retry/conflict protections,
  pre-import date baseline, both confirmations, account highlighting, and manual
  opening-balance reminder. It must never modify Accounts automatically.

## Phase 0 — establish correctness and production-relevant baselines

**Risk:** low. **Dependencies:** none.

**Files:** `test/performance/performance_audit_test.dart`, existing data/widget
tests, and opt-in timeline instrumentation near repository/service boundaries.

1. Extend the existing harness to separate cold/warm measurements, parsing,
   index construction, maintenance calculations, network waits, and rendering.
2. Add counting Sheets/HTTP clients and rebuild/calculate counters. Count full
   reads, affected rows, provider requests, writes, and no-op repairs separately.
3. Capture deterministic reference outputs with a fixed clock for ledger/daily
   balances, FX conversion, manual series, allocation totals, and milestones.
   Preserve independent reference algorithms for differential testing.
4. Use 650/6,500 transactions with 30/365/1,095 days first. Add targeted opt-in
   10k/50k/100k scaling runs, larger account/tag tables, and long-history stress
   cases; avoid multiplying every maximum into an unrealistic mandatory CI test.
5. Record a fresh profile/release trace on the affected browser/device for cold
   startup, first/warm Transactions visit, scroll with balances off/on, return to
   top, scroll after MAX-range Analysis, current/backdated saves, and no-op refresh.
6. Record p50/p95/max CPU/frame costs, network request count/bytes, allocations/GC,
   and retained heap. Widget pump timings and debug JS are not production FPS.

**Exit gate:** reproducible fixture definitions and current behavioral tests;
reference outputs and request counts recorded; remaining scroll-jank hypotheses
kept separate from confirmed reconciliation costs.

## Phase 1 — replace nested history searches

**Risk:** low–medium. **Dependencies:** phase 0 reference tests.

**Files:** `lib/data/repositories/daily_maintenance_service.dart`,
`lib/data/app_data_snapshot.dart`,
`lib/features/analysis/analysis_calculator.dart`,
`lib/features/analysis/category_analysis.dart`.

1. Build a date/currency FX lookup once per maintenance calculation. Normalize
   dates once at ingestion/index construction, not inside sort/search predicates.
2. Expose separate exact-date and latest-on-or-before operations. Use binary
   search for isolated historical queries and monotonic cursors for date sweeps.
3. Advance per-account valuation cursors while generating net worth/manual
   charts. Restrict valuation candidates to valid account lifetimes and retain
   the current no-valuation/missing-rate behavior.
4. Reuse existing transaction-by-date and grouped account/rate indexes rather
   than constructing overlapping copies. Keep account lifetime work outside
   inner loops where straightforward; do not add complex indexes for tiny tables.

**Expected complexity:** maintenance FX work changes from O(D×(A+U)×R) to
O(R + D×(A+U)); latest-prior queries become O(log R_currency); daily carry-forward
work becomes a sweep rather than repeated full-history scans. Decimal conversion
and unavoidable output-row generation remain.

**Correctness gate:** exact financial-output equivalence across unsorted input,
duplicate timestamp ties, currency precision, zero/negative balances, missing FX,
weekends, open/close boundaries, valuations before/after the requested date,
partial valuation coverage, sparse transactions, and no transactions. No-op repair
still makes zero writes. Date/rate lookup operation counts scale approximately
linearly with history, not quadratically.

## Phase 2 — make synchronization return one final result

**Risk:** medium–high. **Dependencies:** phase 0 counting/failure tests; phase 1
can ship independently before this phase.

**Files:** `lib/app/google_sheets_gate.dart`, `lib/app/app_shell.dart`,
`lib/data/repositories/google_sheets_repository.dart`,
`lib/data/repositories/daily_maintenance_service.dart`,
`lib/data/repositories/transaction_outbox_synchronizer.dart`.

1. Introduce a synchronization result containing the authoritative final snapshot,
   whether source data changed, whether derived tables changed, and repair state.
   Reconciliation reports a no-op versus a write instead of returning only void.
2. Give one layer ownership of each workflow. AppShell consumes the result rather
   than immediately issuing another reload. Avoid a new general-purpose framework.
3. Startup: load sources, flush/verify queued batches, reconcile the final source
   state once, perform a final reload only if needed, then write the form snapshot
   and transition online. Skip the second unconditional reconciliation when the
   outbox did not change sources.
4. Transaction save: retain a fresh pre-write validation read, append once, retain
   a fresh post-append source check to include external edits, reconcile once,
   and return/reuse the final result. If repair wrote tables, reload once to
   verify/publish them; if no repair was needed, reuse the fresh checked snapshot.
5. Refresh, valuation saves, rebuilds, template/favorite changes, preferences,
   allocations, migration, and acknowledgment consume the same appropriate result
   rather than stacking reload/refresh/reconcile callbacks. Do not run history
   repair merely because metadata changed unless fresh sources require it.
6. Write the form cache once from the accepted final snapshot. Prevent concurrent
   equivalent reads from racing the repository cache; coalesce only when their
   required freshness is identical, never across a mutation barrier.
7. Preserve the active-entry-form transition guard and recheck outbox emptiness
   under the write coordinator before going online. A newly queued batch causes
   another required pass, not a skipped upload.

### Conservative request budgets

For successful uncontended flows with complete valid reference data; counts
exclude the append itself, range-size reads required by the current replacement
API, provider requests, retries, and outbox verification reads:

| Flow | Current full snapshot reads | Initial safe target |
|---|---:|---:|
| Empty-outbox startup, no repair | 5 | 1, with 1 reconciliation |
| Empty-outbox startup, repair writes | 5 | 2, with 1 reconciliation |
| Save, derived tables unchanged | 4 | 2: pre-write + post-write source check |
| Save, derived tables changed | 4 | 3: those checks + final repaired snapshot |
| Explicit refresh, no repair | redundant caller reload | 1 fresh source read |
| Explicit refresh, repair writes | redundant caller reload | 2 fresh reads |

These are conditional budgets, not permission to skip a necessary freshness check.
A later reduction using patched in-memory snapshots requires independent proof
that external-edit detection and confirmation semantics remain equivalent.

**Correctness gate:** instrumented tests for every workflow and no-op/repair path;
external additions/edits/deletions between reads; multi-tab contention; outbox
enqueue during transition; partial transfer verification; interrupted/uncertain
uploads; expiry/auth failures; append success followed by repair/read/cache-write
failure. No lost data, duplicate writes, stale online transition, or misleading
failure status. Do not retry ambiguous append/structural writes automatically.

## Phase 3 — parse rows directly, without CSV round trips

**Risk:** medium. **Dependencies:** phase 0 parser characterization tests.

**Files:** `lib/data/csv/model_parsers.dart`, `lib/data/csv/csv_table.dart`,
`lib/data/repositories/google_sheets_repository.dart`,
`lib/data/sources/google_sheets_api.dart`.

1. Extract shared row-to-model conversion functions. Strict CSV and issue-collecting
   parsers use the same conversions; the latter catches errors per original row.
2. Eliminate per-row header+row CSV encoding/decoding first, then accept normalized
   Sheets row arrays directly to eliminate the outer whole-table CSV conversion.
3. Keep table/header validation, missing-cell padding, date normalization, legacy
   template/FX compatibility, empty-row behavior, duplicate-key checks, and
   dependency ordering in shared table adapters.
4. Serialize a transaction row once per transaction when appending, not once per
   header column; similarly reuse account-currency metadata within a batch.
5. Batch missing display-preference creation without changing its deterministic
   ordering, generated display orders, or validation behavior.

**Correctness gate:** old/new parser differential tests on valid and invalid
fixtures: quoted commas/newlines, whitespace, trailing blanks, serial/ISO dates,
legacy timestamps, optional tags/descriptions, migration-only blank metadata,
duplicate IDs/account-date keys, malformed headers, and invalid dependencies.
Compare models, error locations/order, and useful technical details. Failures must
not be collapsed into the first error or silently become valid rows. A partial or
uncertain preference append must remain recoverable without duplicate rows.

## Phase 4 — remove redundant snapshot work safely

**Risk:** medium. **Dependencies:** phases 0–1; does not require UI changes.

**Files:** `lib/data/app_data_snapshot.dart`, snapshot callers and index tests,
`lib/app/pages/transaction_list_widgets.dart`.

1. Make optional running-balance indexes lazy. Hidden-balance rows must not request
   them; the first enabled use calculates once and later reads remain O(1).
2. Share one canonical chronological transaction ordering with a derived display
   ordering. Remove comparator date allocations while preserving exact tie-breaks.
   Keep final balances independent/lazy if that avoids forcing the optional index.
3. Do not replay ledger effects independently where one required pass can provide
   both results. Keep affected-account-only per-transaction storage, not an
   all-account matrix.
4. Use immutable table-scoped index bundles if profiling justifies sharing across
   metadata-only snapshot updates. Do not share mutable computed results between
   unrelated snapshots. Use explicit dependency tokens, not list-length checks.
5. Until a reuse case is proven, invalidate conservatively on snapshot replacement.
   Manual reload always validates fresh inputs; never trust an old cache simply
   because a user performed a metadata operation.

### Required dependency/invalidation map

| Cached result | Inputs that invalidate it |
|---|---|
| Canonical ordering/date/month transaction indexes | Transaction IDs, dates, timestamps, contents |
| Final and running ledger balances | Transactions; account opening balances/currencies and applicable account rules |
| Exact/prior FX lookup | Rates, dates/source dates, currency definitions |
| Manual native series | Valuations, account lifetime, requested date range |
| USD series/daily derived calculations | Native inputs plus FX, currency precision, cutoff/end date |
| Spending/income/allocation results | Transactions, allocation definitions, FX/precision, month/tag and relevant reference data |
| Visible/entry/ordered entities | Reference data and display preferences |
| Form/template presentation | Template/reference/preference data and formatting settings |
| Milestone evaluation | Net-worth history, definitions/earned flags, tracking date, calendar date |
| Formatted row/chart geometry | Semantic data, currency formatting, theme, text scale, locale/direction, layout constraints |

**Correctness gate:** tests for lazy calculation count, exact display/balance
order, same-account/cross-currency transfers, filtered/full-history consistency,
immutability, metadata-only reuse, every dependency change, same-size external
edits, and new snapshots arriving with unchanged row counts.

## Phase 5 — preserve UI state and isolate transaction rebuilds

**Risk:** medium. **Dependencies:** phase 2 result/freshness state; phase 4 optional
balances can be integrated independently.

**Files:** `lib/app/app_shell.dart`, `lib/app/pages/transactions_page.dart`,
`lib/app/pages/transaction_list_widgets.dart`, affected pages' `didUpdateWidget`.

1. Keep stable keyed visited page States mounted during refresh/save. Update their
   data and callbacks instead of clearing the whole stack or freezing old widgets.
2. Keep first-load/authentication/error handling intact. During refresh, retain
   existing valid data as explicitly refreshing, not as newly verified data.
   Invalidate/gate derived results until current repair completes; do not issue
   stale milestone celebrations. Continue showing validation/repair failures.
3. Invalidate page calculations on data changes without resetting valid filters,
   scroll positions, or balance visibility. If a selected entity disappears or
   becomes hidden, apply the current safe selection rules, not a stale dropdown.
4. Use a local notifier/builder for the up-arrow threshold. Isolate row balance
   visibility updates so they do not rebuild filter menus unnecessarily.
5. Retain lazy list construction and existing cached filter/group models. Add
   row-presentation caches or extent hints only if profile data justifies them.
   Do not use one fixed height for variable transfer/accessibility content.
6. Keep the existing scroll-to-top behavior initially. A long-distance jump or
   two-stage animation is optional only if it still returns to the same top,
   remains accessible, and does not regress scrolling/filter restoration.
7. Put inactive sections under appropriate `TickerMode`. Do not disable the visible
   pending-milestone navigation pulse or break chart state on reactivation.

**Correctness gate:** widget/browser tests for save/refresh while scrolled,
filters and balances on/off, repeated data updates, deleted references, compact
and desktop layout, transfer expansion, text scaling, dialogs during reload,
restricted startup, navigation/back history, visible/hidden tickers, and errors.
Build counters verify arrow transitions do not rebuild filters; mounted row count
stays viewport-bounded. No stale callback or frozen snapshot in cached pages.

## Phase 6 — optimize analysis and chart interaction

**Risk:** medium. **Dependencies:** phase 1 historical queries and phase 4 keys;
chart rendering changes additionally need phase 0 traces.

**Files:** `lib/features/analysis/analysis_calculator.dart`,
`analysis_page.dart`, `analysis_chart_widgets.dart`, `category_analysis.dart`,
`income_allocation_analysis.dart`, `category_analysis_section.dart`.

1. Cache native series independently of display-unit choice. Either cache the
   existing combined series once without a unit key, or compute/cache USD values
   lazily; do not accidentally hide required missing-rate errors in native mode.
2. Cache currency/date conversion lookup results with their financial inputs.
   For sorted range queries, use binary-search bounds without losing inclusive
   endpoints or missing/unavailable-date reporting.
3. Aggregate monthly income counts and transfers once; memoize per-allocation
   progress rather than rescanning transactions while building category rows.
   Preserve allocation periods, native currencies, and current tag semantics.
4. Cache exact numeric chart points, day offsets, `FlSpot`s, min/max, and axis
   layout by data, constraints, theme, scale, and text direction.
5. Use one deliberate pointer-selection path and update only when the selected
   point changes. Preserve current nearest/next-point behavior in each interaction;
   use equivalent binary searches, not a new selection policy.
6. Update crosshair/tooltip/dot through a localized selection notifier. Recompute
   overlay-dependent bounds only when genuinely needed; maintain overlap avoidance,
   markers, formatted labels, liability styling, touch cancellation, and hover exit.
7. Measure cache/heap growth across accounts and ranges. Remove duplicate unit
   entries; add a bounded cache only if necessary. Keep raw daily data unchanged.

**Correctness gate:** exact old/new series/allocation comparisons; range/tag/unit
changes in isolation; missing FX and zero baselines; liabilities; single/gapped
points; hover/touch/drag boundaries and selection tie cases; chart markers;
responsive/scale/theme changes; tooltip/crosshair visual regressions. No point
decimation, approximation, or dropped financial precision.

## Phase 7 — secondary pages, milestones, migration, and local CSV

**Risk:** low–medium. **Dependencies:** reference tests; milestone sharing uses
phase 4 date/dependency keys.

**Files:** `lib/app/pages/app_pages.dart`, `assets_liabilities_page.dart`,
`lib/data/net_worth_achievement_calculator.dart`, milestone callers,
`lib/data/repositories/migration_transactions.dart`, migration page,
`lib/data/repositories/asset_repositories.dart`, local storage adapters.

1. Overview/Accounts: use the existing sorted per-account valuation indexes and
   calculate asset/liability account lists once per build. Cache net-worth
   summaries by history/date; replace a default-valuation-date sort with a max scan.
2. Index valuation eligibility by `(account, date)`, not assumed ID formatting:
   valid existing rows may use noncanonical IDs. Preserve duplicate/date validation.
3. Milestones: share one evaluation per current semantic inputs/calendar date;
   skip reevaluation if no flags were reset. Keep one clear owner of reset writes,
   and publish acknowledgment/definition changes before reusing results.
4. Migration: replace min/max date sorts with scans, cache status/net-change results
   by snapshot, reuse serialized rows/account-currency maps within conflict checks,
   and retain lazy drill-down rendering. Never sort the source batch in place.
5. Local CSV: validate/migrate only as needed; avoid writeback on unchanged reads.
   Decode once, append the complete transaction/valuation batch, encode once,
   persist once. Preserve stored-schema compatibility and existing failure safety.
6. Reuse local metadata/schema validation only for the exact validated content;
   invalidate after external/storage changes. Retain supported read-only behavior.

**Correctness gate:** partial valuations and eligibility with custom IDs; unchanged
Overview summaries; milestone complete/incomplete months, ordinary declines,
definition/history changes and calendar rollover; full migration warnings/limits/
retry behavior; local storage restart/migrations/batch writes; no unexpected writes
on no-op reads. CSV batch work becomes O(N+B), not O(B×N+B²).

## Phase 8 — reduce FX network waits without changing rate semantics

**Risk:** medium–high. **Dependencies:** phase 1, deterministic provider mocks,
baseline tests for full rebuild versus ordinary reconciliation.

**Files:** `lib/data/repositories/daily_maintenance_service.dart`, provider HTTP
adapter if extracted, related progress/error UI and tests.

1. Share/cache provider responses for identical requests within one operation.
   Reuse current stored rates for ordinary reconciliation as today. Full rebuild
   must still honor its intentional fresh-provider calculation semantics.
2. Investigate provider-supported ranges/bounded concurrency; enable only after
   confirming equivalent requested dates, fallback order, source dates, precision,
   and error behavior. Reassemble results in deterministic date/currency order.
3. Add finite request timeouts, bounded transient-read retries, operation cancellation
   on disposal, and progress reporting. Respect quotas and distinguish provider
   failure from missing data; retain the last valid state and persistent errors.
4. Consider synthesizing USD=1 only when source-date/retrieval metadata and required
   coverage can be preserved. If eliminating provider access changes documented
   failure/metadata behavior, leave it disabled pending explicit review.
5. Close operation-owned HTTP clients on success/failure; never close shared or
   injected clients owned by callers. Do not cache credentials or rates to new
   browser storage, or reuse old responses indefinitely across a full rebuild.

**Correctness gate:** weekends/holidays, missing dates/currencies, source revisions,
USD-only and mixed accounts, unsupported rates, timeouts/429/5xx, cancellation,
deterministic ordering under concurrent completion, client ownership, and identical
daily rows/metadata under a fixed provider/clock. No automatic ambiguous write retry.

## Phase 9 — narrower derived writes and incremental repair (gated)

**Risk:** high. **Dependencies:** phases 1–4 and comprehensive differential/failure
tests. Ship separately from the low-risk algorithm improvements.

**Files:** maintenance service, Sheets API/repository, synchronization coordinator.

1. First avoid writes on equality and avoid rewriting unchanged reference tables.
   Preserve the documented coordinated replacement of all three derived tables
   in the initial optimization release.
2. If payload/read volume remains material, design targeted changes across derived
   tables as one coordinated Sheets batch, including deletion/obsolete-tail clears.
   This changes the implementation mechanism described in `FUNCTIONAL_SPEC.md`;
   require a reviewed spec update before enabling, with identical final tables and
   failure/retry guarantees. Do not introduce three unrelated writes or publish
   a partially repaired snapshot.
3. Use known table extents only when freshly verified. Browser app locks do not
   exclude a human or another external client editing the Sheet. Otherwise retain
   size/freshness reads and the conservative full-replacement fallback.
4. For app-owned changes with a trusted baseline, repair from the earliest affected
   date. Include both old and new dates for edits and the former cutoff for deletes;
   replay with correctly seeded previous balances and latest valuations.
5. Changes to opening balances/currencies/lifetimes, earlier migrations, deletions
   of the earliest transaction, or unrecognized source/rate changes require broad
   invalidation or a full repair. Manual valuation effects extend until the next
   applicable valuation. External additions/edits/deletions require a fresh source
   comparison; length/latest-ID checks are insufficient.
6. Source/dependency change detection must compare all relevant values, including
   equal-row-count edits, dates, precision, and required reference data. A hash may
   accelerate comparison but is not a substitute for reliable equality on doubt.

**Correctness gate:** compare incremental/delta output with a full reference rebuild
after randomized additions, edits, moves, and deletions; earlier/later cutoffs;
account/FX/valuation changes; row shrink/reorder; empty ledger; failures at every
write/verification boundary; retry and external-edit conflict scenarios. If a
safe coordinated delta cannot be guaranteed, retain full replacement—the phase
does not block earlier gains.

## Phase 10 — offload residual long tasks only if needed

**Risk:** high/conditional. **Dependencies:** profile/release measurements after
phases 1–8; phase 9 is not mandatory.

1. Identify remaining UI-thread tasks exceeding the frame budget after removing
   redundant work. If none remain material, do not add worker infrastructure.
2. Prefer bounded cooperative chunks for simple sweeps or a dedicated browser
   worker for substantial pure parsing/calculation. Flutter web `compute` alone
   is not a worker guarantee. Keep worker messaging and transfer costs measured.
3. Pass primitive immutable data; preserve exact minor units and Decimal precision
   during serialization. Keep credentials, OAuth, browser locks, and Sheets writes
   in their existing controlled layer.
4. Use operation generations to reject stale results; support cancellation and
   deterministic errors. Never publish half-calculated history, and revalidate
   source freshness before any write after a long calculation.

**Correctness gate:** synchronous/worker outputs match exactly; cancellation,
navigation, rapid refreshes, concurrent saves, late responses, worker failure,
fallback behavior, and peak memory tested. No overlapping-generation publication.

## Audit coverage map

| Audit finding | Planned phase(s) |
|---|---|
| 1. Quadratic maintenance FX searches | 1 |
| 2. Redundant transaction-save reads | 2 |
| 3. Repeated startup reads/reconciliation | 2 |
| 4. Synchronous UI-thread bursts | 1–4, then conditional 10 |
| 5. CSV encode/decode pipeline | 3 |
| 6. Eager/redundant snapshot indexes | 4 |
| 7. Page teardown on reload | 5 |
| 8. Manual/category/allocation history scans | 1, 6 |
| 9. Chart hover rebuilding geometry | 6 |
| 10. Transaction control/row rebuilds | 4, 5 |
| 11. Serial historical FX fetching | 8 |
| 12. Broad derived writes/preference initialization | 2, 3, gated 9 |
| 13. Duplicate milestones/hidden tickers | 5, 7 |
| 14. Overview/accounts/migration repeated scans | 7 |
| 15. Local CSV read/write and batch costs | 7 |
| Cross-cutting cache/memory growth | 0, 4, 6, 10 |

## Delivery order and release gates

Recommended order: **0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8**, then decide from
measurements whether phases **9/10** justify their added risk. Smaller independent
tasks can ship as separate changes, but may not bypass their correctness gates.

For every implementation change:

1. All existing tests plus new differential, workflow, and regression tests pass.
2. `flutter analyze` and formatting/diff checks pass.
3. Run `tool/check_coverage.sh`: retain at least 80% application logic coverage
   and 90% on its explicitly gated financial files. Also run
   `tool/analyze_financial_coverage.sh`: retain at least 95% line coverage per
   financial source file in each isolated feature/flow and the shared financial
   adapters; report branch coverage separately. Do not move financial logic out
   of a measured scope to improve its score.
4. Run the opt-in VM/Chrome benchmark on identical fixtures, including construction,
   allocations, and peak memory—not just isolated lookup speedups.
5. Compare deterministic operation/read/write counts. Keep wall-clock timing out
   of flaky ordinary unit-test pass/fail thresholds.
6. Build release web with the existing base path and run browser smoke tests on
   compact/desktop layouts. Use a disposable test Sheet for write-path integration;
   do not benchmark destructive rebuilds against the user's real Sheet.
7. Capture the relevant profile/release scenarios. Target smooth 60 Hz interaction
   (16.7 ms frame budget; 8.3 ms at 120 Hz) on the reference device; record actual
   p50/p95/max and remaining outliers instead of claiming a universal guarantee.
8. Verify no incorrect financial result, stale-cache publication, lost selection,
   missing confirmation/error, duplicate write, or schema/storage expansion.
9. Ship with no data migration; keep each change revertible independently. A cache
   problem falls back to recomputation, an incremental-repair doubt to full repair,
   and an offload problem to the verified calculation path—not to partial results.

Success is a measured reduction in CPU bursts, redundant reads, allocations, and
unnecessary rebuilding **with identical valid financial outputs and preserved
workflows**. No plan can guarantee regression-free behavior in advance; these
gates are required to establish it before each change is released.
