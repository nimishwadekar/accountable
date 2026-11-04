# Parcel World — Content Editor Dashboard Plan

**Status:** design plan; no implementation yet.  
**Date:** 2026-11-03  
**Scope:** a JSON content layer for the parcel-world game plus a local editor dashboard, so progression (which models exist, what they cost, when they unlock) and art/animation parameters can be edited without touching Dart code.

## 1. Goals

- All game-content values live in JSON inside the repo; the game loads and
  validates them at startup. No content values hardcoded in code.
- A local dashboard on its own port presents the data by category with
  visual editing: sprite thumbnails, live animation previews with sliders,
  numeric fields with validation.
- Editing content must never silently break existing saves — the dashboard
  warns, validates, and keeps backups.
- V1 data contains only what the game currently uses. Browsing the rest of
  the asset pack to enable new art comes later.

### Non-goals (V1)

- No terrain/world-template editing — a dedicated **world map editor is the
  planned next project after this asset editor** (per the confirmed
  direction); the content editor's terrain data stays read-only.
- No live push of edits into an already-running game (hot restart needed).
- No image editing, only selection of existing pack art and adjustment of
  render metadata (scale, anchors, sway).
- No multi-user editing or authentication (localhost only).
- No editing of product rules fixed by the mechanics doc (one coin per
  check-in, starting builder capacity of 1, no timers, no passive income).

## 2. Where data lives today

| Data | Current location | Moves to JSON? |
|---|---|---|
| Structure catalogue (ids, names, descriptions, kind, footprints, costs, population, unlock thresholds) | `world_content.dart` `structureCatalogue` | ✅ `catalogue.json` |
| Sprite manifest (role → file, scale, anchors, baseOffsetY, sway flag) | `world_content.dart` `spriteManifest` | ✅ `sprites.json` |
| Road / bridge / parcel cost formulas' values | `world_content.dart` (`roadCost`, `bridgeCost`, `parcelCost`) | ✅ `economy.json` (values; formula shapes stay code) |
| Starting wallet, builder progression, starting unlocks | `world_state.dart` `newParcelWorldState` | ✅ `economy.json` + derived (see §4.5) |
| Ambient animation + camera tuning | `parcel_world_tuning.dart` | ✅ `ambience.json` (camera stays code — see §9) |
| Terrain fixtures, parcel size, seed | `terrain_provider.dart`, `world_state.dart` | ❌ read-only in V1 |
| Check-in coin amount (1) | `world_reducer.dart` | ❌ product rule, not content |
| Schema/rules/content *format* versions | `world_state.dart` constants | ❌ code (see §8) |
| V1 fixed-lot preview content | `content/city_content.dart` | ❌ untouched (separate game) |

## 3. Architecture

```text
assets/content/            JSON source of truth (git-committed)
  manifest.json                    schema version + content revision
  catalogue.json                   structure models
  sprites.json                     sprite roles & render metadata
  economy.json                     costs, wallet, builder progression
  ambience.json                    animation tuning
        │
        ├──────────────► GAME (port 9101 preview)
        │                 loads bundle from bundled assets at startup,
        │                 validates, then serves rules/UI/rendering
        │
        └──────────────► EDITOR SERVER (port 9200, dart:io)
                          serves dashboard UI + REST API + pack images,
                          reads/writes the JSON files with backups
                          ▲
                          │ HTTP (localhost only)
                    EDITOR DASHBOARD (Flutter web)
                      same content model + validation code as the game
```

Key property: the content model and validators are **pure Dart** and are
imported by both the game and the editor server, so a save in the dashboard
runs through exactly the rules the game enforces. The content source is
abstracted (`ContentSource`: asset bundle in-game, filesystem in the server)
so the same loader works in both, and in tests.

## 4. Data model

Files live in `assets/content/`. Each file is one category; each is
editable as a unit in the dashboard. `manifest.json` records the schema
version and a monotonically increasing content revision (bumped by the
editor on every save).

### catalogue.json — structure models

```json
{
  "models": [
    {
      "id": "small-home",
      "name": "Sunny cottage",
      "description": "A welcoming home beside a connected road.",
      "kind": "building",
      "assetRole": "home-small-yellow",
      "footprint": { "columns": 1, "rows": 1 },
      "costCoins": 3,
      "population": 1,
      "unlockAtPopulation": 0,
      "enabled": true
    }
  ]
}
```

