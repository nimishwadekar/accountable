# Performance audit

Date: 2026-10-29. Audited revision: `e5394c8`.

## Summary

**650 transactions should not, by itself, be a large workload for this app.**
The largest confirmed costs are loading/parsing *all derived history* repeatedly
and recomputing that history with linear exchange-rate searches inside daily
loops. History length and account count matter much more than transaction count
for these paths. The recent balance feature adds avoidable eager work, but it is
not the largest measured cost.

The transaction list is already virtualized. An isolated test mounted only 6–8
transaction rows with 650/6,500 transactions. This audit does **not** establish the
cause of sustained scrolling jank in the deployed app: that still requires a
profile/release browser trace on the affected device.

No production behavior was changed. Added an opt-in synthetic diagnostic at
`test/performance/performance_audit_test.dart`.

### Relationship to the earlier analysis

The existing `PERFORMANCE_ANALYSIS.md` and `PERFORMANCE_IMPLEMENTATION_PLAN.md`
describe an older implementation and are left unchanged. Several of their main
recommendations are now implemented: pre-sorted/indexed transactions, cached
filters/grouping, lazy row construction, visited-tab retention, memoized analysis,
and cached ledger balances. Their claims that the current transaction list sorts
on every build or that ordinary tab switches always recreate page States no
longer apply. Data-reload teardown is a separate remaining problem.
The historical Chrome trace referenced by that plan is not present in this
checkout, so its summary was not used as fresh profiling evidence.

## Method and limitations

- Static review: startup/authentication, Sheets I/O, parsing/validation, snapshot
  indexes, transaction entry/filtering/scrolling, overview/accounts, migration,
  analysis calculations/charts, milestones, and local persistence.
- Synthetic fixtures: 650 or 6,500 transactions; 30, 365, or 1,095 days; eight
  ledger accounts, two manual accounts, three currencies; 10% transfers; manual
  valuations every 30 days; complete existing rates and derived tables.
- Fixtures contain no real financial data. Sheets and HTTP are mocked. No remote
  reads or writes are performed. Reconciliation is measured on an already-correct
  dataset, and the harness verifies it performs no writes.
- Apple M3 Pro; Flutter 3.47.7 / Dart 3.13.5. Two warm-ups and five samples per
  operation; reported values are medians, not production latency guarantees.
- VM tests include debug/assertion overhead. Browser tests also use a test build,
  not the deployed optimized bundle. Widget pump times are **not FPS, raster
  timings, or real browser scrolling measurements**. Initial widget mounts have
  different font/framework warm-up costs and should not be compared as a scaling
  result. Small synthetic category/tag lists underrepresent complex real filters.
- Network RTT, Google authentication, JSON response decoding, DOM/browser/GPU
  contention, and actual Sheets payload sizes are not included in the in-memory
  repository timing.

Reproduce:

```sh
flutter test test/performance/performance_audit_test.dart --dart-define=PERFORMANCE_AUDIT=true --reporter expanded
flutter test test/performance/performance_audit_test.dart --dart-define=PERFORMANCE_AUDIT=true --platform chrome --reporter expanded
# Add --dart-define=PERFORMANCE_STRESS=true for 10k/50k/100k transaction runs.
```

Diagnostics are skipped in normal test runs. There are no fragile timing gates.

### VM measurements (milliseconds)

| Operation | 650 / 30 days | 650 / 365 days | 650 / 1,095 days | 6,500 / 365 days |
|---|---:|---:|---:|---:|
| Snapshot construction, all indexes | 1.14 | 1.27 | 3.08 | 5.80 |
| Full repository reload, zero network latency | 12.77 | 46.73 | 138.41 | 123.60 |
| Reconcile an already-correct dataset | 2.60 | 31.43 | 230.24 | 31.19 |
| Manual-account all-history series | 0.08 | 2.15 | 15.93 | 1.91 |
| Latest-month category spending | 1.03 | 0.43 | 0.41 | 4.00 |
| Strict transaction parser | 3.29 | 2.61 | 2.52 | 29.86 |
| Issue-collecting transaction parser | 7.27 | 6.67 | 6.74 | 69.19 |
| Daily ledger FX lookups alone, current algorithm | 0.20 | 18.40 | 169.71 | 18.31 |
| Same lookups using a prebuilt map, candidate only | 0.12 | 0.18 | 0.34 | 0.11 |

