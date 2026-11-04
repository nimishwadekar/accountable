# Parcel World — Game Mechanics and Features Plan

**Status:** current product/mechanics reference for the parcel-world prototype. Implemented behavior is distinguished from tuning values and future ideas.  
**Date:** 2026-11-03  
**Prototype:** `lib/main.dart` in the `citysim/` package  
**Technical plan:** [Parcel World Implementation Plan](PARCEL_WORLD_IMPLEMENTATION_PLAN.md)

This document describes what the player can do and how the game is intended to
feel. Code structure, data formats, renderer design, and test procedures belong
in the technical plan.

## 1. Experience and guardrails

Build a calm, long-term isometric settlement that can grow from a small village
toward a country-scale world. The player gradually shapes parcels, roads,
buildings, decorations, and bridges into a place with a recognizable history.

The game should reward deliberate participation and planning, not spending
volume, optimization, or constant attendance:

- No rewards from transaction counts, amounts, or production data.
- No passive income, streak bonuses, missed-day penalties, or automatic
  check-ins.
- Missing a day or closing the app never damages, removes, or downgrades the
  settlement.
- Construction does not advance with wall time or simulated-day advancement.
- The prototype remains synthetic and separate from Accountable's financial
  data and workflows.

## 2. Current playable loop

1. Explicitly check in for the current simulated date to earn one coin.
2. Save coins or spend them on neighboring land, roads, buildings, bridges, or
   decorations.
3. Plan construction for free, assign a builder immediately, and contribute
   saved coins when ready.
4. Expand connected roads and accessible land, then place more structures.
5. Revisit the settlement as it grows; there is no penalty for taking a break.

The starter world has one empty 8×8 parcel, one free dirt-road tile at its
center, no buildings, and zero coins. Current geography is a deterministic
river/lake/coast fixture; broad regional generation is future work.

## 3. Coins, check-ins, and calendar

### Check-ins

- One explicit check-in earns one coin for the current eligible simulated date.
- A date can be credited once. No backfill, streak multiplier, or missed-day
  penalty is used.
- Advancing the calendar does not award coins; the player must check in
  explicitly for each eligible date.
- Rewinding the displayed date does not make already-passed, uncredited dates
  eligible again.
- Test-only debug grants are not part of normal play or progression.

### Spending and project funding

- The wallet starts at zero. Coins come from explicit check-ins in normal play.
- Parcel purchases and instant decorations are paid immediately.
- Building, road-stretch, and bridge plans are free. Their costs are contributed
  explicitly from the wallet; partial contributions persist.
- A project completes immediately when its full cost is contributed. Calendar
  advancement alone never changes its progress.
- A player may save coins and contribute more than one coin at once. There is no
  requirement to fund a project as soon as it is planned.

## 4. Land and expansion

- Parcels are adjacent grids of cells. The current parcel size is 8×8.
- A normal parcel purchase must extend from accessible territory and contain at
  least some land. Owning land across a river does not make that bank accessible.
- Land connectivity and road connectivity are different: a player can reach dry
  land without having a connected road there.
- The player pays for a parcel before developing it. New parcels contain no
  placed buildings, roads, or decorations.
- Lakes can be routed around; the current rules do not allow bridging lakes or
  oceans. Rivers require a valid bridge where no land route exists.
- A bridge plan can quote and purchase needed crossing parcels as part of
  committing that bridge plan; the bridge itself remains unfinished until its
  cost is funded.

Current parcel prices are prototype values and may be retuned. The implementation
uses a base price with modest outward and owned-parcel increments; the precise
formula is documented with the rules code rather than treated as a permanent
shop price.

## 5. Roads and builders

### Builders

- The prototype starts with one builder; the starting capacity is fixed at
  1 and is a product rule, not content.
- Every planned building, road stretch, or bridge takes one available builder
  immediately. Active planned places cannot exceed builder capacity.
- A builder stays assigned until its project is fully funded and finished.
- Builder capacity grows with the settlement's population: the content
  defines a progression table of population thresholds and the capacity each
  grants (monotonic; the highest crossed threshold wins). The table ships
  empty for now — one builder forever — and becomes editable in the content
  editor. Grants reconcile upward when a save loads, so editing progression
  after the fact never short-changes an existing settlement.
- There is no cancellation or refund mechanic in the current prototype.

### Road stretches

- Planning a four-connected road stretch is free and reserves one builder for
  that whole stretch.
- The player manually selects each planned road tile to fund it. Each tile costs
  one coin, regardless of dirt/asphalt style.
- Only an unfinished tile adjacent to a finished connected road tile can be
  funded. A newly finished tile extends the frontier, allowing the next tile to
  be funded; unfinished plans cannot be used to jump ahead.
- Each funded tile becomes a completed road immediately. Buildings require
  access to the completed connected road network, not just a planned road.
- Dirt and asphalt are visually different but connect equally. Road upgrades,
  demolition, and road-type bonuses are not part of the current feature set.

The current prototype treats a drawn road stretch as one builder project, while
funding its tiles individually. This is the active implementation behavior.

## 6. Buildings, decorations, and bridges

### Buildings

- Select a catalogue model and a legal footprint beside a completed connected
  road. Every footprint cell must be owned, accessible, dry, vacant, and outside
  other reservations.