- `id` is the save-stable identity (what saves reference) — never reused.
- `assetRole` points into `sprites.json`; renaming it is save-safe.
- `population` is how much this model adds to the settlement's population
  once completed (see §4.5). Decorations default to 0 but remain editable.
- `unlockAtPopulation: 0` means unlocked from the start; the starting
  unlock set is **derived** from this, replacing today's hardcoded list.
- `enabled: false` hides a model from new purchases and unlocks while
  keeping it loadable for existing saves (see §8 — delete is never offered).

### sprites.json — sprite roles and render metadata

```json
{
  "sprites": {
    "home-small-yellow": {
      "path": "Buildings/bld_house_small_yellow_a.png",
      "renderScale": 0.5,
      "groundAnchor": [0.5, 1.0],
      "baseOffsetY": 0,
      "sways": false,
      "category": "buildings",
      "codeReferenced": false
    },
    "shore.grass.quarter.ne": {
      "path": "Roads and Grounds/tile_ground_grass_water_NE_clean.png",
      "renderScale": 0.5,
      "groundAnchor": [0.5, 1.0],
      "baseOffsetY": 0,
      "sways": false,
      "category": "ground",
      "codeReferenced": true
    }
  }
}
```

- `category` drives the dashboard grouping: ground, roads, shores, bridges,
  buildings, props, characters, water.
- `codeReferenced: true` marks roles whose *names* are constructed in code
  (terrain, road masks, shores, bridges). Their path/scale/anchor/sway
  fields remain editable, but the role name is locked in the dashboard.
  Structure/prop roles are freely renamable.

### economy.json — progression values

```json
{
  "startingWalletCoins": 0,
  "startingBuilderCapacity": 1,
  "roadTileCostCoins": 1,
  "bridgeCost": { "baseCoins": 4, "perWaterTileCoins": 2 },
  "parcelCost": { "baseCoins": 8, "distanceStepCells": 8, "ownedStepParcels": 12 },
  "builderProgression": [
    { "atPopulation": 12, "capacity": 2 },
    { "atPopulation": 30, "capacity": 3 }
  ]
}
```

Formula *shapes* (e.g. how distance steps into parcel price) stay in code;
the numbers are content. If a shape change is ever wanted, that is a code
change plus a content revision.

`startingBuilderCapacity` is fixed at 1 — the dashboard shows it read-only,
like the check-in coin rule. Builder *progression* is editable: whenever
population crosses an `atPopulation` threshold, builder capacity rises to
that entry's `capacity` (monotonic; the highest crossed threshold wins).
An empty list means the settlement stays at one builder forever — which is
exactly today's behaviour, so the seeded file ships an empty list.

### Population (derived progression metric)

Population is **derived, never stored**: the settlement's population is the
sum of `population` over completed buildings (structures only exist once
fully funded, so partially funded projects never count; decorations
default to 0). It is recomputed whenever a building completes and drives:

- **Model unlocks** — a model becomes unlocked once population reaches its
  `unlockAtPopulation`. This *replaces* the completed-building-count gate;
  the seeded values replicate the current 5/10/20-building milestones by
  giving every building population 1 and using thresholds 5/10/20, so the
  switch is behaviour-identical until tuned in the editor.
- **Builder capacity grants** — the `builderProgression` table above.
- **UI** — the game header shows the population alongside coins, and
  unlock/builder-grant events reference the population reached.

Because population derives from placed structures plus current content, a
save's population can shift when models' `population` values are edited
afterwards — expected and safe (unlocks only ever need to be a superset of
the expected set; the dashboard's unlock-threshold editor shows a warning
when lowering thresholds below values old saves may already have passed).

### ambience.json — animation tuning

Everything currently in `parcel_world_tuning.dart` except the camera block:
`ambientTimeScale`, water shimmer (bands, period, opacity, tint), vegetation
sway (angle, frequencies), pedestrian pacing (frame rate, speed range,
density, cap, wander, sprite scale), and the unowned-land wash colour.

## 5. Dashboard (Flutter web, served by the editor server)