At 650 transactions, increasing history from one to three years made no-op
reconciliation approximately **7.3× slower**. Increasing transactions tenfold
without increasing history left reconciliation essentially unchanged. That is
consistent with the quadratic history-dependent lookup identified below.
The candidate lookup measurement excludes map construction and does not represent
an implemented or end-to-end reconciliation speedup.

### Chrome JavaScript test measurements (milliseconds)

| Operation | 650 / 30 days | 650 / 365 days | 650 / 1,095 days | 6,500 / 365 days |
|---|---:|---:|---:|---:|
| Snapshot construction, all indexes | 3.10 | 5.50 | 11.90 | 31.10 |
| Full repository reload, zero network latency | 30.60 | 111.70 | 291.70 | 299.50 |
| Reconcile an already-correct dataset | 7.80 | 203.20 | 1,279.10 | 194.00 |
| Manual-account all-history series | 0.70 | 17.20 | 105.10 | 17.70 |
| Latest-month category spending | 7.80 | 2.90 | 2.60 | 29.30 |
| Strict transaction parser | 5.30 | 5.10 | 5.10 | 55.20 |
| Issue-collecting transaction parser | 16.80 | 16.20 | 16.30 | 175.50 |
| Daily ledger FX lookups alone, current algorithm | 0.60 | 92.20 | 806.50 | 89.20 |
| Same lookups using a prebuilt map, candidate only | 0.20 | 2.60 | 7.20 | 2.30 |

The browser reproduces the same history-dependent scaling. A no-change repair
can consume over a second of CPU in this test runtime with only 650 transactions.
The issue-collecting parser is about **3.2×** the strict parser cost here.
Preindexed FX lookup alone improves about 112× at three years, but conversion,
other calculations, index construction, parsing, and network work still remain.

The 20-step scroll diagnostic took 190 ms at 650 transactions and 230 ms at 6,500
(including reset, test pumps, and row creation). Mounted rows remained under 40.
That supports bounded list construction, **not** a claim of smooth production FPS.

## Prioritized findings

### 1. High: daily reconciliation has quadratic history-dependent FX work

`lib/data/repositories/daily_maintenance_service.dart:477–513, 535–545, 615–625`

`_balancesThrough` iterates dates and ledger accounts. For every account/day it
calls `rateFor`, which uses `rates.lastWhere` over the entire rate history.
Manual-account contributions in `_netWorthThrough` use the same search.
Matching-currency candidates also allocate normalized `DateTime` objects.

Let D = days, A = ledger accounts, U = manual accounts, C = currencies, and
R ≈ D×C = exchange-rate rows. FX lookup work is O(D×(A+U)×R), or
**O((A+U)×C×D²)** with daily rates. Decimal conversion adds legitimate O(D×A)
work, but does not justify repeatedly searching history.

**Recommendation:** build a `(date, currency) → rate` index once per calculation;
use exact-date lookups for maintenance. This reduces the FX portion to
O(R + D×(A+U)). Keep its exact-date semantics; analysis's latest-on-or-before
lookup is a different operation.

### 2. High: one transaction save performs four full repository reloads

`lib/app/app_shell.dart:599–665`
`lib/app/google_sheets_gate.dart:456–466`
`lib/data/repositories/google_sheets_repository.dart:755–780`

Normal authenticated transaction save, excluding retries:

1. AppShell reloads all tables before writing.
2. Repository appends and returns an updated in-memory snapshot.
3. Reconciliation callback reloads all tables again.
4. Reconciliation recomputes all history, even if the transaction is today.
5. Callback reloads all tables after reconciliation and writes the form cache.
6. AppShell reloads all tables once more to display the result.

That is **four full-table batch reads**, one append, and potentially a derived
table replacement. Each full read requests 14 ranges, or 15 with migration enabled,
including every daily balance, exchange rate, and net-worth row. This is four
batch requests, not four requests per table.

At the three-year synthetic size, four VM reloads plus one reconciliation imply
roughly 0.78 seconds of local work, *before network latency*. This is a composition
of separate medians, not a measured end-to-end save time.
The equivalent Chrome test composition is about **2.45 seconds**; the one-year
Chrome composition is about **0.65 seconds**. Optimized release builds and actual
datasets/devices will differ.

