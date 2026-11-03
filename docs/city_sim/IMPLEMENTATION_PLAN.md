# City Simulation — Archived V1 Prototype Plan

**Status:** historical V1 plan; not the current game or implementation specification.  
**Date:** 2026-11-02  
**Scope:** a standalone, synthetic-data prototype, not integration with the finance app.

> This file preserves the original fixed-lot V1 design and implementation record.
> Its mechanics are historical and may conflict with the current parcel-world
> game. See the [Game Mechanics Plan](GAME_MECHANICS_PLAN.md) for current rules
> and the [Parcel World Technical Implementation Plan](PARCEL_WORLD_IMPLEMENTATION_PLAN.md)
> for current engineering work. The old `citysim.prototype.v1` save remains
> untouched by the V2 app.

## Implementation checkpoint

The first runnable slice now includes the authored village/town/city map, CC0
sprite lookup, selection and catalogue placement, daily check-ins, parallel
construction, district expansion, namespaced local persistence, and the
synthetic debug panel. The scene currently uses Flutter canvas painting rather
than Flame. The tuning values below remain provisional. Desktop browser review
and later-stage city composition still need manual evaluation.

## 1. Confirmed direction

The user has confirmed:

- An **isometric** settlement that can grow steadily from a village into a large city diorama.
- **One daily check-in awards one coin per day.**
- The user **chooses when to spend coins to grow the city**. Growth is not automatically awarded per transaction.
- Purchase from a **catalogue**, then select an eligible authored lot. Roads remain fixed in this first prototype.
- Use **tiered costs** rather than charging one coin for every addition. Exact prices remain tunable.
- Check-in is an explicit **today-only button**, with no transaction/review requirement, no missed-day backfill, and no penalty for absence.
- Purchases start **simulated construction timers**. Multiple lots can be under construction in parallel, without a builder limit or queue.
- The synthetic clock **pauses while the preview is closed**; timers do not catch up using real-world elapsed time.
- A confirmed purchase is **not cancellable** in the first version. Show its cost and duration before confirmation.
- Retain the synthetic settlement through refresh using a **separate local browser save**, with a Reset action.
- Start with a **CC0 asset pack**, using its artwork as-is.
- Keep geography and settlement state independent of asset files so the artwork can be replaced later.
- Provide a separately hosted test simulation with synthetic counters and time controls before connecting any financial data.

The earlier [research and brainstorming](README.md) remains background material, not an approved specification. In particular, its suggestion to omit coins is superseded by the confirmed daily check-in coin economy above. Its suggested automatic project progress and financial-milestone rewards are not requirements for this first prototype.

## 2. What the first version should demonstrate

The goal is to answer three questions:

1. Does buying visible additions make the settlement rewarding to revisit?
2. Does its development look coherent at village, town, and city scales?
3. Can we change art and progression values without rewriting the map or renderer?

Build one finite but expandable map with connected districts, not an unlimited city generator. It should offer enough authored growth to show a small starting village, a developing town, and a denser city district. The original village centre remains recognizable as the surrounding area grows.

The prototype should include:

- A starter settlement with a small number of completed buildings and an initial road/path network.
- Authored geography, protected terrain, districts, and valid building lots.
- A visible coin wallet and daily check-in action.
- A catalogue of coin-priced additions and highlighted eligible lots for placement.
- A concise explanation of each purchase's cost and visible result.
- Construction countdowns and clear under-construction versus completed states.
- Building selection and a small information panel.
- Pan, zoom, and a reset-camera action for viewing a larger settlement.
- A debug panel for exercising progression without waiting real days.
- An event history showing how the wallet and settlement changed.

Do not silently promise construction artwork that the chosen pack does not contain. If no compatible construction sprite exists, show a neutral lot outline and a separate progress/countdown indicator, then reveal the complete sprite when the timer finishes. Do not invent misaligned vector scaffolding or reinterpret damaged-building art as a construction sequence.

## 3. Recommended technical approach — not yet locked