Layout: category sidebar + content pane + persistent validation bar.

- **Overview** — content revision, save-compatibility summary, quick budget
  table (average building cost vs. the ~1-building-per-5-check-ins target
  from the mechanics plan), and a population curve preview (models sorted by
  `unlockAtPopulation` with their population contribution, so unlock pacing
  is visible at a glance).
- **Catalogue** — cards per model: sprite thumbnail, editable
  name/description/cost/population/unlock threshold, kind badge, enable
  toggle. Footprint is shown as an overlay on a ground-tile preview so 2×2
  art on a 1×1 footprint mistakes are visible. Adding a model starts from
  picking art in the sprite browser (phase E) or duplicating an existing
  entry.
- **Sprites** — grouped by `category`; each entry shows the image on a
  checkerboard with a ground diamond and a draggable anchor marker, scale
  slider, baseOffsetY, sway toggle. Code-referenced roles show a lock badge
  on the name field only.
- **Economy & progression** — numeric fields with range validation and
  derived-value hints (e.g. bridge cost at spans 1–4, parcel price at
  distance rings), plus the builder-progression table editor (population
  thresholds → capacity, monotonic, starting capacity shown locked at 1)
  and a warning when unlock thresholds are lowered below values existing
  saves may already have passed.
- **Ambience** — sliders with **live previews**: a frame-cycling character
  for walk rate, a rocking tree for sway angle/frequency, an animated water
  diamond for shimmer period/opacity, a pedestrian pacing strip for
  speed/density. ("Preview videos" are implemented as live canvas
  animations — no video files.)
- **Validation & history** — run validators on demand, list errors and
  warnings, show a JSON diff before saving, restore from timestamped
  backups (kept server-side, last N per category).

## 6. Editor server

- `dart run tool/content_editor/server.dart` → **port 9200**, bound to
  127.0.0.1 only.
- Endpoints: `GET /api/content`; `PUT /api/content/{category}` (validate →
  backup → atomic write → bump revision); `POST /api/validate`;
  `GET /api/pack/{path}` (serves pack images for thumbnails, paths
  sanitized and restricted to `assets/`); `GET /api/backups` /
  restore; later `GET /api/assets/scan` for the unused-art browser.
- Serves the prebuilt dashboard from `build/editor/` (built with
  `flutter build web -t lib/editor/main.dart`); prints a friendly
  build hint if the directory is missing.
- Writes are atomic (temp file + rename) and never touch anything outside
  `assets/content/` plus the backups directory.

## 7. Workflow

1. `dart run tool/content_editor/server.dart` (9200) and the game preview
   (`flutter run … --web-port=9101`, or the built web app).
2. Edit in the dashboard → diff → validate → save (backup + revision bump).
3. Hot-restart the game (`R` in `flutter run`) to load the new JSON —
   bundled assets are read at startup, so running games do not see file
   changes live. (Documented friction; a debug-mode fetch-from-server mode
   is a possible later nicety.)
4. Commit JSON changes via git as usual; the dashboard never commits.

## 8. Save compatibility & versioning rules

| Edit | Existing saves | Dashboard behaviour |
|---|---|---|
| Change cost / milestone / tuning values | Safe; receipts and funded totals keep old values (existing invariant) | Normal save |
| Rename `assetRole`, change sprite metadata | Safe; saves reference `id`, not roles | Normal save |
| Disable a model (`enabled: false`) | Safe; still loadable, hidden from new play | Normal save |
| Rename/delete a model `id` | **Breaks saves** (unlocks/placements reference it) | Blocked: rename offered as disable + new model; delete not offered |
| Change content *format* (add fields) | Needs `contentVersion` bump + migration decision | Warn + require version bump |

`manifest.json`'s content revision is informational (audit/diff); it does
not gate saves. The `contentVersion` in world state remains a **code**
constant describing the format, exactly as today.

## 9. Corner cases & decisions

1. **Removal vs. saves** — solved by disable-not-delete (§8); a shipped
   model id is never truly deleted.
2. **Derived starting unlocks** (decided) — every model with
   `unlockAtPopulation: 0` starts unlocked; the hardcoded list goes away.
