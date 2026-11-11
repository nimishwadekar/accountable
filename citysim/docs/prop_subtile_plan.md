# Sub-tile prop placement — plan

Props (catalogue `decoration` models) become placeable at any of 64
subtile positions inside a tile, cluster with each other, and can be
picked up for free. Buildings stay cell-based and permanent.

Decided 2026-11-10 after surveying Factorio (continuous float
positions + per-entity collision), Cities: Skylines (free prop
placement + optional snapping; props cosmetic), and the isometric
y-sort standard (depth = col + row, fractional add for sub-tile
entities, multi-tile keyed on the bottom corner — the pattern our
pedestrians already use).

## Decisions

- **Lattice: 8×8 subtiles per tile** (64 positions), subtile centers
  at `(i + 0.5) / 8` of the tile — near-continuous placement with
  snapping. Chosen over free floats: CSV stays small integers,
  validation stays deterministic, snapping comes free.
- **Placement surface: ground, road, and bridge tiles.** Props go
  on owned vacant grass, on completed roads (incl. bridge banks),
  and on completed bridge decks. Not on open water, building
  footprints, reserved (pending) cells, or unowned tiles. All
  models are placeable anywhere valid — no per-model
  road-adjacency rule.
- **One prop per subtile** — the only prop-vs-prop collision rule.
  No subtile footprints for now (see future notes): sprites may
  overlap freely, which is half the point of clustering.
- **Blocking: props occupy their tile** for future construction
  from ground tiles.
- **Pick-up: free, no refund.** Props only — buildings keep the
  permanence rule. A misplaced flower is never permanent.

## Position model

- A prop is `cell (c, r)` + `subtile (sx, sy)`, `sx, sy ∈ 0..7`.
- World anchor — the subtile's SOUTH vertex, the sub-lattice version
  of how structures anchor at their footprint's south vertex:
  `_cellWorldCenter(c, r)` shifted by
  `fx * (32, 16) + fy * (−32, 16)` in world units plus the
  subtile's half-height (2 world px), where
  `fx = (sx + 0.5) / 8 − 0.5` and `fy` likewise. The front subtile
  (7,7) is the tile's own south vertex, so props from before the
  lattice render pixel-identically.
- **Depth** in the shared actor pass:
  `c + r + (sx + sy + 1) / 16` — the subtile position at HALF
  weight, so every prop stays strictly inside its tile's depth
  slot: a front-corner prop still draws behind whatever stands on
  the tile in front, exactly like the 1×1 structures props used to
  be. (Pedestrian-weight fractions would let front-corner props
  paint over front-tile actors.) Interleaves correctly with
  buildings, bridges, and walkers; ties break on `sx`, then id.
- **Bridge-deck elevation**: a prop on a bridge cell stands on the
  deck, not the water below — its anchor lifts by the bridge body's
  baseOffsetY (12 art px → 6 screen px at scale 1) so its feet sit
  on the deck surface.

## Data model & storage

- `state.structures` keeps **buildings only**. New
  `state.props: List<PlacedProp>` with
  `id, cell, subtile, catalogueId, assetRole, facing?, placedDay`.
  Prop id derives from position — `prop:${c}.${r}.${sx}.${sy}` — so
  it is unique while placed and stable across save/load (one prop
  per subtile keeps anchors unique).
- Subtile occupancy is one prop per subtile, keyed by
  `(cell, subtileX, subtileY)` in the query layer (`propsByAnchor`);
  with 8×8, a tile's occupancy would fit a 64-bit mask if the
  record key ever needs to go faster. No footprint field, no
  content changes; decoration entries stay exactly as they are.
- **Fifth sheet, `Props`**: headers
  `x, y, subtile_x, subtile_y, model, variant, facing`. No status
  column — props are instant purchases, never projects.
- Registration points: `sheet_tables.dart` (field, header, name,
  decode/encode), `world_sheet_codec.dart` (both directions),
  `server_sheet_store.dart`, editor server `worldSheetNames` +
  `_putWorld` whitelist + `_getWorldSummary`/`_terrainOccupationIssues`
  call sites, `world_usage.dart` and the editor's terrain-occupation
  validation (props may sit on road and bridge cells — a prop on a
  bridge deck is on a water tile and must read as valid).
- **No migration code.** The codec reads and writes only the new
  shape. The save itself is migrated by hand when Phase 1 lands: the
  ~74 decoration rows in `assets/test_sheets/Tiles.csv` (14 pines,
  10 street-lamps, 8 flower-gardens, …) move into the new
  `Props.csv` at subtile (7, 7) — the tile's south vertex, exactly
  where 1×1 structures anchored, so the migration is
  pixel-identical — and Tiles keeps only
  building rows. New code and migrated
  save land together, with a launcher restart.