### Isolated Flutter preview

The first implementation lives under `lib/citysim/` in this repository, but has a separate Flutter entry point and does not import the Accountable app. Its isometric canvas uses Flutter painting with ordinary Flutter controls; the content and progression remain independent of the renderer.

- Target URL: `http://localhost:9101`, launched with `flutter run -d web-server --web-port=9101 -t lib/citysim/main.dart`.
- Do not alter or stop the finance app on port `9000`.
- If `9101` is occupied, select another explicit port rather than terminating an unrelated process.
- All simulation input is synthetic. No Google sign-in, Sheets calls, transaction reads, or financial writes.
- Keep prototype state and local-save keys separate from Accountable. The prototype references the CC0 pack under `assets/citysim/`.
- `lib/main.dart` remains the Accountable entry point; running `lib/citysim/main.dart` starts only the prototype.

Suggested internal boundaries:

```text
lib/
  main.dart                    Standalone preview and launch options
  domain/                      State, commands, events, progression rules
  content/                     Definition loading and validation
  rendering/                   Isometric world, sprites, camera, selection
  ui/                          Wallet, check-in, purchases, inspector, history
  debug/                       Fake clock, scenarios, overrides, replay
assets/
  definitions/                 Map, building catalogue, prices, art manifests
  art/                         Selected pack files and license/provenance
test/
  domain/                      Rules and deterministic replay
  content/                     Definition and asset validation
  ui/                          Interaction and responsive tests
```

This structure is a proposal, not a requirement to build every abstraction before the first scene works.

### Art starting point

