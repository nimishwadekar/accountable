# Economy feel report

Generated 2026-11-17 by `dart run tool/sim/simulate_batch.dart` — scripted personas playing fresh cities through the real reducer, quotes, and wallet. 150 days × 6 seeds × 4 personas = 24 runs.

**Content scale**: treasury start 100,000, parcel 15,000 + 150/pop, road 2,500/tile (+10/tile upkeep), bridge 50,000/tile. Services demanded at 300 pop. Migration 2%/check-in, employment 5%/check-in, job pull 10% of surplus jobs. Buildings construct free.

## Personas

- **The Planner** — Plays near-daily, surveys the whole map before founding, keeps a quarter of the population in open jobs, builds dense, keeps services covered, and knows parallel road jobs deliver in parallel.
- **The Casual** — Plays a bit more than half the days, takes the first decent founding spot, builds small cheap homes, reacts to problems rather than anticipating them, and lets contentment sag before fixing it.
- **The Saver** — Plays weekdays, hoards a cushion of more than double the parcel price before buying land, builds slowly, and keeps services tidy. The player who wants the treasury never to feel thin.
- **The Sprawler** — Plays most days, buys every parcel the moment the wallet allows, and fills them with the biggest homes available. The suburban spread, roads and all.

## Headline numbers

| persona | → hamlet (15) | → village (50) | → town (120) | → city (300) | → metropolis (800) | → regional capital (2000) | first profit | opening net (first 10) | late net (last 10) | min treasury | max treasury | dead days / first 30 | poor days | final pop | final coins |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| The Planner | 18 | 46 | 67 | 105 | never | never | 7 | 280 | 146,239.5 | 87,030 (day 6) | 7,057,466.5 | 0 | 0 | 546 | 7,057,466.5 |
| The Casual | 20 | 61 | never | never | never | never | 7 | 310 | 21,675.5 | 89,727 (day 9) | 877,503.5 | 0 | 0 | 71.5 | 877,503.5 |
| The Saver | 18 | 52 | 95 (2/6) | never | never | never | 7 | 185 | 33,338.5 | 89,427 (day 8) | 1,269,099.5 | 0 | 0 | 114.5 | 1,269,099.5 |
| The Sprawler | 18 | 50 | 82 | never | never | never | 7 | 109 | 64,969.5 | 844.5 (day 28) | 1,840,667 | 0 | 78.5 | 213 | 1,840,667 |

“Opening net” is the average credited net (taxes − upkeep) over a run’s first ten check-ins; negative values are the opening bleed before employment fills in. “Poor days” counts check-ins where the treasury could not cover the next parcel. “Dead days” are check-ins where nothing arrived, nothing completed, and no action succeeded — the logged-in-and-logged-off feeling.

## Where the money goes (median across seeds)

| persona | parcels owned | coins on parcels | coins on roads | refused actions |
|---|---|---|---|---|
| The Planner | 5 | 161,625 | 178,750 | 0 |
| The Casual | 3 | 41,100 | 125,000 | 0 |
| The Saver | 5 | 98,175 | 170,000 | 0 |
| The Sprawler | 49 | 1,184,625 | 191,250 | 4.5 |

## The Planner — the curve

Median across 6 seeds, by check-in number:

| check-in | coins | net | population | waiting | contentment |
|---|---|---|---|---|---|
| 1 | 92,500 | 0 | 0 | 1 | 100 |
| 3 | 92,470 | -30 | 0 | 1 | 100 |
| 5 | 92,077 | -363 | 2 | 1 | 100 |
| 10 | 90,300 | 1,050 | 7 | 1 | 100 |
| 20 | 117,677 | 4,457 | 17 | 1 | 100 |
| 30 | 160,110 | 7,863 | 28 | 2 | 100 |
| 50 | 381,138 | 15,653 | 61 | 5 | 100 |
| 75 | 1,124,138 | 49,600 | 162 | 15.5 | 100 |
| 100 | 2,728,614 | 85,550 | 279 | 27 | 100 |
| 125 | 4,693,476 | 117,168.5 | 424.5 | 42 | 99 |

## The Casual — the curve

Median across 6 seeds, by check-in number:

| check-in | coins | net | population | waiting | contentment |
|---|---|---|---|---|---|
| 1 | 92,500 | 0 | 0 | 1 | 100 |
| 3 | 89,980 | -20 | 0 | 1 | 100 |
| 5 | 89,800 | -140 | 2 | 1 | 100 |
| 10 | 93,100 | 1,393 | 7 | 1 | 100 |
| 20 | 112,747 | 3,687 | 15 | 1 | 100 |
| 30 | 133,970 | 7,333 | 24 | 2 | 100 |
| 50 | 303,480 | 12,510 | 40 | 3 | 100 |
| 75 | 651,340 | 19,600 | 62 | 5 | 100 |

## The Saver — the curve

Median across 6 seeds, by check-in number:

| check-in | coins | net | population | waiting | contentment |
|---|---|---|---|---|---|
| 1 | 92,500 | 0 | 0 | 1 | 100 |
| 3 | 89,980 | -20 | 0 | 1 | 100 |
| 5 | 89,700 | -240 | 2 | 1 | 100 |
| 10 | 91,850 | 843 | 7 | 1 | 100 |
| 20 | 108,390 | 4,210 | 17 | 1 | 100 |
| 30 | 126,732 | 7,732 | 27 | 2 | 100 |
| 50 | 301,145 | 14,958 | 48 | 4 | 100 |
| 75 | 716,096.5 | 25,920 | 83 | 8 | 100 |
| 100 | 1,484,606 | 41,610 | 129 | 12 | 100 |

## The Sprawler — the curve

Median across 6 seeds, by check-in number:

| check-in | coins | net | population | waiting | contentment |
|---|---|---|---|---|---|
| 1 | 77,500 | 0 | 0 | 1 | 100 |
| 3 | 42,480 | -20 | 0 | 1 | 100 |
| 5 | 11,640 | -350 | 2 | 1 | 100 |
| 10 | 13,140 | 733 | 7 | 1 | 100 |
| 20 | 15,405 | 4,025 | 17 | 1 | 100 |
| 30 | 14,573 | 7,619 | 27 | 2 | 100 |
| 50 | 4,009 | 15,682 | 51 | 2 | 100 |
| 75 | 13,229.5 | 31,465 | 103 | 10 | 100 |
| 100 | 721,891 | 52,785 | 161 | 16 | 100 |
| 125 | 2,236,670 | 74,270 | 231 | 23 | 100 |

## A diary

The median The Planner run (seed 4), day by day for the first 45 days — the onboarding stretch where feel crystallizes:

| day | in? | net | coins | pop | waiting | milestone | what the player did |
|---|---|---|---|---|---|---|---|
| 1 | ✓ | 0 | 92,500 | 0 | 1 | homestead | parcel (2,2), free; 1 tiles; 1 tiles; 1 tiles |
| 2 | ✓ | 0 | 92,500 | 0 | 1 | homestead | Café at (20,18); Small House at (20,20); Small House at (19,19); Small House at (21,21) |
| 3 | ✓ | -30 | 92,470 | 0 | 1 | homestead | Small House at (22,20) |
| 4 | ✓ | -30 | 92,440 | 1 | 1 | homestead |  |
| 5 | ✓ | -363 | 92,077 | 2 | 1 | homestead |  |
| 6 | ✓ | -47 | 87,030 | 3 | 1 | homestead | 1 tiles; 1 tiles; Small House at (22,19) · cleared 1 nature props |
| 7 | ✓ | 370 | 87,400 | 4 | 1 | homestead | Café at (19,20) · cleared 1 nature props |
| 8 | ✓ | 767 | 88,167 | 5 | 1 | homestead |  |
| 9 | ✓ | 1,083 | 89,250 | 6 | 1 | homestead | Small House at (18,19) |
| 10 | ✓ | 1,050 | 90,300 | 7 | 1 | homestead |  |
| 11 | ✓ | 1,467 | 91,767 | 8 | 1 | homestead |  |
| 12 | ✓ | 1,783 | 93,550 | 9 | 1 | homestead | Small House at (18,22) · cleared 1 nature props |
| 13 | ✓ | 2,200 | 95,750 | 10 | 1 | homestead |  |
| 14 | ✓ | 2,617 | 98,367 | 11 | 1 | homestead | Café at (17,20) · cleared 1 nature props |
| 15 | ✓ | 2,933 | 98,800 | 12 | 1 | homestead | 1 tiles |
| 16 | ✓ | 3,350 | 102,150 | 13 | 1 | homestead | Small House at (20,21) · cleared 1 nature props |
| 17 | ✓ | 3,307 | 105,457 | 14 | 1 | homestead |  |
| 18 | ✓ | 3,723 | 109,180 | 15 | 1 | hamlet | Small House at (19,22) |
| 19 | ✓ | 4,040 | 113,220 | 16 | 1 | hamlet |  |
| 20 | ✓ | 4,457 | 117,677 | 17 | 1 | hamlet |  |
| 21 | ✓ | 4,773 | 122,450 | 18 | 1 | hamlet | Small House at (21,22) · cleared 1 nature props |
| 22 | ✓ | 5,190 | 127,640 | 19 | 1 | hamlet | Fruit Market at (20,23) |
| 23 | ✓ | 5,607 | 133,247 | 20 | 1 | hamlet |  |
| 24 | away | | | | | | |
| 25 | ✓ | 5,923 | 136,670 | 21 | 2 | hamlet | 1 tiles |
| 26 | away | | | | | | |
| 27 | ✓ | 5,990 | 124,360 | 22 | 2 | hamlet | Small House at (19,18) · cleared 1 nature props; parcel (1,2) |
| 28 | ✓ | 6,397 | 130,757 | 23 | 2 | hamlet |  |
| 29 | ✓ | 6,813 | 137,570 | 24 | 2 | hamlet | Small House at (18,17) |
| 30 | ✓ | 7,130 | 144,700 | 25 | 2 | hamlet | Fruit Market at (19,16) |
| 31 | ✓ | 7,547 | 152,247 | 26 | 2 | hamlet |  |
| 32 | ✓ | 7,863 | 160,110 | 28 | 2 | hamlet | Small House at (20,17) |
| 33 | ✓ | 7,930 | 168,040 | 29 | 2 | hamlet |  |
| 34 | ✓ | 8,347 | 173,887 | 30 | 2 | hamlet | 1 tiles |
| 35 | ✓ | 8,663 | 182,550 | 31 | 2 | hamlet | Fruit Market at (16,20); Small House at (15,19) |
| 36 | ✓ | 9,070 | 191,620 | 32 | 2 | hamlet |  |
| 37 | ✓ | 9,487 | 201,107 | 34 | 2 | hamlet | Small House at (17,19) |
| 38 | away | | | | | | |
| 39 | ✓ | 9,453 | 210,560 | 36 | 2 | hamlet | Small House at (16,18) |
| 40 | ✓ | 9,870 | 217,930 | 37 | 2 | hamlet | 1 tiles |
| 41 | ✓ | 10,187 | 228,117 | 38 | 2 | hamlet | Fruit Market at (15,20) |
| 42 | ✓ | 10,493 | 238,610 | 39 | 2 | hamlet | Small House at (16,21) |
| 43 | ✓ | 10,910 | 249,520 | 41 | 2 | hamlet |  |
| 44 | ✓ | 11,393 | 260,913 | 43 | 2 | hamlet | Fruit Market at (14,21); Small House at (15,22) · cleared 1 nature props |
| 45 | away | | | | | | |

## Method and simplifications

- Every action runs through the production reducer (`purchaseParcel`, `planRoadStretch`, `startStructureConstruction`, `pickUpProp`, `checkInWorldForToday`); no rule or price is re-implemented, so results cannot drift from the shipped game.
- Personas are readable heuristics, not optimal players: they cover playstyles, and their mistakes (reactive services, unsplit road strokes) are deliberate.
- Simplified away for this pass: bridges, decorations, connective roads between parcels (frontage roads alone satisfy road access), prop re-placement, and demolition — none exists in the game yet or none moves the economy.
- Founding and expansion pick the land-richest adjacent parcel; cadence, budgets, and model choices vary by persona and seed.
- Each road job delivers one tile per check-in; parallel jobs deliver in parallel. The Planner exploits this (single-tile strokes), the others do not — the pacing difference between its curve and theirs is that exploit’s measured size.