**Recommendation:** make the write/reconcile pipeline own and return the final
snapshot. Preserve the fresh pre-write validation and retry/duplicate protections;
reuse the post-append snapshot where safe, and do at most one necessary final
verification read rather than discarding intermediate results.

### 3. High: startup repeats reconciliation and performs five full reads

`lib/app/google_sheets_gate.dart:473–519, 598–621`

Even with an empty outbox, startup loads once, reconciles, reloads, then enters
`_synchronizeOutboxAndTransition`, which calls the reconciliation callback
(two more reloads and another reconciliation), and finally reloads once again.
Total: **five full snapshot reads and two full reconciliations** on the ordinary
empty-outbox path, before transitioning online. Outbox batches add further reads.
The six-table form cache intentionally does not contain transaction history, so
it does not avoid this work.

**Recommendation:** track whether outbox synchronization actually changed source
data. Reconcile once against the final source snapshot and pass that snapshot
into the online transition/cache write. Avoid an unconditional second cycle.

### 4. High: all-history synchronous work runs on the UI execution thread

`lib/data/repositories/daily_maintenance_service.dart:161–237`
`lib/data/repositories/google_sheets_repository.dart:449–743`

These functions are `async`, but parsing, sorting, date loops, FX searching, and
conversion are synchronous. With all rates present, reconciliation can run all
the way to its no-op return without yielding. The measured 230 ms VM calculation
is far beyond a 16.7 ms frame budget. Network waits do not themselves block
frames; these CPU bursts do.

**Recommendation:** first eliminate redundant work and fix the algorithms. Then
profile remaining long tasks; consider bounded chunks or a dedicated worker for
browser CPU work. Merely adding `async`, `Future`, or Flutter web `compute` is not
a guarantee that work moves off the browser's UI thread.

### 5. High/medium: every Sheets reload re-encodes and re-parses every row

`lib/data/repositories/google_sheets_repository.dart:482–698, 816`
`lib/data/csv/model_parsers.dart:13–62, 114–130, 185–218`
`lib/data/csv/csv_table.dart:11–44`

Pipeline: Sheets row arrays → padded arrays → whole-table CSV → decoded row maps
→ for each row, encode header + row into another CSV string → call a strict
parser that decodes that tiny CSV again → create domain model.

This is **linear**, not quadratic, for fixed column widths, but creates substantial
temporary strings, headers, maps, and parser objects across all derived rows.
The issue-collecting transaction parser measured roughly 2.2–2.7× the strict
parser cost. At three years there are ~13,900 total fixture rows despite only 650
transactions. The full reload costs much more than transaction parsing alone.

**Recommendation:** extract row-to-model functions shared by strict and
issue-collecting parsers. Preserve row numbers, accumulated issues, dependency
validation, and duplicate checks without serializing each row back to CSV.
Ultimately accept normalized Sheets rows directly instead of the outer CSV hop.

### 6. Medium: a tiny mutation rebuilds unrelated snapshot indexes eagerly

`lib/data/app_data_snapshot.dart:20–100, 142–186, 282–361`

Each constructor copies/indexes all tables and sorts all grouped histories.
Transactions are sorted twice: descending for display and ascending for running
balances. Running-balance sorting creates two date-only objects per comparison,
then replays transactions a second time after the separate final-balance pass.
These indexes are computed even when balances are hidden. `withAchievements`
also recreates everything when only an earned flag changes.

**Recommendation:** share unchanged immutable indexes across snapshot updates;
make expensive optional indexes lazy; use one canonical transaction order and
derive/reuse it for display, final balances, and running balances. Check visibility
before requesting optional row data. There is no need to store all accounts'
balances for every transaction: the current affected-account-only storage is good.

The recent `e5394c8` balance change introduced this additional eager chronological
sort/replay. Nevertheless, the *entire* 650-transaction snapshot constructor was
only 1–3 ms in these VM measurements. It is a real optimization opportunity, not
evidence that the balance feature alone explains multi-second delays.
In the Chrome test it was 5.5 ms at one year and 11.9 ms at three years, so eager
reconstruction is more consequential there, especially when repeatedly invoked.

### 7. Medium: loading a new snapshot tears down every visited page

`lib/app/app_shell.dart:352–393, 599–665`