The previously recommended candidate is [Buggy Studio's Isometric City Starter Pack](https://buggystudio.itch.io/isometric-city-starter-pack). The creator describes it as CC0 and lists buildings, road/ground tiles, props, vehicles, and basic character animation.

The pack was downloaded and audited on 2026-11-02: it contains 622 supplied files across buildings, characters, props, roads/grounds, and vehicles. The ZIP has no license file; the creator states CC0 in the pack's itch.io comments. The source and this provenance note are recorded in `assets/citysim/ASSET_NOTICE.md`.

Use pack assets as delivered. No custom vector shapes are layered over buildings; neutral lot outlines and separate construction progress indicators are used where needed. The first scene uses terrain, complete buildings, and supplied props.

### Future district road templates

The user would like to explore choosing a road template when unlocking a district later. Keep a district's road/layout definition separate from its unlock state and from building art. Stable district IDs, a template identifier, lots, and road entry/exit connections should allow that extension without replacing the entire city model. For V1, each district has one fixed authored template; no road-template chooser or procedural road generation is required. Future alternatives must preserve connections and footprint rules, not merely swap road pictures.

## 4. Map and replaceable artwork

### Logical map

- Store geography on a square integer-coordinate grid, projected to an isometric view.
- Ground cells record semantic terrain and infrastructure types, not file paths.
- Buildings have stable instance IDs, lot IDs, building types, upgrade levels, and logical footprints.
- A building can occupy more than one cell; the artwork can extend above or beyond its footprint.
- Roads reserve access routes. Buildings cannot overlap occupied lots, protected geography, or roads.
- New districts connect to the existing network. Expansion must not reshuffle established districts.

### Art manifest

Resolve logical visual roles through an art manifest. For example:

```json
{
  "building.bakery.level_1": {
    "image": "art/bakery.png",
    "footprint": [2, 2],
    "ground_anchor": [0.5, 1.0],
    "render_size": [128, 160],
    "layer": "structures"
  }
}
```

The dimensions and paths above are illustrative, not a claim about a sprite in the pack. An animated entry can replace the image reference with frame and timing metadata while retaining the same logical role and ground anchor.

- Logical ground dimensions are uniform; image dimensions need not be square or identical.
- Place every animation frame on a stable canvas/anchor to avoid jitter.
- Define image offsets, footprints, orientation, and selection bounds explicitly.
- Draw ground before structures. Order structures by ground position, with stable tie-breaking and explicit foreground handling where required.
- Validate multi-cell structures and residents passing in front of or behind them; a naive single-cell sort is not sufficient for every overlap.
- An alternative manifest should reskin compatible roles without moving buildings or modifying progression.
- A different perspective or radically different footprint vocabulary still requires adaptation. Asset indirection cannot make arbitrary packs interchangeable automatically.

For larger maps, organize content into district-sized chunks and render/update only what is needed. Benchmark the actual renderer before claiming a particular city size or frame rate.

## 5. Coin and progression model

### Confirmed rule

One successful daily check-in grants **exactly one integer coin**. Transaction count, transaction amounts, transfers, net worth, and game animation do not create additional coins.

### Confirmed economy and interaction

- Check-in is an explicit action for the current simulated local calendar date.
- There is no transaction/review requirement and no backfill of missed dates. The button is for the current simulated local calendar date only.
- A date can be credited only once, including after refresh, clock rewind, or event replay. Debug rewinding does not erase the credited-date history.
- Advancing time does not automatically check in or grant coins.
- No coin expiration, debt, missed-day penalty, streak multiplier, or passive income.
- Spending is explicit. Validate the price, wallet, lot eligibility, prerequisites, and footprint before applying a purchase.
- Deduct coins and apply the purchase as one state transition, or apply neither if validation fails.
- Affordability alone is not enough to place a building on invalid terrain or overwrite another building.
- Additional coin sources, such as milestone bonuses, remain out of scope unless separately approved.

### Initial tuning proposals

The following are adjustable test values, not additional confirmed rules:

| Setting | Proposed initial value |
|---|---|
| Starting balance | Zero coins; the starter settlement itself is free |
| Small decoration | 1 coin; 30 simulated seconds to complete |
| Ordinary building | 3 coins; 2 simulated minutes to complete |
| District expansion | 8 coins; 5 simulated minutes to complete |
| Clock speed | 1 simulated second per real second while the preview is active; adjustable in the debug panel |

Keep prices, durations, prerequisites, and the starting balance in versioned content definitions. These are fast prototype timers, not a proposed production waiting schedule. Do not apply retroactive price changes to recorded purchases.

### Construction lifecycle

```text
Choose catalogue item → select eligible lot → review cost/duration → confirm
  → debit once and reserve lot → under construction → timer completes
  → completed building or district becomes available
```

- Store the price paid, a stable construction ID, start time, and duration with the purchase.
- Allow parallel construction on separate eligible lots. There is no builder quota, queue, cancellation, refund, or demolition UI in V1.
- Reserved lots count as occupied even before their building is finished.
- A district under construction does not expose buildable lots until it finishes. Unlock/build prerequisites should explicitly distinguish purchased, under-construction, and completed states.
- Readiness depends only on the injected synthetic construction clock, not animation completion or frame count.
- Fast-forwarding completes every due job exactly once, including multiple jobs finishing during one jump.
- Save the fake clock and active jobs. Refresh resumes them without real-world catch-up.
- Track construction elapsed time separately from the rewound check-in calendar: moving the displayed date backward must not undo completed work or make construction remaining time increase. An explicit scenario reset/restore can replace both clocks together.

### Candidate growth structure

Use content-defined districts and a building catalogue:

1. **Village centre:** small homes, greenery, and basic paths.
2. **Town district:** shops, public spaces, and more connected streets.
3. **City district:** denser housing and larger civic/commercial buildings.

These are visual/content stages, not rankings of the user's financial worth. District prerequisites and prices should be tunable. Initially use authored lots rather than procedural road planning or unrestricted construction.

## 6. Determinism and saved state

Separate durable progression from ambient presentation.

- Durable actions include check-ins, purchases, explicit placement choices, and unlocks.
- Animation elapsed time, camera position, and decorative movement must not determine rewards or purchase validity.
- With the same starting definitions, seed, rules version, and ordered commands/events, the settlement and wallet should be identical.
- If cosmetic variants are randomized, derive them from stable IDs or record the chosen variant. Adding one building should not reroll existing buildings.
- Include schema, map, and rule versions in any saved snapshot so future changes can be migrated deliberately.
- Do not use the user's real financial history as a seed or regenerate the entire settlement whenever source data refreshes.
- User choices mean identical check-in totals need not produce identical cities. Identical histories of choices should.

A suggested state contains a simulated calendar date, construction-clock time, credited dates, earned/spent coin totals, wallet, building instances, active construction jobs, unlocked districts, and a command/event history. Store it in a dedicated versioned local-save record; validation and schema changes must preserve or explicitly migrate its invariants.

## 7. Synthetic debug panel

All debug controls are for the isolated preview, not financial data mutation. Keep them behind an explicit debug/test mode so they cannot become production coin controls by accident.

### Clock controls

- Display and set the simulated date/time.
- Advance one day, seven days, or thirty days **without** checking in.
- Run a separately labelled scenario that advances days and checks in on each day.
- Pause/resume a scripted preview and adjust its playback speed.
- Rewind the clock to test duplicate-date handling without resetting credited history.
- Expose the synthetic construction clock, remaining durations, and a jump-to-next-completion action.
- Auto-save the current synthetic clocks and construction state. Resume from the saved time without counting the real interval while the preview was closed. Pause simulation when the page is hidden to avoid browser-dependent background throttling.

Use an injected simulation clock. Derive rewards from calendar-date keys rather than elapsed 24-hour durations, and do not change the machine clock. Set an explicit simulated time zone/date policy; avoid accidental daylight-saving or device-time-zone changes in repeatable tests.

### Counter and scenario controls

- Show credited check-in days, wallet, total coins earned/spent, building count, and unlocked districts.
- Provide named village, town, and city scenarios.
- Allow labelled test coin grants or loading a synthetic wallet for affordability checks.
- Prefer replaying commands to changing several related counters independently. Clearly label direct overrides as test-only and log them separately from daily rewards.
- Persist through a dedicated, versioned local browser-storage key. Warn clearly if persistence fails; do not silently claim a successful save.
- Reset that prototype save only, with confirmation.
- Explicit export/import is deferred; named scenarios can load predefined synthetic snapshots without requiring a file importer.

Changing date, daylight, zoom, or animation speed must never itself add coins. Pressing Check In repeatedly on the same credited date must leave the wallet unchanged.

## 8. Implementation stages and exit checks

### Stage 0 — Record product choices and audit the pack

Use the confirmed product choices above; tune the provisional prices and timer values during testing. Verify the actual CC0 license and useful sprite inventory. Choose logical tile dimensions and normalize a small set of anchors without altering the artwork.

**Exit:** documented initial economy/interaction, license provenance, and a small asset catalogue sufficient for three visual scales.

### Stage 1 — Render an attractive, coherent starting map

Host the standalone scene on the separate port. Add authored geography, roads, several buildings, selection, and camera controls. Work on correct alignment, layering, and readability before adding progression.

**Exit:** an unchanged pack sprite sits correctly on its lot; nearby buildings and tall objects overlap correctly; the scene works at desktop and narrow mobile widths.

### Stage 2 — Add check-in coins and purchases

Implement pure progression rules, synthetic clocks, wallet, once-per-date check-in, catalogue/lot purchases, parallel construction timers, and separate local persistence. Keep all validation independent of the rendering engine.

**Exit:** one coin per eligible date; invalid/duplicate actions make no unintended changes; valid purchases debit and reserve a lot together; due construction finishes once; a refresh restores the same synthetic state without closed-time catch-up.

### Stage 3 — Demonstrate village-to-city expansion

Add district prerequisites and enough authored lots/building choices to inspect several scales. Include the chosen construction behavior. Do not add a separate economy or citizen-management game.

**Exit:** expansions are connected, established places remain stable, and the map reads as a progressively larger place rather than unrelated sprites scattered on terrain.

### Stage 4 — Debug scenarios, asset swap, and usability pass

Add scenario replay, the chosen persistence mode, keyboard-accessible controls, reduced-motion behavior, and a small alternative-manifest test. Profile the late-stage scene on the web.

**Exit:** deterministic replay, reliable reset/reload behavior, an art swap that preserves logical layout, and a short run/test guide. Do not claim a visual-style overhaul is zero-effort merely because file indirection works.

## 9. Test plan

### Progression tests

- First check-in on a date adds one coin; repeated check-ins add none.
- Check-ins on different current simulated dates each grant one coin; missed dates are not automatically rewarded and cannot be claimed through a backfill action.
- Clock rewind, refresh, and replay do not duplicate rewards.
- Advancing dates and ambient timers alone grants no coins.
- Purchases enforce non-negative integer wallets and configured prices.
- Insufficient coins, invalid lots, collisions, and unmet prerequisites change neither wallet nor map.
- A valid purchase records the debit and reserves its lot once; construction completion applies the building/unlock once.
- Parallel construction is permitted on different lots but not on the same reserved footprint.
- Calendar rewinds do not undo finished buildings or extend active construction timers.
- Time jumps complete all due jobs once; reprocessing the same clock time is a no-op.
- An unopened district's lots cannot be purchased while its expansion is still under construction.
- Refresh restores credited dates, wallet, active constructions, and the fake clock without applying real elapsed time.
- An invalid local save or storage write failure produces a clear recoverable error instead of a false save confirmation or silent reset.
- Identical initial state and commands produce identical logical state.

### Content and rendering tests

- Referenced art exists; animation frames, dimensions, anchors, lot footprints, and required roles validate.
- The selected sprites have recorded source and license information.
- Terrain, roads, structures, and foreground props have correct layering and selection behavior.
- Swapping a compatible art manifest leaves geography, building positions, wallet, and event history unchanged.
- Village/town/city screenshot checks and a manual browser review confirm alignment and composition.
- Pan/zoom, selection, purchase controls, and debug controls work on desktop and narrow mobile layouts.
- Pause off-screen work and respect reduced motion; measure the large-scene performance rather than relying only on unit tests.

### Isolation checks

- The preview makes no OAuth or Sheets requests and reads no production financial records.
- It uses no Accountable storage keys or real milestone flags.
- The existing app and its development server remain unaffected.

## 10. Decision record and remaining tuning

The user answered the initial product questions as follows:

| Topic | Confirmed choice |
|---|---|
| Spending | Catalogue plus eligible authored lots |
| Roads | Fixed in V1; consider district road-template choices on unlock later |
| Economy | Tiered coin costs |
| Check-in | Explicit today-only button, no review requirement or backfill |
| Construction | Simulated timers |
| Concurrent jobs | Parallel builds on separate lots |
| Closed preview | Synthetic time pauses; no real-world catch-up |
| Cancellation | Not in V1; show terms before purchase confirmation |
| Persistence | Dedicated local browser save |

There are no remaining blocking product questions for the first prototype. The starting wallet, prices, durations, lot count, district prerequisites, and decorative animation remain **tuning proposals**. The separate `lib/citysim/main.dart` entry point and port `9101` are implemented; the scene uses Flutter canvas painting rather than Flame. Record progression tuning changes here rather than treating the initial values as permanent finance-app behavior.

## 11. Explicit non-goals for this first version

- Production finance-app integration, OAuth, Sheets-backed city saves, or historical transaction replay.
- Passive coin generation, paid currency, advertising, or coin purchases.
- Multiplayer, rankings, account/device synchronization, or anti-cheat guarantees.
- Full traffic simulation, staffing, survival needs, complex pathfinding, or resource production chains.
- Infinite procedural geography, a general-purpose map editor, or arbitrary free placement.
- Bespoke art production, mixed art styles, or improvised vector overlays.

The synthetic clock is intentionally controllable. It is a testing tool, not a secure production entitlement system. Real multi-device check-ins and persistence will need a separate design before production integration.