- Planning is free and immediately reserves the footprint and a builder.
- Each model lists several sprite variants (e.g. the cottage in yellow, blue,
  and red); one is rolled deterministically per placement and snapshotted onto
  the structure, so repeated builds of the same model look varied while
  staying stable across reloads. Variants are content — editable in the
  dashboard.
- **Door sides face the road.** A building sprite carries two hand-drawn
  door facings (left and right). At planning the game looks at which half of
  the footprint the adjacent finished road touches: grid north/east frontage
  (the screen-right half) faces the door right, grid south/west frontage
  (the screen-left half) faces it left, and a road behind the building still
  counts — the door lands on the visible facade around the corner from it,
  on the same screen side. A road on only one half fixes the door; roads on
  both halves leave the choice to the player, who can flip it with a
  floating swap button while the plan is unfinished. The chosen side is
  snapshotted onto the plan and survives funding, saves, and reloads. While
  a building plan is unfinished, a bobbing arrow above the site points at
  the door side; it disappears once the building completes.
- Contribute coins manually; the building appears when fully funded.
- Unfinished buildings do not provide road access or count toward model-unlock
  milestones.
- Current catalogue prices and footprints are balancing defaults, not final
  commitments. Most current models occupy 1×1 cells; the largest current models
  use 2×2 footprints.

### Decorations

- Decorations are paid and placed instantly, use no builder, and do not wait for
  simulated days.
- They require owned, accessible, vacant dry land but do not require road
  adjacency.

### River bridges

- A bridge must start at a connected road, end on dry land, and cross one
  continuous straight river span. Current maximum span is four water tiles.
- Planning reserves the crossing and assigns a builder. Any quoted crossing
  parcels are bought when the plan is committed.
- Bridge coins are contributed manually. The bridge opens in one transition
  when fully funded; no half-built bridge provides access.
- The far-bank landing becomes part of the connected road/access network at
  completion.

Current bridge price is length-based. Parcel, building, and bridge price values
should be tuned through playtesting; do not compensate for a slow economy with
automatic coin rewards.

## 7. Catalogue progression and features

### Population and model unlocks

**Population** is the settlement's progression metric: the sum of each
completed building's population value (decorations contribute 0 by
default). It is derived from placed structures — never stored — and only
completed, fully funded buildings count. The game header shows it alongside
coins.

Building models unlock at population thresholds: a model becomes available
once the settlement's population reaches its unlock value. The current
seed uses uniform population 1 per building with thresholds at 5, 10, and
20, replicating the earlier completed-building milestones exactly; both
per-model population and unlock thresholds are content values tuned in the
editor. A completed project can unlock models; an active, partially funded
project cannot.

Unlocking a model does not upgrade or replace existing buildings and does not
award coins. When content thresholds are lowered, saves gain any
newly-expected unlocks on load (recorded once); unlocks are never removed
retroactively. A dedicated building-upgrade system remains out of scope for
the current slice.

### Features currently present

- Isometric map with pan, zoom (touch pinch, mouse wheel, and trackpad), and camera reset.
- Inspect, parcels, roads, buildings, decorations, and bridge tools.
- Terrain, ownership, road, structure, reservation, and project-progress views.
- Manual calendar controls, explicit check-in, and a clearly labelled test-only
  coin grant.
- Recent event history and a separate local parcel-world save.
- Ambient life that is presentation-only: pedestrians wander connected roads
  using the pack's walk cycles, water carries a gentle travelling shimmer, and
  vegetation (trees, flowers) sways slightly in the wind. Ambience is muted
  when the platform requests reduced motion, is excluded from saves and
  progression, and never affects gameplay.

## 8. Future features and open decisions

These are candidates, not promises or requirements for the current prototype:

- Seeded regional terrain and expansion across a country-scale world.
- Additional builders and the milestones/costs for increasing builder capacity.
- More settlement regions, naming, historical snapshots, and a regional overview.
- Additional building models, footprints, and progression milestones.
- Long-term save export/backup and resilience for years of play.
- Optional ambience, residents, or seasonal presentation that never penalizes
  absence or makes residents a resource-optimization system. Deferred
  animation follow-ups: a true water-flow shader, a wind-gust sweep over
  grass, and ambient vehicles using the pack's driving sprites.
- Optional personal-life themes or financial milestones. These would require a
  separate product decision and must not turn spending or sensitive data into a
  requirement for ordinary settlement growth.

Before committing to additional mechanics, decide:

1. ~~How and when should builder capacity increase, if at all?~~ Decided:
   population-threshold grants, editable in the content editor, starting
   capacity fixed at 1.
2. Are current parcel, building, and bridge prices sustainable over months and
   years of explicit check-ins?
3. Are current model-unlock thresholds and catalogue tiers satisfying?
4. Which regional features, if any, are required for country-scale expansion?
5. Which long-term presentation features belong in the game, versus remaining
   visual ideas only?

## 9. Product boundaries

- No transaction-based rewards, passive production, premium currency, market,
  staffing, resource chains, leaderboards, or mandatory streaks.
- No actual finance-data integration in this prototype.
- No demolition, relocation, cancellation, refunds, or automatic construction
  timers in the current slice.
- The map is intended to grow over the long term, but generated country-scale
  geography and long-run content balance are not yet implemented.
