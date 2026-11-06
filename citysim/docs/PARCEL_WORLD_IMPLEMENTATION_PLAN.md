# Parcel World — Technical Implementation Plan

**Status:** vertical slice implemented; regional terrain, long-run persistence resilience, and scale work remain.  
**Date:** 2026-11-03  
**Entry point:** `lib/main.dart` (run commands from the `citysim/` package folder)  
**Mechanics and features:** [Game Mechanics Plan](GAME_MECHANICS_PLAN.md)  
**Renderer performance:** [Rendering Performance](RENDERING_PERFORMANCE.md)

This document covers code architecture, data contracts, rendering, persistence, and engineering work. Player-facing rules and the product roadmap belong in the game mechanics plan.

## 1. Current technical status

- **Implemented:** standalone Flutter entry point; typed parcel-world state; versioned rules/content; reducers, queries, and validation; isolated persistence; deterministic fixture terrain; canvas-based isometric rendering; rule/widget/save tests.
- **Limitations:** terrain is an authored fixture, not a seeded regional generator. Local browser storage is not a decades-long archive. Sprite alignment, large-world performance, and long-run persistence need review.
- **Verified:** from the `citysim/` folder, `flutter analyze`, full `flutter test`, and `flutter build web` pass.

### Current source map

| Area | Source |
|---|---|
| Standalone entry | `lib/main.dart` |
| UI/controller and save dispatch | `lib/parcel_city_app.dart` |
| Coordinates and terrain | `lib/world/coordinates.dart`, `terrain_provider.dart` |
| Logical catalogue and sprite manifest | `lib/world/world_content.dart` |
| Immutable state and JSON codec | `lib/world/world_state.dart` |
| Derived indexes and graph queries | `lib/world/world_queries.dart` |
| Quotes and snapshot validation | `lib/world/world_rules.dart` |
| State transitions | `lib/world/world_reducer.dart` |
| Persistence/write coordinator | `lib/world/world_save_store.dart` |
| Isometric canvas, camera, hit testing | `lib/rendering/parcel_world_view.dart` |

Keep behavioral acceptance cases in the [game mechanics plan](GAME_MECHANICS_PLAN.md); do not duplicate its feature descriptions or tuning discussion here.

## 2. Runtime boundaries

```text
Flutter UI → reducer/rules → immutable world state
                  ↘ terrain/content/derived queries
Flutter UI → save repository/coordinator
world state + terrain queries + sprite manifest → renderer
```

- Keep state, reducers, rules, coordinates, terrain queries, and content independent of Flutter widgets and browser storage.
- Use the same rule functions for UI previews and committed reducer actions; disabled controls are not validation.
- Treat the state snapshot as authoritative. Connectivity, occupancy, reachability, and render chunks are derived indexes.
- Avoid empty abstractions or another generic game framework. Extract boundaries when they solve concrete testability, performance, or persistence needs.

## 3. World data and invariants

### Coordinates and sparse ownership

- Use signed integer `CellCoord(column, row)` and `ParcelCoord(x, y)`; cell-to-parcel conversion must use floor division, including negative values.
- Parcel dimensions are fixed per saved world; current data uses 8×8-cell parcels.
- Store owned parcels and entities sparsely. Do not allocate an infinite world array or let render-cache dimensions affect ownership.
- Define safe coordinate bounds and preserve camera precision at large coordinates. Generate only visible terrain and bounded query frontiers.

### Typed state and validation

Use typed records for parcels, roads, structures, bridges, active projects, events, and accounting. Validate:

- unique entity/project IDs and non-overlapping footprints/reservations;
- builder-slot range and uniqueness for active projects;
- total/funded project costs and wallet accounting (`earned - spent = wallet`);
- stable dates and road/bridge geometry and derived connectivity.

Events are session-only presentation state: they carry stable IDs, action
kinds, structured payloads, and readable descriptions, but they are not
persisted — storage is state (IDs, coordinates, construction stages), not
history. Do not emit an event per render or clock tick.

## 4. Terrain and derived queries

Terrain is authored content: `terrain.json` maps every parcel on the map
to grass or water, `ContentTerrainProvider` samples it (seed-independent
until detail layers land), and any parcel without an entry is open ocean
— unbuyable, unbridgeable, rendered as sea with natural coastlines.
There are no water-body identities or kinds beyond land/water.

