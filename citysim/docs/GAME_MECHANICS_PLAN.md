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
authored parcel map in `terrain.json` (grass and water parcels on a
  bounded map with open ocean beyond it); the map editor and finer
  detail layers are future work.

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
- Check-in state persists as the last credited date and a total count; the
  dated ledger itself is not stored.

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
  oceans. Rivers require a valid bridge where no land route exists. Decided
  direction: bridges will eventually span any water body — straight line,
  both ends on land, starting from a road — with cost as the limiter; see
  the implementation plan.
- A bridge plan can quote and purchase needed crossing parcels as part of
  committing that bridge plan; the bridge itself remains unfinished until its
  cost is funded.

Current parcel prices are prototype values and may be retuned. A parcel costs
a base price plus a per-population surcharge — expanding a settlement gets
pricier as it grows, so land becomes a progression gated by the tax base that
must pay for it. Population only ever rises (no demolition, no churn), so the
price is monotonic and cannot be gamed by shrinking. The precise formula is
documented with the rules code rather than treated as a permanent shop price.

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

- Planning a straight road stretch is free and reserves one builder for
  that whole stretch. Roads place anywhere on owned, vacant, dry land —
  they no longer need to attach to the existing road network.
- Planning is a two-click tool: the first click sets the start tile, the
  next click sets the end tile projected onto the closer axis (ties go
  horizontal), and further clicks move the end. A translucent preview
  shows the final tiles — following the cursor on desktop, fixed after
  the end click on touch — with invalid tiles marked.
- Funding is per project: selecting any tile of an active project selects
  the whole project, and each coin completes the next tile in order from
  the start. Under-construction tiles render as dirt ground until their
  coin arrives.
- All roads are asphalt; the dirt ground texture is the
  under-construction visual only.
- Each funded tile becomes a completed road immediately. Buildings
  require a road beside them — any completed road, connected or not.
- Tapping a completed road selects its section: the straight run between
  the nearest junctions, turns, or dead ends.
- Road upgrades, demolition, and cancellation are not part of the
  current feature set.

## 6. Buildings, decorations, and bridges

### Buildings

- Select a catalogue model and a legal footprint beside a completed
  road. Every footprint cell must be owned, dry, vacant, and outside
  other reservations.
- Planning is free and immediately reserves the footprint and a builder.
- Each model lists several sprite variants (e.g. the cottage in yellow, blue,
  and red); one is rolled deterministically per placement and snapshotted onto
  the structure, so repeated builds of the same model look varied while
  staying stable across reloads. Variants are content — editable in the
  dashboard.
- **Doors face the road.** A building sprite carries two hand-drawn door
  facings (left and right art). At planning the game snapshots *which
  road side* the door faces as a compass value — north, east, south, or
  west — one of the sides with an adjacent finished road. The art variant
  follows the side's screen half: grid north/east (screen-right) draws the
  right-facing door, grid south/west (screen-left) the left; a road behind
  the building still counts — the door lands on the visible facade around
  the corner from it, on the same screen side. When only one half has
  frontage the side is fixed; roads on both halves leave the choice to the
  player, who can flip it to the other half with a floating swap button
  while the plan is unfinished. The chosen side survives funding, saves,
  and reloads. While a building plan is unfinished, a bobbing arrow above
  the site points at the door side; it disappears once the building
  completes.
- **Facing offset (per-sprite content).** Each facings sprite carries a
  `facingOffset` in tiles (−0.5 to 0.5, default 0) that shifts its art
  toward the road side the door faces — main-street buildings can sit
  close to their road from any direction while symmetric ones stay at
  zero. Picking follows the shift, and the dashboard's plot preview tunes
  it against all four road sides.
- Contribute coins manually; the building appears when fully funded.
- Unfinished buildings do not provide road access or count toward model-unlock
  milestones.
- Current catalogue prices and footprints are balancing defaults, not final
  commitments. Most current models occupy 1×1 cells; the largest current models
  use 2×2 footprints.

### Decorations

- Decorations are paid and placed instantly, use no builder, and do not wait for
  simulated days.
- They require owned, vacant dry land but do not require road
  adjacency.

### Bridges

- A bridge is planned with the same two-click straight tool as roads:
  both banks need owned, vacant, dry land, and the span between them
  may cross water and land alike. Bridges can go anywhere — including
  entirely over land.
- Everything under a bridge must already be owned. Nothing is
  auto-acquired: water parcels are bought before bridging, like land.
  Spans cannot cross roads, buildings, or other bridges.