Mutation paths clear `_pageCache` and replace `_snapshotFuture`. During waiting,
`_buildContent` returns `AppLoadingPage` even when FutureBuilder retains old data.
This removes the IndexedStack and its page States. The intermediate post-append
snapshot and final reload can repeat this cycle. Since `_visitedSections` is
retained, **all previously visited pages** are recreated afterward, including
offscreen analysis charts and their discarded calculation caches.

**Recommendation:** keep valid existing content mounted while saving/refreshing;
show localized progress and update immutable data in place. Invalidate only caches
whose inputs changed. Do not expose stale derived history as current or celebrate
milestones before repair is complete.

### 8. Medium: manual-account and categorical analysis repeatedly scan history

`lib/features/analysis/analysis_calculator.dart:128–184`
`lib/features/analysis/category_analysis.dart:142–170`
`lib/data/repositories/daily_maintenance_service.dart:632–645`

Manual chart generation scans all valuations for *every day*, then scans rates
from the beginning for every day. Cost is O(D×(V + R_currency)). It calculates USD
values even when the chart is displayed in native currency. Maintenance also
rescans an account's valuation history for every net-worth date. Categorical
analysis scans the currency's historical rates anew for each non-USD transaction:
O(N_month×R_currency).

**Recommendation:** binary search for isolated latest-on-or-before queries; use
monotonic valuation/rate cursors for chronological daily sweeps. Cache conversions
by currency/date, and avoid building USD series until needed. `AnalysisPage`
already caches series, but its account-series cache key includes display unit
even though both units are calculated together, duplicating work when switching.

`lib/features/analysis/income_allocation_analysis.dart:24–82` still scans the
selected month's transactions twice per applicable allocation. The category
section invokes it while building income rows, outside AnalysisPage's result
cache (`category_analysis_section.dart:217–223`). That is O(L×N_month) transaction
work for L applicable allocations per build, not a whole-history scan anymore.
Compute monthly income counts and transfer totals once and memoize the result.

### 9. Medium, needs browser profiling: chart hover rebuilds the whole chart

`lib/features/analysis/analysis_chart_widgets.dart:142–267, 279–403, 591–638, 775–795`
`lib/features/analysis/analysis_page.dart:357–428`

Pointer selection has two paths: MouseRegion/Listener and fl_chart's touch
callback. The latter calls `setState` without checking whether selection changed.
Rebuilds rescan points, reconstruct every `FlSpot`, find the nearest point
linearly, compute overlay conflicts, and lay out axis labels with TextPainters
twice. A ValueNotifier exists, but whole-chart `setState` negates much of its
benefit. Parent analysis rebuilds also recreate chart-point lists and convert
Money through Decimal even when cached series are unchanged.

**Recommendation:** one input path, selection-change guard, cached static chart
geometry/axis metrics/spots, binary search of point offsets, and a separately
updating selection overlay. Consider preserving extrema with downsampling only
for long display ranges. This affects analysis, not ordinary transaction scrolling.

### 10. Medium/low: broad transaction-page rebuilds and variable row geometry

`lib/app/pages/transactions_page.dart:337–417, 591–603`
`lib/app/pages/transaction_list_widgets.dart:68–118, 166–204`

- The scroll listener calls page-wide `setState` when crossing 300 px, rebuilding
  desktop dropdowns and mounted rows just to show/hide an arrow. It does **not**
  do this on every scroll event; the existing threshold guard is correct.
- Balance toggle similarly rebuilds filters and visible rows and changes row
  heights. Variable-height rows/date headers need layout, and scroll-to-top uses
  a fixed 300 ms animation regardless of distance.
- Each amount requests a cached balance even when hidden, but that is an O(1)
  lookup, **not a transaction-history scan**. Money formatting uses Decimal and a
  regular expression; measured formatting of all 650 amounts was only ~1.3–1.9 ms
  in the VM, while the actual list formats a small visible/cache subset.
- Cards use hard clipping and contain several text/layout widgets. Their theme
  has zero elevation, so there is no basis for blaming hundreds of card shadows.

**Recommendation:** isolate arrow visibility with a notifier/builder and keep
filters out of row-only rebuilds. Cache immutable row presentation if a profile
shows formatting/layout is hot. Evaluate extent hints for predictable rows and a
long-distance jump-to-top policy; do not force one fixed height that clips transfer
balances, wrapped text, or accessibility scaling. Do not build all rows or add
pagination merely to compensate for unrelated reconciliation delays.