Future work: the map editor (paint parcels, validate on save against
the current world), finer cell-level detail layers drawn on top of
parcel terrain, and regional generation beyond authored maps. Preserve
the stable provider API; keep shores independent of ownership order.

`WorldQueries` derives entity lookup, reservations, land reachability, road connectivity, and render-chunk groupings. Rebuild/update indexes after topology-changing actions. These are caches, not durable state. Keep land reachability and road connectivity separate, and avoid world-wide scans in paint/layout loops.

## 5. Reducer and rules contracts

- Reducer actions are deterministic and atomic: apply the whole transition or leave state unchanged.
- Validate numeric inputs and balances before producing the next snapshot.
- Keep rules independent of artwork. Logical footprints belong to content/rules; sprite bounds, anchors, and image variants belong to rendering metadata.
- Loaded snapshots use the same geometry and economy invariants as actions. Unsupported/inconsistent states fail visibly instead of being silently repaired.
- UI code handles tool selection and presentation, not a parallel rules implementation.

## 6. Rendering and asset constraints

- Keep rendering behind `ParcelWorldView`; camera transforms are separate from durable state, and hit testing follows visible draw order.
- Current projection uses 64×32 logical tiles. Render viewport bounds plus sprite overhang; avoid giant widget trees and per-frame scans of all entities.
- Preserve stable depth ordering for tall/multi-cell sprites; distinguish logical footprints from transparent image margins.
- Share image caching and report load/retry failures visibly.
- Derive road masks and shoreline sprites from logical neighbors; never store sprite filenames in durable state.
- Ambient animation (water shimmer, vegetation sway, road pedestrians) runs on a ticker-driven clock and repaints through the painter's `repaint` listenable. Ground, roads, and bridges are recorded into a cached `ui.Picture` keyed by world, camera, and image set, so per-frame work is limited to replaying that picture plus the animated layers. Ambient state is render-only: it is not persisted, does not touch rules, and the ticker is muted under reduced-motion preferences.
- Audit supplied sprite alignment for dirt paths, shore masks, and bridge axes/ramps. Do not invent construction art or use damaged sprites as construction stages; project progress is separate from final building art.
- Profile large worlds after terrain generation exists. Consider cached far-zoom summaries only when measurements justify them.

## 7. Persistence and storage design

Game data lives in four sheets — the analogue of the main app's table
storage, and the exact shape of the game's future Google Spreadsheet:

- **`UserData`** (`key,value`): seed, coins, coins_earned, coins_spent,
  simulated_date, high_water_date, last_checkin_date, checkin_count,
  construction_day.