3. **Camera tuning stays code** (decided) — app feel, not game content.
4. **Product rules stay code** (decided) — check-in = 1 coin, starting
   builder capacity = 1. Both display read-only in the dashboard.
5. **Builder grants must reconcile on load** — capacity is saved per world
   and grants are event-driven, so an existing save whose population
   already passes a newly added (or lowered) threshold would otherwise
   never receive it. On load, effective capacity is reconciled *upward*
   to what the progression table grants for the save's population — never
   downward. Same for unlocks: expected-but-missing unlocks are granted at
   load (recorded once, with an event), so lowering thresholds after the
   fact cannot invalidate a save.
6. **Population edits shift old saves** — population derives from placed
   structures × current content, so editing per-model `population`
   retroactively changes a save's population. Safe by design with the
   reconciliation above; the dashboard still warns when lowering unlock
   thresholds.
7. **Unlock-gate migration** — switching from building-count to population
   gates is seeded behaviour-identically (uniform population 1,
   thresholds 5/10/20), so the switch itself changes nothing until tuned.
8. **Parcel size, seed, terrain fixtures stay read-only** — parcels
   materialize terrain and the save validates `parcelSize ==
   defaultParcelSize`; editing these invalidates every save and the shore
   fixtures. Hand-authored terrain editing is the dedicated world map
   editor planned as the next project.
9. **Road/shore/bridge role names are code-constructed** — locked names,
   editable metadata (handled via `codeReferenced`).
10. **Two editors / stale game** — single-writer server, last-write-wins
    with a stale-revision check; an already-running game keeps its loaded
    content until restart (workflow §7).
11. **Validation before every save** — duplicate ids, unknown assetRole,
    missing files on disk, cost < 0, population < 0, footprint < 1,
    unlock-threshold ordering, monotonic builder progression, at-least-one
    unlocked model at start, anchor/scale sanity ranges. File-existence
    checks are server-side only (the game can't list assets).
12. **Footprint vs. art mismatch** — not machine-validatable (art is
    deliberately opaque to rules); mitigated by the footprint preview.
13. **Integer discipline** — all coin and population values integers;
    sliders only for float ambience values.
14. **Backup retention & git** — backups live server-side (gitignored);
    the JSON itself is the committed source of truth.
15. **Test migration** — current tests assert concrete values (cottage
    costs 3, etc.); they will load the same JSON so values stay asserted,
    now against the data file. A snapshot test guards accidental value
    drift. Unlock tests keep passing because the population seed replicates
    today's milestones.
16. **Async loading refactor risk** — today's content is compile-time
    `const` consumed synchronously everywhere (painter, rules, reducer,
    tests). Phase A must load-then-start (the app already gates on image
    loading) and thread a loaded `ContentBundle` through; mechanical but
    the widest-touching change in this plan.
17. **Editor build step** (decided) — the dashboard is a prebuilt Flutter
    web bundle served by the Dart server; developing the dashboard itself
    uses `flutter run` against the running server.

## 10. Implementation phases

- **A. Content layer + population** — JSON files seeded with today's exact
  values; `ContentBundle` loader + `ContentSource`; validation; game/tests
  load the bundle; derived starting unlocks; the population metric with
  uniform `population: 1`, unlock thresholds seeded at 5/10/20 (replicating
  the current building-count milestones), an empty builder progression,
  load-time unlock/capacity reconciliation, and a population readout in the
  game header. *Exit: full analyze/test/web-build green with zero gameplay
  behaviour change.*
- **B. Editor server** — port 9200, API, backups, atomic writes, pack
  image serving.
- **C. Dashboard core** — catalogue, economy & progression, sprite editors
  with image previews, validation bar, diffs.
- **D. Ambience editor** — tuning moves to JSON; sliders with live
  animation previews.
- **E. (Future) Asset browser** — scan unused pack art, thumbnails, promote
  to manifest + catalogue; debug live-reload of content into a running
  game.

The hand-authored **world map editor** (terrain, water bodies, parcels) is
a separate project planned immediately after this one; the content editor
is deliberately structured so its server/dashboard shell can be reused for
it.

## 11. Port map

| Port | Purpose |
|---|---|
| 9000 | Accountable finance app (untouched) |
| 9101 | Parcel-world game preview |
| **9200** | Content editor dashboard (this plan) |
