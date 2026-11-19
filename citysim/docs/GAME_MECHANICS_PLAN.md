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

1. Claim a founding parcel — the first purchase is free, anywhere
   charted with room to build.
2. Explicitly check in for the current simulated date to run the town
   report: taxes from completed buildings, minus upkeep.
3. Spend coins on neighboring land, roads, buildings, bridges, or
   decorations (decorations are free).
4. Expand connected roads and accessible land, then place more structures.
5. Revisit the settlement as it grows; there is no penalty for taking a break.

A new game owns nothing and builds nothing — no starter parcel, no pre-built
road. The founding stake (`startingTreasuryCoins`) is the opening wallet.
Current geography is a deterministic authored parcel map in `terrain.json`
(grass and water parcels on a bounded map with open ocean beyond it), and
content validation guarantees the map always offers at least one parcel
with five or more land cells, so a new game can always be founded.

## 3. Coins, check-ins, and calendar

### Check-ins

- One explicit check-in runs the town report for the current eligible
  simulated date: taxes from completed buildings, minus upkeep owed by
  buildings, roads, and bridge tiles. An empty town nets zero.
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

- The wallet starts at the founding grant (`startingTreasuryCoins`, 100,000
  in the shipped economy — a development grant covering the opening years).
  Coins come from the town report in normal play.
- **Construction is free by rule** (pinned in content validation since
  2026-11-17): buildings are gated by land, road access, and staged time —
  never by money. Coins buy parcels, roads, and bridges; nothing else.
  Decorations always were free; the pin now covers every model.
- Parcel purchases are paid immediately. Road-stretch plans are
  bought upfront from the wallet and the whole stretch lands on the
  next check-in (one day of waiting, whatever the length — tiles once
  crept one per check-in per plan, which let a stack of single-tile
  plans deliver far faster than one long street, a knowledge gate
  found by a playtest reviewer). Bridge plans are bought upfront and
  the deck still builds one tile per check-in. Structure plans
  complete one stage per check-in.
- Calendar advancement alone never completes a project.

### The realistic economy (decided 2026-11-17)

Money was rescaled to real-world magnitudes — 1 coin = $1 — with the
free-construction rule intact. Capacities count people, not households:

- **Population is people.** A small home houses 3, a large home 5, the
  apartments 40; shops offer real workplace counts (café 8, tall office
  300). The `households` field is gone; `population` on a model *is* its
  residential capacity, snapshotted per placed structure as before. The
  save key `waiting_households` became `waiting_population` (absent keys
  default to zero, so old saves load and simply reset their list).
- **Taxes are a per-capita levy** at report time: ≈ $170 per housed
  resident and $250 per job per check-in in the shipped content (civic
  buildings pay nothing — services are pure cost, which is the contentment
  trade-off). Homes pay at least the **unemployment floor** — 30% of
  their levy, with full employment topping the rate back up to 100%
  (added 2026-11-17 after a playtest reviewer soft-locked: a homes-only
  town had zero jobs, therefore zero taxes, therefore no road or land to
  place a café with, forever — unemployed people still pay rent and
  sales taxes in reality, so the floor is both the fix and the more
  realistic rule). The town report shows unemployment whenever it is
  above zero — the count only. The report states facts and never
  explains the levy's mechanics: a floor/binding line was removed
  2026-11-18 after playtest reviewers misread it (doctrine: players
  get numbers, not interpretations of numbers). The rate is the one
  pacing dial: realistic annual property
  rates (~1.2%/yr) would recoup a building in decades, so the levy runs at
  per-report scale and a blended town roughly doubles its invested value
  monthly.
- **Land, roads, bridges**: parcels $15,000 base + $150 per population;
  roads $2,500/tile ($10/tile upkeep); bridges $50,000/tile ($300/tile
  upkeep). Because the parcel price escalates with population while tax
  income scales with population, the parcel cadence stays roughly constant:
  weekly in the founding era, about one per check-in late game.