- **`Tiles`** (`x,y,kind,status,detail,variant,facing,project`): one row
  per touched coordinate, keyed by global tile x/y (x = `CellCoord.column`,
  y = `CellCoord.row`). Roads carry their style, structures their model
  id/variant/door side at their origin (footprints derive from content),
  bridges one row per water cell (spans and ramps derive from geometry).
  Status is `planned` or `complete`; building funding amounts live on the
  project row. The `project` column names a **live** project only — it
  ties a half-funded road stretch's completed and planned tiles together
  so the reload can rebuild the path, its funding count, and the frontier
  order; a finished stretch drops the reference when its project row is
  deleted (project numbers restart once no project is active, so a stale
  reference would collide with a later project's number).
- **`Parcels`** (`x,y`): owned parcel coordinates.
- **`Projects`** (`id,kind,detail,target,funded`): active projects only —
  rows are deleted as projects finish.

Everything else derives on load: parcel terrain re-samples the codebase
provider, road-plan order walks from the connected-road frontier, bridge
runs regroup into spans, unlocks and builder capacity come from
population, and entity counters come from the rows. Purchase receipts and
the dated check-in ledger are not reconstructible and not stored; the
check-in rule (high-water date + last check-in date) reproduces
no-backfill without a ledger.

**No versions are stored anywhere.** Content edits are live updates; the
editors validate them against the current save instead (terrain under
used cells cannot change unless cleared). Structural corruption still
fails loudly: the codec rejects unknown kinds/statuses, duplicate cells,
and orphan planned tiles before any derivation runs.

Current wiring: `ServerSheetParcelWorldStore` holds the world in
memory and reads/writes the four CSV documents through the editor
server (`GET/PUT /api/world`, selected by `assets/config.json`'s
`citysim.dataSource` and `citysim.serverUrl`). The server writes
`assets/test_sheets/*.csv`, which are the save and the crash-recovery
seed for a fresh browser. The Google Sheets data source (the game's own
spreadsheet, `citysim.spreadsheetId`) reuses the same codec and
documents; only the transport changes.

- Validate the complete decoded world before publishing it; corrupt data
  needs recoverable diagnostics and an explicit reset path.
- Serialize saves and resets through `ParcelWorldSaveCoordinator`; a
  generation token prevents stale queued writes from undoing reset.
- Save after state transitions, not render frames. Surface quota/write
  errors and allow retry.

## 8. Development and preview isolation

The game is a self-contained Flutter package in `citysim/` — it declares its
own dependencies, assets, and tests, and shares nothing with the root
Accountable package. All commands below run from the `citysim/` folder.

Run the game preview with the editor server it saves through:

```sh
dart run tool/run_game.dart
```

This starts the server on 9200 (reusing one that is already running)
and the preview on 9101, stopping the server it started when the game
session ends. Plain `flutter run -d web-server --web-port=9101` still
works when a server is already up.

Accountable's development port is 9000. Do not stop or reconfigure it to launch the preview. If 9101 is occupied, choose another explicit port rather than terminating an unrelated process. The city-sim stays synthetic: no OAuth, Sheets, transaction reads, or financial writes. Do not automatically restart a preview server the user has stopped.

The content editor dashboard (see the [content editor plan](CONTENT_EDITOR_PLAN.md)) runs on port **9200** via `dart run tool/content_editor/server.dart` (also from `citysim/`), localhost-only, and never touches ports 9000/9101.

## 9. Remaining engineering work

Agreed priority order: **wire the Google Sheets data source, then build the world map editor** — the remaining items ride on those.

### Google Sheets data source

The storage redesign landed: four CSV sheet documents (UserData, Tiles,
OwnedParcels, Projects) persisted locally through `CsvSheetParcelWorldStore`,
with the codec deriving everything else from codebase content. Remaining
work: create the real spreadsheet with the four tabs and headers above,
move `citysim.spreadsheetId` off the empty string, and implement the
Sheets `SheetSource`/store (upserts keyed by id, appends for tiles,
delete-on-completion for project rows, outbox with uncertain-write
reconciliation — the main app's transaction outbox is the pattern).
Until then local browser storage remains the medium and is not a
long-term archive.

**Local storage is never uploaded.** The sheets store reads only the
spreadsheet; an empty spreadsheet means a fresh world, and data written
by the CSV-mode store is never migrated or pushed. (Writes made while in
sheets mode that fail mid-sync still retry through the outbox — that is
the sync, not a migration.)

### World map editor and terrain design

Today's geography is a code fixture: infinite featureless grass with three hardcoded water features (a river column at x=12, a 4×4 western lake, an eastern ocean rectangle). Decisions made:

- **Authored content first.** Terrain becomes data — a terrain category in the JSON content layer, editable in the dashboard, git-tracked, backed up by the editor server — read by the provider. Seed-based detail variation (puddles) stays in code. Infinite procedural generation beyond the authored map is a later phase; it is the hardest part to make good (rivers that read as rivers, coastlines worth buying) and is not needed until players push past the authored region.
- **Terrain derives from content; there are no snapshots.** Purchased
  parcels re-sample the provider on load, so a map edit is a game update,
  not a save migration. The protection runs in the editor instead:
  terrain under *used* cells — roads, bridges, structures, and planned
  reservations — cannot be edited unless those cells are cleared.
  Owned-but-vacant land stays editable. The same validate-against-save
  rule extends to other content editors (a model's footprint cannot
  change while structures of that model are placed).
- **Parcel-level map, ocean by default.** Terrain is a parcel → grass/water map in `terrain.json`; any parcel without an entry is open ocean — rendered as sea, unbuyable, unbridgeable. There are no water-body entities or water kinds; cell-level detail layers come later on top of parcel terrain.
- **Starter-experience guarantees as editor validation.** The starter parcel (0,0) must be authored as grass — already enforced by content validation; the editor's map page hard-locks it.

Landed: the terrain content schema and provider-from-content (a
49-parcel starter map with east and west water channels), the bridge
relaxation (any authored water, straight line, land banks, no span cap),
buyable water parcels with ownership decoupled from access, constant
parcel pricing, and the editor MVP — the Map page: an isometric canvas
of authored parcels with + growth on void-facing edges, kind
re-typing and deletion with locks (occupied cells block both, ownership
blocks deletion, the starter parcel is always locked), occupied-cell
grey-out from the current save (`/api/world/summary`, with structure
footprints and bridge spans expanded), and save-time validation refusing
terrain edits under occupied cells. The dashboard warns at startup to
stop the game before editing. Remaining: cell-level detail layers and
regional generation.

### Concurrent editing protection (future work)

A running game holds content in memory from startup. If the editor saves
content underneath it, the still-running game keeps acting on the old
content and pushes worlds that can be invalid under the new content
(roads on now-water parcels, structures with now-changed footprints) —
the save then fails loudly on next load. Interim protection: the
dashboard warns at save time to make sure the game is not running
anywhere, and save-time validation refuses terrain edits under occupied
cells. Proper protection is future work: an exclusive live-game session
arbitrated by the save store. In CSV mode the local server holds the
session (the game heartbeats ~10s; the dashboard refuses content saves
while the session is live). In Sheets mode the lock lives in the
spreadsheet (the game heartbeats a lock row; the editor reads it before
saving content, using the main app's Sheets auth). Only the editor is
blocked — the game never needs blocking: the two write different files
through a single-threaded server, and save-time validation covers the
reverse direction.

### Content breadth

Phase E asset browser (see the content editor plan) promotes the ~470 unused pack files into the organized sprite tree; afterwards new models, subcategories, and deeper population-gate tiers are dashboard-only work. The catalogue currently tops out at unlock population 20 with nine models.

### Rendering validation and scale

Manually audit terrain/road/shore/bridge artwork. Profile representative large worlds and record frame, update, memory, and save costs before adding caches or changing the rendering engine — run this during the map-editor work, since authored maps grow the world faster than the fixture did.

### Selection and occluded-target picking

Taps currently hit the frontmost structure whose sprite *bounding rectangle* contains the point — transparent sky included — so buildings steal taps from roads peeking out beside or behind them, and fully occluded targets (a road behind a dense block of houses) cannot be selected at all. Camera rotation is not an option (fixed-view art, no back facings). Planned techniques, in the order they should land:

- **Per-pixel picking.** Cache one byte of alpha per image pixel alongside the image cache (computed after load; picking falls back to rectangle hits until a mask arrives). A structure is only a tap candidate when the point lands on an opaque pixel, with a small (~3 image-pixel) neighbourhood so thin art — antennas, poles — stays clickable.
- **Click cycling.** Repeated taps at the same world spot (within roughly a quarter tile and a few seconds) cycle front-to-back through the candidates — the front structure, then what it hides, then the ground cell — and wrap. Selection outlines already paint above structures, so the cycled target stays visible.
- **Tool-based pick priority.** Only the inspect tool should pick structures; the road, parcel, bridge, and placement tools target cells directly, since no one wields the road tool intending to select a house.
- **X-ray dimming.** While the road or bridge tool is active, render structures at reduced opacity so fundable tiles and banks behind buildings are visible as well as tappable.

### Regression checks

Maintain pure rule/reducer coverage, persistence tests, and responsive widget checks. Keep scenario/pacing tools synthetic and separate from the production finance app.

## 10. Required verification

Run from the `citysim/` folder (the root Accountable package has its own
separate checks):

```sh
flutter analyze
flutter test
flutter build web
```

Also verify negative-coordinate conversion; atomic quote/reducer behavior; wallet receipt reconciliation; JSON/store round-trips for funded projects and reservations; visible failure for unsupported schemas; stable road/bridge connectivity; camera gestures that do not trigger purchases; desktop/mobile hit testing; and city-sim preview isolation from port 9000.
