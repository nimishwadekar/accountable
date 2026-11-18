# Sub-agent playtest plan — LLM game reviewers

Spawning sub-agents as game reviewers, each handed a persona in words,
playing a full simulated year through the real game rules, keeping
richer notes than the scripted sims, and ending in a cross-reviewer
synthesis. This document is the build-and-run plan; nothing spawns
until it is approved.

## 1. Why — what this adds over the scripted sims

The harness personas (`tool/sim/`) measure what the economy *does*:
curves, runways, milestone days. They cannot tell us what the game
*feels like to decide in*. Reviewers add four things the scripts
structurally cannot:

1. **The decision landscape** — where choices were interesting vs.
   automatic, where the player stared at a wall of affordable options
   and felt nothing.
2. **Friction and confusion** — the moments the rules surprised them,
   the information they wanted and couldn't get, the actions they
   attempted and were refused.
3. **Desires with no outlet** — "I wish I could…" is a backlog
   generator no metric produces.
4. **A behavioral control** — each reviewer mirrors a scripted
   archetype on identical content. Where their curves diverge from
   the archetype's prediction, a human factor is showing through.

Honest framing, agreed up front: an LLM reviewer is a plausible
narrator around real numbers, not a human with feelings. The numbers
come from the game itself (auto-logged); the narration is disciplined
by a citation rule — every subjective claim must cite a day and a
number. Convergent findings across reviewers are the signal; a single
reviewer's mood is an anecdote.

## 2. What they play — the ground rules

- **The real rules, headless.** All state transitions go through the
  production reducer (`checkInWorldForToday`, `purchaseParcel`,
  `planRoadStretch`, `startStructureConstruction`, `pickUpProp`), so a
  reviewer's year cannot drift from the shipped game.
- **Content snapshot: the "road to a million" variant** — blend-40
  economy (taxes ×0.4, parcels 30,000 + 400/pop), the extended
  milestone ladder (6k/20k/60k/200k/600k/1M), the test-only density
  housing and scaled civic buildings, and the enlarged 18×18 island
  map with lakes and scattered nature (water never severs the
  island, so the pilot needs no bridge command). All built in memory
  from the shipped files by `tool/sim/content_variants.dart` —
  `ladderABundle`. The base content is **frozen at playtest start**
  into `docs/sim/playtests/content-snapshot/` and the CLI reads only
  that copy, so editor sessions mid-playtest cannot drift the
  reviewers' game.
- **One year**: day 1 through day 365, fresh city, zero parcels, the
  free founding parcel first. Single city — multi-city is out of
  scope for this pass.
- **Pilot first**: Maya (planner) and Leo (casual) run the full
  pipeline before Sam and Vera join.
- **The information diet is the experiment.** Reviewers see only what
  the play CLI prints — the same facts the game's UI shows a player
  (treasury, population, waiting list, contentment, coverage,
  milestone, projects, town report, quotes). They must not read
  `lib/`, `assets/content/`, or the sim tools. Wanting information the
  CLI doesn't show is a *finding* — they note it, they don't dig.

## 3. Prerequisite — the play CLI (`tool/sim/play_cli.dart`)

A command-oriented driver the sub-agents call. Each invocation loads
the save, runs a batch of commands, saves, prints results — one shell
call per play session. The CLI ships as an AOT-compiled binary
(~50 ms per invocation; `dart run` costs ~800 ms of VM boot and JIT
per call, which adds up over hundreds of sessions). Rebuild it after
any code change:

```
dart compile exe tool/sim/play_cli.dart -o build/play_cli
```

A session is then:

```
./build/play_cli --state docs/sim/playtests/maya/state.json \
  --log docs/sim/playtests/maya/log.jsonl \
  --notes docs/sim/playtests/maya/notes.md \
  "day" "status" "map" "build apartments 12 9" "note \"...\""
```

Commands (all refusals surface the game's real `WorldRuleViolation`
messages verbatim — the refusal *is* the friction we want captured):