- **Founding is the city hall** (added 2026-11-18, closing the
  sparse-road-pad exploit the run-3 playtest measured — frontage
  without a network let four buildings ride one orphan tile). A
  city is founded by placing a 3×3 **city hall** with a chosen
  facing (a swap button and a direction arrow place it; north,
  east, south, or west). One road tile plants itself at the middle
  of the hall's front face, and the parcel holding hall and road
  becomes the free founding parcel; brush under the ten footprint
  cells clears with the act. The hall is pure ceremony — zero
  jobs, tax, and upkeep, five stages, church art as its
  placeholder sprite until real art lands — and it is permanent:
  it cannot be demolished, never appears in the catalogue, and
  places only through founding.
- **The outside connection**: that front-road tile is the root of
  the town's road network. Buildings construct only where their
  fronting road is transitively connected to it — road tiles join
  by orthogonal adjacency, and each bridge welds its two banks, so
  a network may cross water. **Bridge banks are not frontage**
  (2026-11-18): a bridge's near and far landings carry its ramp
  art, and a building may never face them — the network flows
  through banks, but a landing is not a street. The save validator
  enforces the connection on every standing building: a save whose
  building fronts a road off the hall's network is refused on
  load, naming the building. Roads themselves still pave anywhere
  (a network in the woods is legal; it carries no buildings until
  it links home), and because roads are permanent the connected
  set only ever grows. A town that builds on every free cell
  touching its own network seals itself in — recoverable by
  demolishing a building beside a road, which is ordinary play,
  not a trap. Every city founds its own root: multi-city maps
  never require roads between towns, and where two towns'
  networks meet they simply join. Saves from before founding
  (land with no hall) are refused on load, by absence — no
  version code anywhere.
- **Services**: fire/police/health coverage is demanded from a population
  of 300 (`serviceRequirementPopulation`) — exactly the city milestone,
  so the demand never precedes the stations that answer it (the earlier
  250 opened a measured income valley between 250 and 300); one clinic
  covers 400 people, a fire station 1,200, a hospital 3,000. Coverage is
  deliberately tighter than census reality so services stay a live
  constraint.
- **Milestones** rescaled to people: 0 / 15 / 50 / 120 / 300 / 800 / 2,000
  — Hamlet in ~5 weeks of daily check-ins, Regional Capital in about a
  year. All rates (migration 2%, employment ramp 5%, job pull 10%,
  tolerances 10%) are percentages and unchanged.
- Coin values render with thousands separators (a `formatCoins` helper);
  the clock panel's debug grant is now +10,000.
- The pre-existing cities were hand-migrated to the new scale the same
  day (the sanctioned path — saves are data, never code): city_1 kept its
  fully-occupied, ~96%-employed character (population 254 = its 51 homes'
  new capacities; 244 employed of 966 jobs), a treasury at
  purchasing-power parity with the old one (100,000 ≈ 1.8 parcels then
  and now), and a lifetime earned/spent ledger reconstructed from its
  parcels, roads, and bridge tiles at new prices. Its missing milestone
  row derives 'town' (120) from the migrated population on first load —
  models above town that it already owns stay valid possessions, and
  re-crossing 300 (city) re-unlocks placing them. city_2 was reset to
  the new founding grant minus its two road tiles.

## 4. Land and expansion

