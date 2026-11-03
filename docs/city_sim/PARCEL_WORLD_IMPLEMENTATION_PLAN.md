# Parcel World — Technical Implementation Plan

**Status:** V2 vertical slice implemented; regional terrain, long-run persistence resilience, and scale work remain.  
**Date:** 2026-11-03  
**Entry point:** `lib/citysim/main.dart`  
**Mechanics and features:** [Game Mechanics Plan](GAME_MECHANICS_PLAN.md)

This document covers code architecture, data contracts, rendering, persistence, and engineering work. Player-facing rules and the product roadmap belong in the game mechanics plan.

## 1. Current technical status

- **Implemented:** separate V2 Flutter entry point; typed parcel-world state; versioned rules/content; reducers, queries, and validation; isolated V2 persistence with explicit V1-save detection; deterministic fixture terrain; canvas-based isometric rendering; rule/widget/save tests.
- **Limitations:** terrain is an authored fixture, not a seeded regional generator. Local browser storage is not a decades-long archive. Sprite alignment, large-world performance, and long-run persistence need review.
- **Verified:** `flutter analyze`, full `flutter test`, and `flutter build web --target=lib/citysim/main.dart` pass.

### Current source map

| Area | Source |
|---|---|
| Standalone entry | `lib/citysim/main.dart` |
| UI/controller and save dispatch | `lib/citysim/parcel_city_app.dart` |
| Coordinates and terrain | `lib/citysim/world/coordinates.dart`, `terrain_provider.dart` |
| Logical catalogue and sprite manifest | `lib/citysim/world/world_content.dart` |
| Immutable state and JSON codec | `lib/citysim/world/world_state.dart` |
| Derived indexes and graph queries | `lib/citysim/world/world_queries.dart` |
| Quotes and snapshot validation | `lib/citysim/world/world_rules.dart` |
| State transitions | `lib/citysim/world/world_reducer.dart` |
| V2 persistence/write coordinator | `lib/citysim/world/world_save_store.dart` |
| Isometric canvas, camera, hit testing | `lib/citysim/rendering/parcel_world_view.dart` |

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

- unique entity/event/project IDs and non-overlapping footprints/reservations;
- builder-slot range and uniqueness for active projects;
- total/funded project costs and completed purchase receipts;
- wallet accounting (`earned - spent = wallet`);
- stable dates and world/rules/content/terrain versions;
- road/bridge geometry and derived connectivity.

Keep receipts after project completion. Content-price changes must not rewrite past receipts or active funded totals. Events need stable IDs, action kinds, structured payloads, dates, and readable descriptions; do not emit an event per render or clock tick.

## 4. Terrain and derived queries

`DemoTerrainProvider` supplies deterministic grass plus authored river, lake, and coast fixtures. It is a preview fixture, not the final country generator.

Future generator work should preserve a stable provider API and pinned version; evaluate regional features in global coordinates; keep water-body identities stable; make shores independent of ownership/reveal order; and avoid rerolling acquired terrain. A usable start is required, but infinite land is not promised.

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

## 7. Persistence and compatibility

- V2 storage key: `citysim.parcel-world.v2`. V1 key: `citysim.prototype.v1`. V2 reset must never clear or write the V1 key.
- Current V2 JSON schema is 3; rules and content versions are 2. Timer-based schema-2 V2 snapshots are incompatible and are not automatically migrated. Report them as unsupported and leave them untouched unless the user explicitly chooses a V2 reset.
- Validate the complete decoded snapshot before publishing it. Corrupt/unsupported data needs recoverable diagnostics and an explicit reset path.
- Serialize saves and resets through `ParcelWorldSaveCoordinator`; a generation token prevents stale queued writes from undoing reset.
- Save after state transitions, not render frames. Surface quota/write errors and allow retry.
- Local browser storage is not a long-term archive. Evaluate export/import, storage diagnostics, multi-tab conflicts, and IndexedDB against measured needs.

## 8. Development and preview isolation

Run the standalone city-sim preview with:

```sh
flutter run -d web-server --web-port=9101 -t lib/citysim/main.dart
```

Accountable's development port is 9000. Do not stop or reconfigure it to launch the preview. If 9101 is occupied, choose another explicit port rather than terminating an unrelated process. The city-sim stays synthetic: no OAuth, Sheets, transaction reads, or financial writes. Do not automatically restart a preview server the user has stopped.

## 9. Remaining engineering work

### Regional terrain

Replace the authored fixture behind the existing provider API. Add seam, reveal-order, water-body identity, pinned-version, and reload tests.

### Long-term save resilience

Add backup/export and storage diagnostics before recommending local browser storage for years of daily use. Define migration policy before changing persisted schemas or generator versions.

### Rendering validation and scale

Manually audit terrain/road/shore/bridge artwork. Profile representative large worlds and record frame, update, memory, and save costs before adding caches or changing the rendering engine.

### Regression checks

Maintain pure rule/reducer coverage, persistence/compatibility tests, responsive widget checks, and V1-save-preservation tests. Keep scenario/pacing tools synthetic and separate from the production finance app.

## 10. Required verification

Run from the repository root:

```sh
flutter analyze
flutter test
flutter build web --target=lib/citysim/main.dart
```

Also verify negative-coordinate conversion; atomic quote/reducer behavior; wallet receipt reconciliation; JSON/store round-trips for funded projects and reservations; visible failure for unsupported schemas; V1 preservation; stable road/bridge connectivity; camera gestures that do not trigger purchases; desktop/mobile hit testing; and city-sim preview isolation from port 9000.