### 11. Medium: historical FX fetching is serial and can cause very long waits

`lib/data/repositories/daily_maintenance_service.dart:181–207, 301–308, 428–454`

Missing dates are fetched one at a time. Full rebuild fetches every historical
day, including USD-only days where the rate is always one, and does not reuse
existing rates. Each date can try up to 31 backward dates, with no explicit HTTP
timeout. Repeated weekend/source dates can cause redundant requests. This is
network latency rather than continuous CPU blocking, but startup waits for it.

**Recommendation:** synthesize USD=1, reuse valid existing rates where appropriate,
cache source-date responses, use provider-supported historical ranges or bounded
concurrency, add timeouts/retry policy, and expose progress. Preserve deterministic
daily IDs and existing source-date/coverage semantics; don't blindly parallelize
thousands of requests or bypass provider limits.

### 12. Medium/low: full-history writes and serial preference initialization

`lib/data/repositories/daily_maintenance_service.dart:209–236`
`lib/data/sources/google_sheets_api.dart:108–169`
`lib/data/repositories/google_sheets_repository.dart:534–546`

Any derived discrepancy replaces all three derived tables, including unchanged
rates. `replaceRanges` first rereads the complete tables to discover their old row
counts. Single-range replacement similarly performs a full read before updating.
Missing display preferences are appended in a serial per-entity loop during load.

**Recommendation:** batch missing preference rows. Update only changed derived
ranges/tables and safely clear obsolete tails; use already-known row counts only
where freshness guarantees permit. Ordinary app-owned writes can repair from the
earliest affected date, while external edits/deletions still need reliable source
change detection and a full-repair fallback. Transaction count alone is not a
sufficient change detector.

### 13. Low: duplicate milestone evaluations and broad retained-page scope

`lib/data/repositories/google_sheets_repository.dart:718–743`
`lib/app/app_shell.dart:203–223, 376–393, 698–715`
`lib/features/milestones/milestones_page.dart:53–84`

The repository evaluates achievements; AppShell evaluates again and immediately
reevaluates even when there were no reset writes; the milestone page evaluates
again when created. Cost is O(D log D + K×M), where K is milestones and M completed
months. Usually small, but repeated on top of the reload pipeline.

Visited pages remain in an IndexedStack. Cached widget identity avoids ordinary
whole-page rebuilds on every navigation, but children remain mounted, retain
caches, and can still be laid out on stack relayout. IndexedStack does not itself
disable hidden tickers. The pending-milestone navigation pulse also intentionally
schedules continuous animation frames, with an AnimatedBuilder-local rebuild.
It does **not** imply the entire transaction list is rebuilt every animation tick.

**Recommendation:** share milestone evaluation per snapshot/date and skip the
second evaluation if nothing changed. Use explicit TickerMode for inactive
sections and verify hidden-chart layout/animation in a trace before redesigning
page retention. Avoid losing useful cached state as a side effect of optimization.

### 14. Low: overview/accounts and migration have avoidable repeated scans

`lib/app/pages/app_pages.dart:15–24, 249–345, 749–757`
`lib/app/pages/assets_liabilities_page.dart:19–47, 125–127, 163–179, 383–391`
`lib/data/repositories/migration_transactions.dart:43–78`
`lib/features/migration_assistance/migration_assistance_page.dart:86–89, 338–356`

- Account rows scan *all* manual valuations instead of using the already-sorted
  per-account index's last applicable point: O(U×V_total).
- `_assetLiabilityAccounts` filters/allocates a new list in every loop-condition
  and indexed access: O(A²) even before building rows. Capture it once per build.
- Manual valuation eligibility scans all valuations for each account; deterministic
  account/date lookup can replace it. Finding the default date sorts every
  valuation when a max scan suffices.
- Overview repeatedly scans/re-groups daily net worth on build.
- Migration status sorts all main/migration dates just to find min/max, and
  reserializes matching transaction pairs on every page build; cache by snapshot.
  Migration drill-down filtering/sorting is per-open, but its list is lazy.

These are worth cleaning up, but small account/milestone/category counts make them
unlikely to dominate the 650-transaction case.

