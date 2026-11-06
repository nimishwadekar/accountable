# Citysim assets

Active game art lives in a category-organized tree that mirrors the content
editor's grouping:

- `sprites/<category>/<subcategory>/` — every sprite referenced by
  `assets/content/sprites.json`, organized exactly as the editor displays
  it (buildings/houses, props/trees, ground/grass, roads/end, …).
- `characters/` — ambient pedestrian walk and idle frames, loaded directly
  by the renderer.
- `content/` — the JSON content layer (catalogue, sprites, economy,
  ambience).
- `buggy_studio/` — the remainder of the downloaded art pack: damaged
  versions, the gunshop (deliberately not promoted), and vehicles,
  kept for the planned asset browser that will promote them into
  the organized tree. The pack is **disk-only**: it is not listed in
  the pubspec asset bundle, so builds ship only promoted art — the
  browser will read it server-side from disk, like content
  validation already does. The pack's clean building art (35
  entities, both door facings) was promoted into
  `sprites/buildings/` and wired into the catalogue's houses,
  commerce, offices, civic, industrial, and sites subcategories;
  all 46 clean props were promoted into `sprites/props/` as
  decoration models. Promotions copy files, so the pack originals
  remain here.

## Unused pack remainder — category inventory

Everything below sits in `buggy_studio/` and is not referenced by the
game. Work through the categories one by one when promoting. (The
construction-site and water-tower originals also remain here under
their original pack filenames — those two were promoted under renamed
copies in `sprites/buildings/`.)

### Buildings — 2 clean files
- Gunshop, both door facings (`bld_gunshop_a/b`) — deliberately
  skipped for the cozy tone; revisit only if that decision changes.

### Props — promoted in full
All 46 clean pack props are promoted into `sprites/props/` as instant
decoration models (16 catalogue entries): streetside (lamps, traffic
lights, signs, fences, trash cans and bags), natural (common trees,
trunks, rocks, wild grass — the grass joined `flowers/`), and clutter
(boxes, drop box, papers, tires). Only the 18 damaged/toppled variants
remain in the pack remainder, parked for demolition/abandonment
visuals.

### Roads and Grounds — 37 clean, 22 damaged
- **Pelican crossings** (4 orientations) — zebra-crossing road
  overlays, candidate for road detailing.
- **Puddles and patches** — grass puddles, dirt puddles, drypatch,
  grasspatch — candidate ground variation/weathering layer.
- **Dirty terrain variants** — grimy copies of every shore
  edge/corner/quarter and water tile — a grime aesthetic, distinct
  from the `_damaged` building art.

### Vehicles — 104 clean, 80 damaged
All 4-direction driving sprites; the biggest untouched category and
the logged future ambience work (ambient traffic on roads):
- **Civilian**: sedans (blue/red/white), pickups (black/orange/red),
  vans (black/purple/white), trucks and box trucks (green/red/yellow).
- **Service**: school bus, fire truck, garbage truck, police car,
  SWAT van.
- **Air**: helicopters (red/white) with 3-frame spinning-rotor
  animation per direction.

### Damaged variants — ~220 files across all categories
Demolished buildings, toppled props, wrecked vehicles, dirty terrain.
Parked as potential demolition/abandonment/grime visuals — see the
future-work notes in the docs.

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