| command | effect |
|---|---|
| `help` | player-facing rules summary (the tutorial: check-ins, taxes, free construction, road frontage, parcel pricing) |
| `status` | the HUD: date, check-in count, treasury, population, employed, waiting, contentment, coverage, milestone, parcels, free land, projects in flight, can-check-in |
| `report` | the last town report in full (taxes, upkeep, net, arrivals, completions) |
| `day` | advance one calendar day and take the check-in if arrived |
| `skip <n>` | days the player didn't open the game |
| `map [col row]` | ASCII cell window centered on the town (~40×20): roads `#`, homes `h`, commerce `c`, civic `s`, props `,`, free `.`, water `~`, owned/unowned shading |
| `catalogue` | unlocked models with player-facing stats (population/jobs/service/tax/upkeep/stages) |
| `found <parcelX> <parcelY>` | claim the founding parcel |
| `parcel <parcelX> <parcelY>` | quote land (price, cells, treasury after); append `buy` to purchase |
| `road <c1,r1> <c2,r2>` | quote one road stretch between cells (price, treasury after; blocked tiles named); append `buy` to purchase |
| `build <modelId> <col> <row>` | place a building (quoted; road-frontage and overlap refusals verbatim) |
| `place <modelId> <col> <row> <sx> <sy>` | place a decoration on the subtile lattice |
| `demolish <col> <row> [<sx> <sy>]` | quote removing the building or prop at a cell (net, capacity, who loses homes); append `confirm` to execute |
| `inspect <col> <row>` | what stands here, and the placement quote if relevant |
| `note "<text>"` | append a timestamped session note to the notes file |

Bookkeeping the CLI owns:

- **State** persists between invocations via the production codec
  (`worldToSheetTables` / `sheetTablesToWorld` under a thin JSON
  envelope with the city name) — the same format as saves, so a
  reviewer's city could even be loaded into the real game later.
- **The day log** auto-appends one `DayRecord` JSON line per day
  (same shape as `simulate_batch`'s logs: coins, taxes, upkeep, net,
  population, waiting, capacities, parcels, roads, structures,
  milestone, actions with outcomes and refusal reasons, dead flag,
  next parcel price). Reviewers never hand-count statistics. Mutating
  commands lazily open the game (a fresh world's first action rolls
  day 1 with its check-in, like opening the app), and a day played
  across several invocations writes several records — the analysis
  merges by day, concatenating actions.
- **Session notes** append to the reviewer's markdown file with the
  day and a compact context line, so notes survive context loss.

Definition of done for the CLI: a smoke run of a 10-day session
(founding, roads, a café, homes, three check-ins, a note) that
round-trips state across separate invocations, plus analyzer-clean.

## 4. The four reviewers

Personas are written as people, not parameter sets. Their habits
mirror the scripted archetypes so the curves are comparable, but
their words are their own.

1. **Maya — the planner.** Plays near-daily, misses maybe one day in
   twenty. Reads every number the game shows her, plans districts
   before building, keeps services ahead of demand, and treats the
   town report as a scorecard. The type who reads patch notes. She
   will experiment with mechanics (she may *discover* the parallel
   road-job trick on her own — she is not told).
2. **Leo — the casual.** Plays three, four evenings a week. Builds
   small, pretty things — trees, lamp posts, a café he likes the look
   of — and reacts to problems only when they're on screen. Gets
   bored easily; his notes are where tedium and dead days surface.
3. **Sam — the saver.** Weekday player. Keeps a treasury cushion he
   can see, expands slowly, hates being refused for coins, and keeps
   services tidy before they're demanded.
4. **Vera — the sprawler.** Plays most days and buys every parcel the
   moment she can afford it, filling them with the biggest homes
   available. Loves the map itself; wanders to look at terrain. Her
   notes are where land hunger, cash-poor cycles, and map-boundary
   feelings surface.

None of them are told the internals: no migration formula, no content
values beyond what `catalogue`/quotes show, no economy file.

## 5. Protocol — chunks, handoffs, and how to spawn them

A year is too much context for one agent, so each reviewer's year
runs as **six chunks of ~61 in-game days**, each chunk a fresh
sub-agent that inherits a save and a notes file. All four reviewers
play in parallel as background sub-agents; chunks chain as each
finishes.

Per chunk:

- **Agent**: `subagent` tool, `general` agent, background, one per
  reviewer. Label: `playtest <name> days <from>–<to>`.
- **Packet**: persona brief, the command cheat sheet, the state/log/
  notes paths, the day range, and a short handoff summary written by
  the previous chunk (where the town stands, standing intentions).
- **Session rhythm**: advance a day (or `skip` per their habits),
  read `status`/`report`, act, and always end the session with one
  `note`. The note format is structured for later clustering:
  `note "day N: did X · felt Y · friction: Z · wish: W · confusing: V"`
  — reviewers don't have to use every tag, but the tags are greppable.
- **Stop condition**: the save reaches the chunk's end day. The agent
  writes the handoff summary and exits.

**Chunk prompt template** (verbatim, placeholders in braces):