## Placement rules

Same tap → confirm → instant coin purchase flow as today; the tapped
point simply snaps to its containing subtile.

A placement is valid when the anchor cell is:

- owned;
- one of: vacant grass ground, a completed road (incl. bridge
  banks), or a completed bridge deck cell;
- not under any building footprint or reserved (pending project)
  cell;

and the target subtile is free — one prop per subtile; sprites may
overlap, anchors may not.

Open water and unowned tiles never accept props. All models are
placeable anywhere valid — streetside props do not require a road
border (a per-model content flag can be added later if that ever
feels wrong). Props on roads and decks do not collide with
pedestrians — the C:S-style clutter is accepted. Blocking only
matters on ground tiles (roads and decks have no future
construction to block); pick-up stays free.

Variant roll and facing roll (south/east when the sprite has
facings) work exactly as today, seeded by `nextEntityNumber`.

## Pick-up

- Inspect tool → select a prop → **Pick up** action in the
  inspector: free, no refund, logs an action, removes the prop.
- Reducer action (`pickUpProp`), rule check (target exists, is a
  prop), save validation unchanged in spirit — props are optional
  data, removing one is always legal.

## Rendering

- Anchor the sprite at the subtile center using the pedestrian
  pattern (feet at the anchor, `groundAnchor` respected); sway keeps
  working around that anchor.
- Fractional depth per above; props join the existing per-frame
  actor pass, culled by cell chunk as today.
- Selection tint and footprint outline switch from cell lookup to
  id lookup (a selected prop outlines its tile diamond and washes
  its sprite, same colours as structures).
- **Ghost preview while the decor tool hovers** — LANDED (mockup A,
  `prop_ghost_preview.png`): translucent sprite at the pending
  subtile — the hover point on desktop, the tapped cell and subtile
  on touch — with a small filled diamond on the target subtile.
  Validity stays in the panel text, like buildings.

## Picking & selection

- Reuse sprite-alpha hit testing (`sprite_picking.dart`); candidate
  window already reaches far enough via `_spriteReachCells`.
- Hits report the prop id; app selection gains a
  `selectedStructureId` so two props on one tile are distinguishable
  (inspector, tint, pick-up all resolve by id).
- Repeated taps cycle the existing hit chain — two same-tile props
  are two chain entries.

## Phases (each lands analyze + tests green)

1. **Data model + storage** — LANDED 2026-11-10: `PlacedProp`, Props
   sheet, codec both directions, editor server + usage registration,
   hand migration of the save, and — pulled forward from phases 2–3
   so the game stays whole — placement rules, prop rendering in the
   actor pass, and sprite-alpha picking (props join the tap cycle).
   Tests: round-trip, multiple props per cell, same-subtile
   rejection, the placement surface, blocking, reducer round-trip.
2. **World logic** — LANDED 2026-11-11: `pickUpProp` (free, no
   refund, logged; the game's one removal action, scoped to
   decorations), id-based prop selection (`selectedPropId`) with the
   selection wash and an inspector card carrying the Pick up button.
   Tests: pick-up frees the subtile and refunds nothing, missing ids
   fail loudly.
3. **Rendering pins** — LANDED 2026-11-11: pixel tests pin that a
   prop draws behind the structure in front and over the structure
   behind; `propDepth` (visible for testing) pins the half-weight
   tile-slot contract; the prop wash is pixel-tested like the
   bridge's.
4. **UX** — LANDED 2026-11-10/11: taps carry the subtile (placement
   lands where the player taps), and the ghost preview — mockup A,
   approved — draws the translucent sprite plus a subtile diamond at
   the hover point on desktop and the tapped cell on touch.
5. **Docs + full suite + web build** — LANDED 2026-11-11 (116/116
   tests).

## Future notes

- A faint subtile grid (ambience-tunable, like `tileGrid`) shown
  only while the decor tool is active — optional polish, mockup
  first.
- Streetlight system (backlog) can reuse sub-tile placement to sit
  lamps at road edges precisely.
- Subtile footprints (dropped 2026-11-10): if a genuinely big prop
  ever needs to claim space, add a per-model `subtileFootprint`
  catalogue field as a placement-time guardrail only — never a save
  invariant, or an editor resize would brick old saves. The 64-bit
  per-tile mask makes the overlap check a bit AND when that day
  comes.
