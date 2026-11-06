# Renderer Performance — Campaign Notes & Future Work

**Status:** structural optimization complete (steps 1–4); remaining items are refinements, deferred.  
**Date:** 2026-11-06  
**Owner docs:** [Parcel World Implementation Plan](PARCEL_WORLD_IMPLEMENTATION_PLAN.md)

## What the campaign established

Measured on the sample town (13 owned parcels, 56 structures, 104 roads, 2
bridges), desktop debug VM, 1500×850 window, via
`test/world_perf_probe_test.dart`:

| Panning zoomed-out (~0.54) | Before | After |
|---|---|---|
| UI-thread paint, mean | 8.5 ms | 1.8 ms |
| Ground-layer re-records | every motion frame | ~1 parcel chunk per frame (entering view) |
| Draw ops per frame | 16,753 | ~183 |

The architecture that got us here:

1. **Diamond culling** — the terrain record loop walks each row's exact
   viewport column window instead of the lattice bounding box (~2.2× fewer
   ops in every phase).
2. **Parcel-sized world-space chunks** — the flat layer (terrain, wash,
   roads, parcel outlines) records per parcel in world coordinates,
   rasterizes to textures (`Picture.toImageSync`) at zoom buckets
   (0.5×/1×/2× density), and draws one quad per chunk. Camera motion never
   re-records; world edits reset the cache (whole-layer semantics for now).
3. **Fragment-shader water shimmer** — `shaders/water_shimmer.frag`
   computes the band pattern per pixel from world coordinates and time,
   sampling a per-chunk water mask texture. One textured quad per water
   chunk replaces thousands of tessellated contours per frame. Falls back
   to merged-path drawing when the shader cannot load.

### Correctness tooling (keep using it)

- `test/world_chunk_render_test.dart` — world-coordinate pixel anchors
  (road/water/grass at derived screen positions) plus a texture-vs-picture
  A/B pixel comparison for every chunk draw path.
- `test/world_shimmer_test.dart` — shader-vs-path shimmer parity (frozen
  ambient clock), plus an assertion that the shader actually engaged.
- `test/world_perf_probe_test.dart` — structural invariants: idle never
  re-records; motion records ≈ entering chunks only; frame draws stay in
  the hundreds. Run it on the VM only; debug Chrome cannot finish inside
  any sane timeout (itself a data point about the web-debug platform tax).
- **Live HUD:** open a debug build with `?perf=1` for on-screen frame
  stats and periodic console summaries; it compiles away in release.

## Future work (deferred)

Ordered roughly by expected value:

1. **Per-chunk dirtying on world edits.** Any state change (placing a
   building, funding a road tile) currently re-records and re-rasterizes
   every *visible* chunk (~10–25 ms one-time blip per action). Chunks are
   already keyed by parcel, so dirtying just the parcels a mutation
   touches is straightforward: compare old/new state per chunk or pass
   mutation footprints from the reducers.
2. **Actor-pass batching.** Structures, bridge pieces, and pedestrians
   (~120 draws at zoom-out) are individual `drawImageRect`s with fresh
   `Paint`s. Batching sprites that share a source texture into
   `drawAtlas`/`drawRawAtlas` calls would collapse most of them; requires
   a runtime-built atlas from the decoded sprites. Sway transforms and
   depth-sorting need per-sprite RSTransforms, which drawAtlas supports.
3. **Per-frame allocation churn.** A `math.Random()` per frame and a
   rebuilt road-cell set per frame in `_PedestrianSim.update`; per-actor
   closures in `_drawActors`; `Paint` per draw call. All trivially
   hoisted/cached (road set keyed on a roads version counter).
4. **Camera without widget rebuilds.** Pan/zoom gestures `setState` the
   whole view subtree per frame. Camera scale/offset could live in a
   `ValueNotifier` driving painter-only repaints (the ambient clock
   already uses the `repaint:` listener pattern).
5. **RepaintBoundary around the map.** The game canvas shares a layer
   with surrounding app UI; a boundary would stop app-panel `setState`s
   from repainting the map (and vice versa).
6. **Startup re-record churn.** The chunk cache keys on `images.length`,
   so each arriving sprite during launch re-records visible chunks.
   Smarter: track which roles were missing images and dirty only chunks
   containing them.
7. **Measure on release Chrome.** All numbers above are debug-VM. The
   browser is the shipping platform; a release-build profile pass would
   quantify the remaining platform tax and validate the zoom-bucket
   thresholds (0.75/1.5) and the chunk LRU cap (400) against real DPR-2
   fill rates and texture memory.
8. **Shimmer shader rail extensions** (feature work, not perf): shoreline
   foam, drifting cloud shadows, day/night grading, puddle glints, lamp
   glows — each is another mask channel plus formula in the existing
   overlay pass.

### Known acceptable trade-offs

- Parcel-outline stroke width scales with zoom (recorded in world space,
  1.2 world px). Fixable with screen-space overlays if it ever reads
  badly.
- Zoom-bucket crossings re-rasterize visible chunks over a few frames
  (budget 12/frame) while stale textures draw scaled — brief softness
  during zoom, no hitch.
- Shader mode costs ~0.5 ms more UI-thread time per frame than path mode
  at full zoom-out (one `FragmentShader` instance per water quad) in
  exchange for zero raster-thread tessellation — the right trade for the
  web target.