- Parcels are adjacent grids of cells. The current parcel size is 8×8.
- **The founding purchase** (a new game's first) is free, needs no neighbour,
  and requires five or more land cells — enough room for a first road and
  home, so the opening can never dead-end on water. Every later purchase
  is normal: it must neighbor owned land, and it may be any charted parcel,
  grass or water alike. Owning land across a river does not make that bank
  accessible.
- Land connectivity and road connectivity are different: a player can reach dry
  land without having a connected road there.
- The player pays for a parcel before developing it. New parcels contain no
  placed buildings, roads, or decorations.
- Zero-owned-parcel start (2026-11-16): a new game begins with **zero owned
  parcels** — the player claims the founding parcel, and the starter parcel
  is retired (its (0,0)-grass content validation and editor lock retired
  with it). Purchase is the only path to ownership, which the nature-props
  design relies on: terrain vegetation materializes into the save exactly
  at parcel purchase, so no creation-time copy exists — and "new parcels
  contain no placed anything" keeps that one exception: copied nature
  props, cleared by the player before building on them.
- Lakes can be routed around; the current rules do not allow bridging lakes or
  oceans. Rivers require a valid bridge where no land route exists. Decided
  direction: bridges will eventually span any water body — straight line,
  both ends on land, starting from a road — with cost as the limiter; see
  the implementation plan.
- Parcels are only ever purchased explicitly and manually. Bridge plans have
  not quoted or acquired crossing parcels for a long time (this page said
  otherwise until 2026-11), and nothing at all can be done in a place before
  its parcel is purchased.

Current parcel prices are prototype values and may be retuned. A parcel costs
a base price plus a per-population surcharge — expanding a settlement gets
pricier as it grows, so land becomes a progression gated by the tax base that
must pay for it. Population only ever rises today (no demolition, no churn),
so the price is monotonic; once demolition lands (§8) the price tracks
current population and may fall with it — a town that drives out its
residents cheapens its own land, paid for in permanently lost people.
The precise formula is
documented with the rules code rather than treated as a permanent shop price.

## 5. Roads and construction

### Road stretches

- Planning a straight road stretch is free and holds that
  whole stretch. Roads place anywhere on owned, vacant, dry land —
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
  current feature set; demolition is planned with dependent checks and
  refund rules (see §8).

## 6. Buildings, decorations, and bridges

### Buildings

- Select a catalogue model and a legal footprint beside a completed
  road. Every footprint cell must be owned, dry, vacant, and outside
  other reservations.
- Planning is free and immediately reserves the footprint.
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

- Decorations are free by rule and placed instantly, and do
  not wait for simulated days (content validation pins every decoration's
  cost to zero — props are the one thing a new settlement can spend on
  before its first road, so they can never drain the founding treasury).
- They require owned, vacant dry land but do not require road
  adjacency.
- Placed props are physical: buildings, road stretches, and bridge banks refuse
  cells carrying a prop until it is removed (removal is free and instant,
  through the Demolish tool) — clear the land first.
- Nature props are the map's, not the save's: the terrain editor's brush
  sprinkles trees, flowers, and rocks onto unowned land, the game shows them on
  the frontier, and buying a parcel makes its nature part of the save — the
  settlement's to clear before building. Nothing can be done anywhere before
  its parcel is purchased.

### Bridges

- A bridge is planned with the same two-click straight tool as roads:
  both banks need owned, vacant, dry land, and the span between them
  may cross water and land alike. Bridges can go anywhere — including
  entirely over land.
- Everything under a bridge must already be owned. Nothing is
  auto-acquired: water parcels are bought before bridging, like land.
  Spans cannot cross roads, buildings, or other bridges.
- Planning is free. Funding is per project,
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

### Population milestones and unlocks

**Population** is the settlement's progression metric: the sum of each
completed building's population value (decorations contribute 0 by
default). It is derived from placed structures — never stored — and only
completed, fully funded buildings count. The game header shows it alongside
coins.

**Milestones** are the progression layer above the catalogue
(`progression.json`): named population thresholds, each carrying the models
that unlock for *placement* when reached. The catalogue no longer knows its
own tier — models are a layer below milestones, re-tired by dragging them
between milestone rows in the editor's Progression tab. A model in no
milestone is legal and meaningful: not part of the progression, placeable
never — and, for nature-capable decorations, existing purely as authored
terrain vegetation (the extreme of the exotic
strategic-parcel idea — buying land for what grows on it, not what you can
plant). The shipped ladder is Homestead 0, Hamlet 5, Village 10, Town 15,
City 20, Metropolis 25, Regional Capital 30. The fresh-game floor is
content-checked as a warning plus a shipped-content test: at least one
residential model must unlock at the population-0 milestone, or a new game
can never gain population.

**Unlocks gate placement, never possession.** Saves may legally hold items
above the reached milestone — nature exotics materialized by purchase,
models re-tiered by content edits — and validation never rejects them;
only new placement checks the unlock set. Removing a locked prop is
allowed (clearing land is sacred) but it cannot be placed again until its
milestone, which the removal dialog says.

