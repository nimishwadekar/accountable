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
  versions, the gunshop (deliberately not promoted), vehicles, and urban
  props, kept for the planned asset browser that will promote them into
  the organized tree. The pack's clean building art (35 entities, both
  door facings) was promoted into `sprites/buildings/` and wired into the
  catalogue's houses, commerce, offices, civic, industrial, and sites
  subcategories.

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