- Planning is free and reserves a builder. Funding is per project,
  coin by coin: the near bank completes as a road tile first, then each
  span tile (flat per-tile price, content-tunable), then the far bank.
  Under-construction span tiles render as dirt ground; funded tiles
  appear as bridge deck one at a time.
- The bridge opens when fully funded; the far-bank landing joins the
  road network at completion.

Current bridge pricing is flat per span tile with road-priced banks.
Parcel, building, and bridge price values should be tuned through
playtesting; do not compensate for a slow economy with automatic coin
rewards.

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

- World map editor for authored terrain — the agreed next project (design and
  sequencing in the implementation plan) — with seeded regional generation
  beyond the authored map as a later phase.
- Additional builders and the milestones/costs for increasing builder capacity.
- More settlement regions, naming, historical snapshots, and a regional overview.
- Additional building models, footprints, and progression milestones.
- Google Sheets sync for game data: the four-sheet storage (CSV documents
  for now, the game's own spreadsheet once created) replaces ad-hoc
  export/backup.
- Tap-picking follow-ups on top of the landed per-pixel picking (sprite
  alpha masks tested in painter order, ground diamond as fallback):
  click cycling for targets genuinely hidden behind tall art,
  tool-based pick priority, and x-ray dimming (spec in the
  implementation plan).
- Free prop placement: props anywhere on terrain, roads, and bridge
  decks; several props on one cell; live mirroring and swapping
  between direction variants after placement; prop removal. Full
  technical breakdown (fifth save sheet, prop entity, deck-height
  anchoring, mirror-aware picking) in the implementation plan.
- Optional ambience, residents, or seasonal presentation that never penalizes
  absence or makes residents a resource-optimization system. Deferred
  animation follow-ups: a true water-flow shader, a wind-gust sweep over
  grass, and ambient vehicles using the pack's driving sprites.
- Optional personal-life themes or financial milestones. These would require a
  separate product decision and must not turn spending or sensitive data into a
  requirement for ordinary settlement growth.
- Staged building foundations, re-scoped to the check-in economy below:
  a planned building pours its concrete slab immediately (the single
  decision point is `foundationGroundStyle` in
  `lib/world/world_queries.dart`), which stays the stage-1 behavior
  under the single-site-look decision; dirt in a project's early
  stages and concrete as it progresses remains a future per-stage
  option.

### Check-in economy and settlement growth (future work)

Decided direction from the 2026-11-06 design discussion; the first
implementation stage — the simplified economy — was scoped on
2026-11-13 and implemented on 2026-11-14 (decisions and seed values
below). Settlement growth — household arrival, occupancy, growth
rules — remains future work.

**Where population comes from (lore frame).** The mainland exists
off-map; the starter road is the last stretch of an old trail that
reaches it, and boats are the second route. Arrivals are households,
they arrive in lumps tied to check-ins (never a smooth trickle), and
they need a route plus housing. When land pressure builds, splinter
households strike out and homestead disconnected land — another
island, not a nearby corner, because settlements within walking
distance merge and water is what keeps two towns two towns. They raise
their own homes slowly, by their own labor. A cluster earns a town
name at some size. Towns connect late — ferry first, bridge last,
both player-built. As islands fill, new landmasses are colonized by
boat: never grow an existing landmass, author a new one. The player is
the founder-proprietor, and the role matures from pioneer (the town
runs on your starting stake) to mayor-steward (the town funds itself
through you). Settlers never build roads or infrastructure. Residents
never leave — no churn penalties, flavor lines at most.

**The economy.** One town treasury; the wallet merges into it. The
check-in stays the only heartbeat: nothing progresses in real time or
on simulated days, and taxes are collected *on* the check-in, never
trickled between them. Each check-in becomes a town-report event —
collect taxes, net upkeep, advance every active construction one stage
(later also: household arrivals and rule-driven growth).

- **Labor builds the town.** Homes and ordinary buildings are planned
  without coins and advance one stage per check-in; stage counts are a
  per-model content knob standing in for construction complexity.
  Crew/concurrency limits gate how many projects can grow at once, and
  population-gated capacity is the throughput curve.
- **Taxes build the infrastructure.** Tax is X coins per building and
  upkeep is Y coins per building — both content fields, editable in
  the dashboard, netted each check-in. Civic services and
  infrastructure cost more in upkeep than they pay in tax (roads:
  tax 0, positive upkeep), so they are a real maintenance expense;
  homes and commerce carry the tax base (decided 2026-11-13: shops
  and offices net positive). The anti-compounding guard rests on
  civic upkeep, infrastructure upkeep, and crew capacity, with a
  future growth rule — commerce needs nearby homes — as the backstop
  against shop farming.
- **Treasury purchases** are parcels, road stretch plans, and bridges
  — in stage 1 all buildings, civic ones included, plan free and are
  built by labor (a per-model planning fee for landmarks can be
  revisited later). Parcels are population-scaled (base plus a
  per-population surcharge), keeping the save-up cadence constant as
  the town grows. Road stretch plans and bridges are bought upfront
  and then build one tile per check-in — creeping construction
  replaces per-tile coin funding.
- **No coin-rush.** Growth costs check-ins, not money; a
  pay-to-finish-a-stage knob can be reconsidered later if the waiting
  ever feels dead.

**Props.** Free to place — pure creativity, no economy. Some props are
placed automatically by growth rules (traffic lights at four-way
junctions, street lamps). Causality rule: the world reacts instantly
to player actions, but only acts on its own during check-ins.

**Growth rules as content.** Auto-growth rules live in the content
layer, editor-tunable and deterministic, with outcomes stored in the
save so rule edits grandfather what is already placed. Start with a
tiny vocabulary (junction props, per-model tax and upkeep) and grow it
one rule at a time — settler claims, town founding, splintering.

**Stage 1 — the simplified economy (decided 2026-11-13).** The first
implementation stage drops household arrival and occupancy entirely:
every building keeps its flat population number, and tax is collected
per completed building. The decisions:

- **Flat values, all content.** Per-model `taxCoins`, `upkeepCoins`,
  and stage count in the catalogue; per-tile road and bridge tax and
  upkeep in `economy.json`. Road and bridge tax seed at 0 — paving
  must never mint coins. Small integers; with a daily heartbeat
  every coin is felt.
- **Money buys permission, check-ins are the labor.** Planning a
  building is free; construction costs no coins and advances one
  stage per check-in. The treasury's purchases are parcels, road
  stretch plans, and bridges, paid upfront.
- **Insolvency never blocks labor.** Each check-in nets taxes minus
  upkeep; the treasury floors at 0, the shortfall is reported in the
  town report, and every stage still advances. Money gates expansion,
  never growth — and with free building planning a broke town always
  recovers by rebuilding its tax base.
- **The daily coin is retired.** No 1-coin-per-check-in grant; the
  treasury starts at 20 coins (a placeholder — a more natural start
  is an open question below).
- **Builders are concurrent slots.** Capacity caps how many projects
  are in flight — planning holds a slot until completion — and every
  in-flight project advances one stage per check-in. The planning day
  itself advances nothing. Progression thresholds become
  load-bearing: seed 10→2, 25→3, 50→4 (the live list is empty,
  capacity 1 forever).
- **Costs start on completion.** Construction sites pay no tax and no
  upkeep; road and bridge upkeep counts per tile as it appears.
- **Bridges creep too.** Paid upfront, then the deck extends one tile
  per check-in — the existing incremental bridge rendering, driven by
  a delivered-tiles counter instead of coins funded (near ramp with
  the first tile, far ramp with the last). Road creep is automatic
  and consumes no builder.
- **One look while building.** Foundation slab plus construction-site
  appearance from planning to completion; per-stage art stays future
  work.
- **The check-in is a town report.** Itemized: taxes collected, upkeep
  paid and any shortfall, constructions advanced.
- **Migration is one line.** The live save holds zero in-flight
  constructions, so the wallet simply becomes the treasury's opening
  balance and the completed town starts paying tax and upkeep. The
  fallback, if a funded project ever exists at the switch: the funded
  fraction becomes stages done, rounded down.
- **Occupancy is deferred, not dropped.** When households arrive in a
  later stage, occupancy slots in as a multiplier on the flat tax
  field — nothing decided here conflicts with that.

**Stage 1 seed values (first pass; everything is dashboard-tunable
afterward).** The old prices were sized for a +1-coin-per-day income,
so upfront prices scale up alongside home taxes. Economy: starting
treasury 20; road and bridge tax/upkeep 0/1 per tile;
`parcelBaseCoins` 32 plus `parcelPerPopulationCoins` 2 per population,
`roadTileCostCoins` 4, `bridgeTileCostCoins` 12 (a lighter 24/3/8
alternative if the richer late game feels right);
builder progression 10→2, 25→3, 50→4. Homes (tax/upkeep/stages):
small 3/0/2, medium 5/0/3, large 6/0/3, mobile 2/0/2, apartments
8/1/4. Commerce nets +2 to +4 (tax/upkeep/stages): cafe 4/2/2,
ice-cream-shop 4/2/2, fruit-market 3/1/2, pizza-shop 5/3/3, autoshop
5/3/3, gas-station 6/4/3, warehouse 5/3/3, small-office 6/3/2,
tall-office 9/5/4, city-office 9/6/4. Civic drains (tax/upkeep/
stages): clinic, fire-station, and police-station 0/4/3, church
0/3/4, water-tower 0/2/2, hospital 0/6/5, construction-site 0/0/1.
Props stay free, instant, and unstaged. Calibration against the live
town (51 homes, 12 commerce, 6 civic, 109 road tiles + 17 bridge
tiles): roughly +85 per check-in; an early five-home town roughly +3.

**Multiple cities (future concept, discussed 2026-11-14).** Several
starting cities scattered around the map, unconnected at first, each
with its own progression and its own treasury; connecting them by
road is the later milestone this plan already wants to reward. The
motivation is structural: when the first city saturates, the second
replays the tight early economy, and expansion pressure never has to
carry the whole game alone. Population-scaled parcel pricing was
chosen deliberately to compose with this — it prices each parcel by
the buyer's size, so it partitions cleanly along settlement lines
where distance-based pricing would tangle cities together. The lift,
in the order the decisions force themselves:

- **Settlement partition of the state.** Per-city treasury,
  population, builder capacity, and unlock set; a settlement tag on
  every parcel. The five sheets grow a settlement dimension — the
  biggest schema change since the codec. The earned-minus-spent
  ledger invariant becomes per-city.
- **One heartbeat, many reports.** One check-in per day advances
  every city — the day passes everywhere, protecting the
  one-check-in product rule. The town report becomes a multi-city
  report or a city picker.
- **Purchase locality.** Every treasury purchase needs a settlement
  context — a road built in one city draws from that city's treasury
  alone. This is the invasive part; it touches every purchase path
  in the reducer.
- **Founding mechanics.** How a second city starts on disconnected
  land: the lore above (boat colonization, splinter households)
  supplies the story; mechanically a founding action is needed —
  claim a charted parcel, receive a starter road and perhaps a
  founding stake. Design slowly; this is genuinely new gameplay.
- **Authoring weight.** The map is hand-authored; several cities
  wants a bigger canvas and camera/UX for jumping between them.

Open even later: when a parcel borders two settlements, which one it
joins — player's choice, the bigger city, or adjacency not mattering
at all. Not a today problem.

**Open questions.** A more natural starting treasury than a flat 20;
the stage-2 occupancy model (household-by-household vs. full on
completion, riding the flat tax as a multiplier); a commerce-needs-
homes growth rule as the backstop against shop farming; whether
splinter settlers ask permission or build unilaterally; whether
settler construction renders as process (scaffolding) or arrives
between sessions; model-unlock thresholds and catalogue tiers under
the new pacing.

Before committing to additional mechanics, decide:

1. ~~How and when should builder capacity increase, if at all?~~ Decided:
   population-threshold grants, editable in the content editor, starting
   capacity fixed at 1.
2. ~~Are current parcel, building, and bridge prices sustainable over months and
   years of explicit check-ins?~~ Decided in direction: superseded by the
   check-in economy above — coin prices give way to taxes, upkeep, and
   check-in stages.
3. Are current model-unlock thresholds and catalogue tiers satisfying?
4. Which regional features, if any, are required for country-scale expansion?
5. Which long-term presentation features belong in the game, versus remaining
   visual ideas only?
6. Permanence policy: no demolition is deliberate for buildings — it fits the
   accountability theme — but decide consciously whether road removal exists
   for dead-end cleanup in long-running settlements.
7. ~~Should asphalt roads be population-gated rather than a freely chosen style?~~
   Moot: dirt is gone and asphalt is the only style; population-gating road
   access remains a content option if ever wanted.

## 9. Product boundaries

- No transaction-based rewards, passive production, premium currency, market,
  staffing, resource chains, leaderboards, or mandatory streaks.
- No actual finance-data integration in this prototype.
- No demolition, relocation, cancellation, refunds, or automatic construction
  timers in the current slice.
- The map is intended to grow over the long term, but generated country-scale
  geography and long-run content balance are not yet implemented.