> You are {NAME}, a game reviewer playtesting a check-in-driven
> parcel city builder. You are not an engineer on this project. You
> never read the game's source code, content files, or test code —
> your entire experience of the game is the play CLI below. If you
> want information it doesn't show, that's a finding: note it, don't
> dig for it.
>
> WHO YOU ARE: {PERSONA_BRIEF}
>
> THE GAME, as a player is taught it: open the game once a day and
> check in — taxes arrive, upkeep is paid, and every construction
> advances one stage. Buildings construct for free; land, roads, and
> bridges cost coins, and land prices rise with population. Buildings
> need a completed road along one full side of their footprint.
> Nothing progresses on days you don't open the game.
>
> HOW TO PLAY — every session is one shell call (run from
> /Users/nwadekar/Projects/accountable/citysim):
> `./build/play_cli --state {STATE} --log {LOG} --notes {NOTES} "day" "status" ...`
> Commands run in order, the save updates, results print. Start any
> session you're unsure about with `help`. Plan bigger sessions as
> one call with several commands.
>
> YOUR CHUNK: in-game days {FROM} through {TO} (the save is at day
> {DAY}). Play as {NAME} would — your cadence, your priorities, your
> moods. Every session ends with one note in the greppable format
> (did · felt · friction: · wish: · confusing:). Cite the day and a
> number for every feeling you claim. If you would close the app in
> frustration, say so and why. Do not edit the state, log, or notes
> files by hand — the CLI owns them. Stop when the save reaches day
> {TO}; then write a short handoff summary (town standing, population,
> treasury, your current intentions) as your final note prefixed
> `handoff:`.
>
> WHERE YOU LEFT OFF: {HANDOFF_SUMMARY}

**Final chunk** (day 305–365) additionally instructs the reviewer to
write their verdict: `docs/sim/playtests/{name}/review.md`, first
person, covering pacing, the money feel (rich/poor moments with day
+ number citations), the friction list, the wish list, and a plain
"would I keep playing past day 365, and why/why not."

## 6. The analysis pass (what I do with the output)

1. **Control run**: `simulate_batch.dart` on the identical content
   snapshot — the four scripted archetype curves.
2. **Reviewer metrics**: the four JSONL logs through the same metric
   definitions as the batch tool (milestone check-ins, first profit,
   opening net, late net, min/max treasury, poor days, dead days,
   parcel runway, spend split).
3. **Reviewer vs. archetype table**: where each reviewer's curve
   matches and diverges from their scripted twin. Divergences get
   read back against the notes ("she stopped buying parcels at day
   210 because…").
4. **Note clustering**: grep the notes by tag (`friction:` `wish:`
   `confusing:`), cluster by topic, count per reviewer. Findings are
   classed **convergent** (two or more reviewers hit it — the real
   signal), **persona-specific**, or **unique insight**.
5. **Severity**: blocker (stopped progress), friction (slowed or
   annoyed), polish. Each finding is mapped to a dial it would move
   (`economy.json`, `catalogue.json`, `progression.json`) or flagged
   as a tooling/UX change for the real app.
6. **Deliverable**: a synthesis in chat plus
   `docs/sim/playtest_synthesis_<date>.md` — the comparison table,
   the clustered findings with reviewer quotes-by-number, and a
   ranked change list.

## 7. Costs, limits, and honest caveats

- **Volume**: 4 reviewers × 6 chunks = 24 sub-agent runs, each on the
  order of 60–150 tool calls (one call per session). Wall-clock is a
  few hours with the four reviewers in parallel. A cheaper pilot
  (two reviewers: Maya + Leo) validates the pipeline first.
- **LLM players are more patient than humans** and cannot experience
  art, animation, or the tactile map — this playtest covers
  mechanics, pacing, and economy feel only.
- **Their feelings are narratives around numbers.** The numbers are
  real (auto-logged); the citation rule keeps the narratives honest.
- **Persona drift** is the main failure mode — mitigated by
  re-anchoring the brief every chunk and by the notes file carrying
  memory forward.
- **One run per persona is one player's anecdote.** Conclusions that
  matter get re-measured with the scripted sims (which run in
  seconds) before any content change.

## 8. Execution checklist

1. Build `tool/sim/play_cli.dart` (state round-trip, DayRecord
   logging, notes, ASCII map, quotes-with-refusals). Smoke test.
2. Freeze the content snapshot decision (shipped economy vs.
   blend-40).
3. Write the four persona briefs from §4 into the packet.
4. Run the scripted control (`simulate_batch.dart`, same content).
5. Spawn chunk 1 for all reviewers in parallel (background).
6. Chain chunks 2–6 as each completes; spot-check notes for drift.
7. Final reviews in chunk 6.
8. Analysis pass per §6; synthesis delivered.