### 15. Local CSV mode: whole-dataset reads write it back; batched appends rescan

`lib/data/repositories/asset_repositories.dart:420–440, 586–685, 716–721`
`lib/data/sources/local_dataset_store.dart:18–46`

Reading an existing dataset decodes every CSV to check headers, then writes the
whole dataset back even if no migration occurred, before parsing it again.
Appending B transactions decodes/re-encodes the growing Transactions CSV B times:
O(B×N + B²) row work. This path is separate from authenticated Sheets mode.

**Recommendation:** validate/migrate only when necessary, persist only changes,
and decode/append/encode a batch once. The transaction form snapshot is small
metadata, so it should not be confused with a cache of the full online ledger.

## What is already efficient / what this does not justify

- `ListView.separated` builds visible/cached rows, not all 650 transactions.
- Transaction filters are O(N) **on input/snapshot change** and reuse results on
  unrelated rebuilds. Date headers/grouping also cache their flattened list.
- Account/category/tag and per-transaction balance reads are indexed O(1).
- Month/date transaction indexes avoid repeated whole-ledger scans in analysis
  and maintenance. Analysis series/category results are memoized per page.
- No periodic auto-refresh loop or per-scroll Sheets request was found. Startup,
  saves, explicit refresh/rebuild, and outbox synchronization invoke expensive
  operations; idle scrolling does not invoke reconciliation by itself.
- Browser locks and duplicate verification serve data-integrity requirements.
  Remove redundant work inside the workflow, not these protections wholesale.
- Error dialogs, thousands-separator input formatting, and partial valuation
  entry do not introduce loops over transaction history during normal scrolling.

## Recommended sequence

1. Index maintenance FX lookups; cursor/binary-search latest valuation/rate queries.
2. Consolidate startup/save/reconcile into one snapshot-returning pipeline; add
   tests for read counts and no-op repair. Preserve manual-Sheet-edit detection,
   backdated transaction repair, retry idempotence, and outbox safety.
3. Remove CSV serialization from per-row validation while retaining diagnostics.
4. Keep pages mounted across writes; selectively invalidate indexes/calculations.
5. Make optional running balances lazy/share canonical order; isolate transaction
   control rebuilds. Optimize chart selection independently.
6. Add incremental derived updates, FX batching, and worker/chunking only after
   measuring the simpler changes.

Selective cache/index sharing would refine the older plan's conservative
invalidate-everything-on-snapshot-replacement contract. Only reuse immutable
results with proven unchanged semantic dependencies; until that is tested, retain
the conservative invalidation rather than risk stale financial data. Keep all
indexes memory-only and preserve exact daily chart values and point selection.

### Memory/scaling considerations

With D dates and A ledger accounts, daily balances occupy O(D×A) rows; rates
occupy O(D×C), even when transaction count is constant. Snapshots retain original
model lists plus maps and per-account/per-date list references. The running
balance index adds at most two entries per transaction, O(N), not O(N×A).
Parsing adds temporary CSV strings/maps on top of these retained objects. Visited
analysis pages retain every queried series in their calculation cache until
snapshot change; overlapping ranges and duplicate unit keys can retain overlapping
point lists. Profile retained heap before adding more indexes or a general cache;
no permanent memory leak has been established by this audit.

## Profile the remaining reported lag before attributing it to rendering

Use the same affected browser/device with a profile/release build, not `flutter
run` debug mode. Record separately:

1. Cold start with empty outbox and complete historical tables.
2. Opening Transactions with 650 rows, without fetching or saving.
3. Steady scroll with balances hidden, then shown; long-distance return to top.
4. Same scroll after visiting Analysis and selecting MAX history.
5. Current-date save vs backdated save; explicit refresh with no source changes.

Capture CPU long tasks, allocation/GC, UI/raster frame timings where supported,
network request count/payload bytes, and retained widgets/heap after refreshes.
Add timeline spans around batch read, normalization/CSV parsing, snapshot
construction, milestone evaluation, reconciliation, and chart-series generation.
Measure p50/p95/max frame costs against 16.7 ms (60 Hz) or 8.3 ms (120 Hz).

This distinguishes a network wait, a main-thread history-repair pause, a page
recreation hitch, and sustained raster/layout jank. The current synthetic evidence
strongly supports the first optimization priorities, but does not substitute for
that end-to-end trace.