**The high-water milestone never regresses.** The save stores the last
milestone reached (stable id, plus the population threshold it had when
reached — the fallback if the milestone is later deleted from content)
rather than re-deriving unlocks from population on every load. Population
dips — however they one day arrive — cannot re-lock anything. Within a
session the unlock set only ever grows (union, never replacement), and
each newly reached milestone reports as one named event ("Village reached
· 4 new model(s) placeable") instead of per-model unlock spam.

When content thresholds are lowered, saves gain any newly-expected
unlocks on load (the load-time reconcile crosses what the population
already reaches, and the derived set flows content edits in reached
milestones into play). Unlocking a model does not upgrade or replace
existing buildings and does not award coins. A dedicated
building-upgrade system remains out of scope for the current slice.

### Features currently present

- Isometric map with pan, zoom (touch pinch, mouse wheel, and trackpad), and camera reset.
- Inspect, parcels, roads, buildings, decorations, and bridge tools.
- Terrain, ownership, road, structure, reservation, and project-progress views.
- Manual calendar controls, explicit check-in, and a clearly labelled test-only
  coin grant.
- Recent event history and a separate local parcel-world save.
- Ambient life that is presentation-only: pedestrians wander connected roads
  using the pack's walk cycles — their count a percentage of population
  (`populationPercent`, 20%, floored at one walker once anyone lives there;
  0% turns them off; painted sidewalk still bounds the count), each new
  walker appearing at the doorstep of a random building, moving at the
  gait-consistent pace the walk cycle depicts (~2.4–3.6 m/s, feet landing
  on the stride) — water carries a
  gentle travelling shimmer, and vegetation (trees, flowers) sways slightly
  in the wind, stilling below the sway zoom gate (`minScale`, 0.75 — at far
  zoom the rock is a sub-pixel shiver not worth a per-sprite transform).
  Ambience is muted when the platform requests reduced motion,
  is excluded from saves and progression, and never affects gameplay.
- A physical scale for the map: one tile is 12 m of ground — walkers read
  ~1.69 m, the human average; a road tile, a complete street; a one-tile
  cottage, 144 m² — so the town card reports city limits and built-up area
  in km² (owned parcels vs. structure footprints plus roads; bridge water
  spans and unfinished constructions stay out) and average population
  density (population ÷ city limits).
- Ambient car traffic, presentation-only like the walkers: one slot per
  population share (`populationPercent`, 10%, floored at one car once
  anyone lives there), each running errands — spawn stopped on the lane
  at a random building's front, dwell, drive a planned lane path to a
  home-biased end building at least `minTripCells` (10) road cells away
  (the planner's distance map filters nearer ends, so no rerolls), park
  on the lane, and leave after a respawn delay. Traffic drives on
  **painted directional lanes** — the same doctrine as sidewalks: each
  road and bridge role carries lane masks keyed `north-1`…`west-4`, up
  to four lanes per direction of travel; a subtile painted for one
  direction is a lane, several directions a crossing where cars keep
  their heading, and cars never reverse. Distinct lanes of one direction
  are distinct bands — a car centres on whichever it drives and never
  weaves between them, so turning is stepping from one direction's lane
  into another and corners are authored paint. (Known limitation, noted
  2026-11: the planner breaks path ties deterministically, so parallel
  same-direction lanes pile traffic into one lane; seeded tie-breaking
  is the fix when multi-lane roads arrive.)
  Vehicle types mix by authored percents (summing to 100) with colour
  variants rolled per trip, like catalogue variations; cars climb
  bridges — pitching onto ramps through a lift-gradient rotation about the ground anchor (a rigid turn: silhouette preserved, slight lateral banking; chosen over an exact-ground affine shear whose slope-proportional vertical squash playtesting found too drastic) —
  and drive at town pace (~1 cell/s = 12 m/s). Unpainted roles
  carry no traffic, so young or unpainted towns stay foot-traffic only,
  and one-way streets are simply lanes painted in one direction.

## 8. Future features and open decisions

These are candidates, not promises or requirements for the current prototype:

- World map editor for authored terrain — the agreed next project (design and
  sequencing in the implementation plan) — with seeded regional generation
  beyond the authored map as a later phase.
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
- Manual category assignment in the editor: a building's economic
  class (residential / commerce / service / civic) is derived today
  from its numbers — population, jobs, serviceCategory — which the
  2026-11-18 civic reclassification made load-bearing (a service
  building's jobs are appeal, never levy). An editor control that
  names the class explicitly, with validation that the numbers agree
  with it, would retire the derivation as the single source of truth.
- City hall upgrades: the hall is content (`isRoot` on the model),
  zero-stat and 3×3, with church art as a placeholder. An upgrade
  path — a grander hall per milestone tier, or halls that gain
  capabilities — is pure content work on that model and its sprite
  roles.

### Demolition (planned — direction agreed 2026-11-18, refined same day)

The reviewer playtest's chunk-1 findings forced the decision: three
of four reviewers hit "full parcel = dead parcel", the one true
soft-lock (a homes-only town with no free road frontage) had
demolition as its only escape, and every game in the genre ships it
as the universal solvency lever. The prior blockers and their
resolutions:

- **The accountability theme.** §9's open question — "no demolition
  is deliberate; it fits the accountability theme" — resolves as:
  permanence lives in the *money*, not the *buildings*. Demolition
  never refunds and never profits; the town keeps what it spent.
  What you build can go; what you paid cannot come back.
- **Population monotonicity.** Parcel prices (base + per-population
  surcharge) assumed population only rises. Decided: the price
  simply tracks current population and **may fall** — a mayor
  demolishing homes and driving people out cheapens the surrounding
  land, which is honest. The exploit is paid for in people, because
  eviction can permanently lose them (below), so shrinking to
  cheapen land trades citizens for coins. Milestone unlocks stay on
  their stored high-water, unchanged.
- **The wide-lot road invariant.** Placement turns non-square
  footprints to face their road, and save validation requires that
  facing edge to stay fully roaded — a blocker for *road*
  demolition, deferred with infrastructure.
- **Occupancy aggregates.** Population and employment are counters,
  not citizens, so a demolished home cannot un-house specific
  people. The cascade: after demolition, current population is
  compared to the town's remaining beds. Everyone fits — nobody
  moves. Overflow — as many as can stay stay; the rest join the
  residential demand (the waiting list, at its normal cap); demand
  beyond the cap is dropped, those people forced out of town for
  good. Employment re-clamps to the survivors and the remaining
  jobs. Players weigh demolition seriously because they may
  permanently lose residents.

Scope, decided 2026-11-18:

- **Now: buildings and props.** Buildings demolish through the
  cascade above, no refund, the footprint freeing instantly; props
  are removed free through the same Demolish tool — there is no
  separate pick-up action anywhere in the game. In-flight
  construction sites are not demolishable — that work finishes in
  days and cancellation is a separate future feature.
- **Deferred: infrastructure.** Roads, bridges, and their dependent
  checks (wide-lot facing edges, bridge banks, project cells) wait,
  together with the cancellation-refund question. Parcels stay
  permanent for good: exclusive claims on a shared map, and the
  price is a progression, not an inventory.

Surface: a **Demolish tool** — the game's one removal surface.
Selected, tapping any building opens a small dialog — the building's
net coins per check-in, its capacity (residents housed or jobs), the
eviction consequence if the remaining beds cannot hold everyone, and
a Demolish button. Tapping a prop offers its free removal through
the same tool. The CLI mirrors the purchase flow:
`demolish <col> <row>` quotes, `demolish <col> <row> confirm`
executes. The regression test that matters: a homes-only
soft-locked town demolishes a home, builds commerce on the freed
frontage, and recovers.

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
  per-model content knob standing in for construction complexity. There
  is no concurrency cap (builders were removed 2026-11-16): any number
  of projects may grow at once, so staged check-in time is the only
  construction pacing.
- **Taxes build the infrastructure.** Tax is X coins per building and
  upkeep is Y coins per building — both content fields, editable in
  the dashboard, netted each check-in. Civic services and
  infrastructure cost more in upkeep than they pay in tax (roads:
  tax 0, positive upkeep), so they are a real maintenance expense;
  homes and commerce carry the tax base (decided 2026-11-13: shops
  and offices net positive). The anti-compounding guard rests on
  civic upkeep and infrastructure upkeep, with the
  stage-2 occupancy design below — vacant commerce earns nothing and
  pays full upkeep — as the backstop against shop farming.
- **Treasury purchases** are parcels, road stretch plans, and bridges
  — in stage 1 all buildings, civic ones included, plan free and are
  built by labor (a per-model planning fee for landmarks can be
  revisited later). Parcels are population-scaled (base plus a
  per-population surcharge), keeping the save-up cadence constant as
  the town grows. Road stretch plans are bought upfront and land
  whole on the next check-in; bridge decks still build one tile per
  check-in — visible construction replaces per-tile coin funding.
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
- **Construction is check-in-paced.** Every in-flight project advances
  one stage per check-in; the planning day itself advances nothing.
  There is no builder or concurrency cap (removed 2026-11-16 after a
  design review: with free buildings, coins and land already gate
  throughput, and a second limiter only added refusal screens) —
  planning is limited by coins, land, and staged time alone.
- **Costs start on completion.** Construction sites pay no tax and no
  upkeep; road and bridge upkeep counts per tile as it appears.
- **Bridges creep too.** Paid upfront, then the deck extends one tile
  per check-in — the existing incremental bridge rendering, driven by
  a delivered-tiles counter instead of coins funded (near ramp with
  the first tile, far ramp with the last). Road creep is automatic.
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
afterward; superseded 2026-11-17 by the realistic economy above).**
The old prices were sized for a +1-coin-per-day income,
so upfront prices scale up alongside home taxes. Economy: starting
treasury 20; road and bridge tax/upkeep 0/1 per tile;
`parcelBaseCoins` 32 plus `parcelPerPopulationCoins` 2 per population,
`roadTileCostCoins` 4, `bridgeTileCostCoins` 12 (a lighter 24/3/8
alternative if the richer late game feels right).
Homes (tax/upkeep/stages):
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

**Stage 2 — demand, occupancy, and contentment (designed
2026-11-14, implemented 2026-11-14; population units rescaled to
people 2026-11-17 — see the realistic economy above).** The
growth-rules stage: demand
does not gate building, it drives occupancy. Anything can always be
planned and built, but homes sit vacant and shops stay shuttered
until demand exists for them — vacant buildings pay no tax and full
upkeep, which is the whole anti-shop-farming guard: an unpatronized
shop is a pure upkeep drain.

- **Population is occupied households.** One occupied home = one
  household = one population; vacant homes and all commerce/civic
  count zero residents (commerce contributes jobs, civic coverage).
  Per-model household capacities (apartments housing three families)
  are a later content pass — the mechanism already stores counts.
- **Demand, in household units.** Residential demand = frontier
  appeal + jobs − population; commercial demand = population − jobs.
  Both clamp at zero; the bars' hints do the steering ("needs jobs",
  "needs homes"). The frontier appeal constant kickstarts the loop —
  people want to homestead this valley — and job overshoot is the
  feature: a new shop's jobs attract residents, so the loop
  oscillates instead of settling.
- **Arrivals are check-in events.** Households move in and shop
  positions fill only at check-ins, capped by a rate knob (seed: one
  per check-in) — growth costs check-ins, not money, and the town
  visibly grows one family a day.
- **Contentment is the town's appeal, never its tax collector**
  (redesigned 2026-11-18 after the run-3 playtest: the tax
  multiplier stacked a second income floor over unscaled upkeep —
  a City-scale town at the floor ran −25k/day, survivable only
  through the free-construction escape). Coverage per required
  service category (fire, police, health — content lists them) is
  capacity ÷ population, clamped at 1.0; contentment is the average
  across categories as a percentage. The whole migration pipeline —
  arrivals and the waiting list's refill — runs at the contentment
  rate, so an unhappy town stagnates rather than going broke.
  Taxes are the levy, unmultiplied: nothing may push income below
  the unemployment floor, so the homes-only guarantee holds
  unconditionally. Requirements phase in late (nothing demanded
  below the service threshold), so the early game stays exactly as
  pure as before. The HUD shows the contentment percentage only —
  no derived arrivals multiplier (removed 2026-11-18 under the
  facts-not-interpretations doctrine; a playtest reviewer read the
  multiplier as decoration and none could verify it against
  arrival noise).
- **The contentment floor is 30 percent** — it floors the growth
  dial, not income. Unhappy towns still grow (at 30% pace) and
  always earn their full levy, so even the most neglected town can
  afford the road tile that starts its recovery. Doctrine
  extended: contentment gates growth, never income; the fix for
  low contentment — service buildings — is always free labor.
- **Service buildings are civic, never commerce** (also
  2026-11-18): a `serviceCategory` classifies a building before
  its jobs ever reach the commerce levy — a staffed clinic must
  not dilute what the shops pay (a playtest reviewer measured a
  7% tax gap from exactly this). Civic jobs still count toward
  the town's employer appeal, the arrival pull, but they are not
  staffable positions and never enter the levy's denominators.
- **Storage.** A ninth `occupancy` column on the Tiles sheet holds
  filled units per completed structure: households for residential,
  staffed positions for commerce (a cafe staffs up job-by-job
  exactly as an apartment fills family-by-family). Short rows pad
  to vacant; over-capacity stored values grandfather rather than
  reject, so content edits never invalidate saves.
- **Framing keeps it chill.** The report speaks in invitations, not
  alarms ("a few folks mention the clinic is far", contentment
  deltas); a town at equilibrium asks nothing. A garden asks for
  water; that is gardening, not stress. The canary while playtesting
  is the requirement curve — slow it before ever considering removal.

Suggested slices: occupancy and demand first (the structural half),
then service coverage and contentment (the pressure half), then the
bars and retune. All quantities are per-settlement and compose with
the multi-city direction below.

**Stage 2.1 — the waiting-list demand system (decided and
implemented 2026-11-14).**
Reworks stage 2's demand half and its storage: the per-structure
occupancy column is **removed**. The town is the character and
citizens are its vitals — three stored aggregates replace the
distribution of occupancy across buildings, which the final design
(tax fractions, aggregate demand, percentage rates) never reads.

- **State (UserData):** `waiting_households` (the waiting list),
  `population` (households in town), `employed_population`
  (households holding jobs). Derived always: vacant residential
  capacity = Σ model households − population; unemployment =
  population − employed; job capacity = Σ model jobs caps
  employed. A population above capacity grandfathers (content
  edits shrink capacity; arrivals simply pause).
- **Residential demand is the waiting list.** Each check-in, while
  unemployment sits within `unemploymentTolerancePercent` (10%) of
  population (minimum 1 household — frontier towns tolerate some
  joblessness), the list refills by the migration budget.
  Population zero is within tolerance vacuously, so a fresh town's
  list grows from day one; this replaces the frontier-appeal
  constant. Vacant homes no longer freeze the list — arrivals
  drain it into them, so demand reads as a lower bar instead of a
  stuck one (relaxed 2026-11-14 after surveying SimCity 4, both
  Cities: Skylines, and Caesar/Pharaoh: nobody gates arrival on
  full employment or full housing; both are dampeners, not walls).
  Cap: `waitingHouseholdsCapPercent` (10%) of population, minimum
  1 — the bar's scale, and the bound on every burst.
- **Arrivals scale with the town, pulled by jobs:** up to 2% of
  population (minimum 1) households move in per check-in while the
  list is non-empty and vacant homes exist — regardless of
  unemployment — plus a job-pull bonus:
  `jobPullPercentPerCheckIn` (10%) of an arrival per surplus job,
  so commerce built ahead visibly accelerates migration (SimCity
  4's "jobs pull residents"). The three gradients oppose each
  other and the system self-balances: job surplus pulls migration,
  arrivals raise unemployment, unemployment past tolerance pauses
  the list, staffing catches up.
- **Employment demand** (renamed from commercial demand) **is the
  unemployed count**: population − employed. Bar scale:
  population. While citizens are unemployed and positions vacant,
  up to `employmentPercentPerCheckIn` (5%) of population (minimum
  1) positions staff per check-in. Employment adjusts faster than
  migration — jobs catch up to people, then people follow jobs.
- **Only employed people pay tax.** Home taxes scale by
  employed ÷ residential capacity; commerce taxes by employed ÷
  job capacity; both multiply by contentment, rounded once on the
  total. Every home pays the average rate — unemployment reads as
  a town condition, not a named household's. Unemployment's cost
  is lost tax and blocked migration; contentment stays purely
  service coverage.
- **Check-in sequence:** taxes, upkeep, stage advancement,
  arrivals, staffing, list growth — counter increments only, no
  per-structure writes.
- **Growth shape:** roughly 2% per check-in at full steam (a
  doubling in about five weeks), with the player's build rate as
  the real limiter. Early game: income is zero until the first
  job exists — the founding wave is one household, then a shop
  must open before the next family comes. Home, shop, home.
- **Deleted:** the ninth Tiles column, `PlacedStructure.occupancy`,
  the derived employment pairings, per-structure check-in writes.
  Flavor concession: arrival lines are aggregate ("a household
  moved in"); completions stay located.
- **Migration:** the live save carries population 51, employed 49,
  waiting 0, column stripped. Income lands near 265 (the two
  unemployed households' lost tax).
- **Content fields:** economy gains `migrationPercentPerCheckIn`
  (2), `employmentPercentPerCheckIn` (5),
  `waitingHouseholdsCapPercent` (10),
  `unemploymentTolerancePercent` (10),
  `jobPullPercentPerCheckIn` (10);
  `frontierAppealHouseholds` and `householdsPerCheckIn` retire.
  The walled-shop corner is unchanged (grant-button escape until
  demolition lands).

**Multiple cities (future concept, discussed 2026-11-14; storage
schema decided 2026-11-16).** Several
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

- **City partition of the state.** Decided (2026-11-16): per-city
  treasury, population, unlock set, and clock; one shared map with
  parcels exclusive across cities; a leading `city_id` column on
  every sheet in city-major blocks plus a Cities index document —
  not per-city sheets (the workbook tab limit caps those at ~40
  cities). The biggest schema change since the codec; the design
  lives in the implementation plan §7. Saves migrate by hand — the
  game carries no version or migration code.
- **Per-city check-ins.** Decided (2026-11-16, replacing the
  one-heartbeat sketch): each city carries its own clock and checks
  in independently — the player visits every city each day, which
  builds attachment. The town report stays per-city; a multi-city
  summary view can come later.
- **Purchase locality.** Comes free with the partition: the reducer
  operates on one city's state, so a road built in one city draws
  from that city's treasury by construction. No reducer changes.
- **Founding mechanics.** How a second city starts on disconnected
  land: the lore above (boat colonization, splinter households)
  supplies the story; mechanically a founding action is needed —
  claim a charted parcel and a founding stake, the same free-first
  rule the game's own opening now uses. Design slowly; this is
  genuinely new gameplay.
- **Authoring weight.** The map is hand-authored; several cities
  wants a bigger canvas and camera/UX for jumping between them.

Open even later: when a parcel borders two settlements, which one it
joins — player's choice, the bigger city, or adjacency not mattering
at all. Not a today problem.

**Open questions.** A more natural starting treasury than a flat 20;
whether
splinter settlers ask permission or build unilaterally; whether
settler construction renders as process (scaffolding) or arrives
between sessions; model-unlock thresholds and catalogue tiers under
the new pacing.

Before committing to additional mechanics, decide:

1. ~~How and when should builder capacity increase, if at all?~~ Retired
   (2026-11-16): builders removed from the game entirely — construction
   is limited only by coins, land, and staged check-in time.
2. ~~Are current parcel, building, and bridge prices sustainable over months and
   years of explicit check-ins?~~ Decided in direction: superseded by the
   check-in economy above — coin prices give way to taxes, upkeep, and
   check-in stages.
3. Are current model-unlock thresholds and catalogue tiers satisfying?
4. Which regional features, if any, are required for country-scale expansion?
5. Which long-term presentation features belong in the game, versus remaining
   visual ideas only?
6. Permanence policy: decided 2026-11-18 — demolition ships (the playtest
   and genre practice both demand it), but permanence lives in the money:
   no refunds, no profit, and land prices that fall with a shrinking
   population, paid for in permanently lost residents. Buildings and props
   can go now; infrastructure is deferred; parcels stay permanent.
   for dead-end cleanup in long-running settlements.
7. ~~Should asphalt roads be population-gated rather than a freely chosen style?~~
   Moot: dirt is gone and asphalt is the only style; population-gating road
   access remains a content option if ever wanted.

## 9. Product boundaries

- No transaction-based rewards, passive production, premium currency, market,
  staffing, resource chains, leaderboards, or mandatory streaks.
- No actual finance-data integration in this prototype.
- No demolition, relocation, cancellation, refunds, or automatic construction
  timers in the current slice. Demolition is planned future work; when it
  lands it must stay affordable at an empty treasury (free or labor-priced)
  — a coin-priced demolition would reintroduce the walled-town dead end it
  exists to remove. Until then, the coin grant in the clock panel is the
  escape hatch for that contrived corner.
- The map is intended to grow over the long term, but generated country-scale
  geography and long-run content balance are not yet implemented.
