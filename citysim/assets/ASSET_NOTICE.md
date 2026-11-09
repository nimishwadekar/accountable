# Citysim assets

Active game art lives in a category-organized tree that mirrors the content
editor's grouping:

- `sprites/<category>/<subcategory>/` — every sprite referenced by
  `assets/content/sprites.json`, organized exactly as the editor displays
  it (buildings/houses, props/trees, ground/grass, roads/end, …).
  The six ground tiles (grass, grass puddle, dirt, asphalt, concrete,
  water) were replaced with borderless versions on 2026-11-09: the
  3.5px edge band painted the tile's dominant colour and the diamond
  edge hardened to full opacity, removing the baked cell grid and the
  alpha-seam hairlines between tiles. The grid-lined originals were
  returned to `buggy_studio/Roads and Grounds/` — the only copies,
  since the pack originals were moved out during promotion.
- `characters/` — ambient pedestrian walk and idle frames, loaded directly
  by the renderer.
- `content/` — the JSON content layer (catalogue, sprites, economy,
  ambience).
- `buggy_studio/` — the remainder of the downloaded art pack, kept for
  the planned asset browser that will promote pieces into the organized
  tree. The pack is **disk-only**: it is not listed in the pubspec
  asset bundle, so builds ship only promoted art — the browser will
  read it server-side from disk, like content validation already does.
  The pack's clean building art (49 entities, both door facings — see
  the promotion-history note below) was promoted into
  `sprites/buildings/` and wired into the catalogue's houses,
  commerce, offices, civic, industrial, and sites subcategories; the
  clean props were promoted into `sprites/props/` as decoration
  models.
- `buggy_studio/Damaged/` — all damaged, toppled, and dirty variants
  (242 files: 98 buildings, 14 props, 50 roads and grounds, 80
  vehicles), separated from the clean art by filename suffix
  (`_damaged`, `_damaged1..3`, `_toppled`, `_dirty`). Not used by the
  game; parked for potential demolition/abandonment/grime visuals.

  Promotion history note: the earlier terrain/roads/bridges pass and
  the first batch of building/props promotions **moved** files out of
  the pack (their originals are gone); later promotions **copied**, so
  many clean originals now sit alongside their promoted copies. The
  inventory below is checksum-verified against the promoted tree, not
  reconstructed from the original pack contents.

## Unused pack remainder — category inventory

Everything below sits in `buggy_studio/` (outside `Damaged/`) and is
not referenced by the game. Checksum-verified against the promoted
tree: **119 sprites are left to migrate.**

### Buildings — 2 candidates
- Gunshop, both door facings (`bld_gunshop_a/b`) — deliberately
  skipped for the cozy tone; revisit only if that decision changes.
- The other 70 clean building files are originals of already-promoted
  copies (later promotions copy, originals stay).

### Props — 4 candidates
- Dry wild-grass variants (`prop_weed_*_dry`) — color variants of the
  promoted weeds, never promoted.
- The other 46 clean props are originals of already-promoted copies.

### Roads and Grounds — 9 candidates
- **Pelican crossings** (4 orientations, `tile_road_pelican_*_normal`)
  — zebra-crossing road overlays, candidate for road detailing.
- **Puddles and patches** (5 tiles: grass `puddles` variant, dirt
  `puddle` and `puddles`, `drypatch`, `grasspatch`) — candidate ground
  variation/weathering layer. The promoted grass puddle is the
  singular-`puddle` art and was moved out of the pack; the plural
  variant here is distinct, different art.
- The six plain ground tiles here (`tile_ground_grass`, `_dirt`,
  `_asphalt`, `_concrete`, `_water`, and the singular grass
  `_puddle_clean`) are the **grid-lined originals** of the borderless
  promoted tiles, returned 2026-11-09 — not migration candidates.

### Vehicles — 104 candidates
All 4-direction driving sprites; the biggest untouched category and
the logged future ambience work (ambient traffic on roads):
- **Civilian**: sedans (blue/red/white), pickups (black/orange/red),
  vans (black/purple/white), trucks and box trucks (green/red/yellow)
  — 60 files.
- **Service**: school bus, fire truck, garbage truck, police car,
  SWAT van — 20 files.
- **Air**: helicopters (red/white) with 3-frame spinning-rotor
  animation per direction — 24 files.

### Damaged/Dirty variants — 242 files
Demolished buildings (98), toppled props (14), cracked roads and
grimy terrain (50), wrecked vehicles (80) — all in
`buggy_studio/Damaged/`, parked as potential
demolition/abandonment/grime visuals — see the future-work notes in
the docs.

## Provenance

`buggy_studio/` contains the **Isometric City - Starter Pack** by Buggy
Studio, downloaded from <https://buggystudio.itch.io/isometric-city-starter-pack>
on 2026-11-02. The creator states in the pack's itch.io comments that the
pack is CC0 and may be used in personal or commercial projects. The current
pack page lists the supplied sprite categories but does not include a
license file in the ZIP. Source/license confirmation:
<https://buggystudio.itch.io/isometric-city-starter-pack>.

Sprites moved into `sprites/` and `characters/` originate from that same
pack; this is a reorganization, not new artwork. Keep the origin clear if
assets are later moved or the project is redistributed.
