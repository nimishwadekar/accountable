# Accountable City Simulation — Research & Concept

**Status:** historical research and brainstorming. The current game specification is the [Game Mechanics Plan](GAME_MECHANICS_PLAN.md); technical work is tracked in the [Parcel World Implementation Plan](PARCEL_WORLD_IMPLEMENTATION_PLAN.md). A separate prototype lives in the self-contained `citysim/` package and is not integrated with the main Accountable app.  
**Researched:** 2026-11-02

The [first implementation plan](IMPLEMENTATION_PLAN.md) records the original
fixed-lot V1 prototype and is retained as history. Its mechanics are superseded
by the current parcel-world specification where they differ. Earlier proposals
below—including transaction-derived growth, rewards for quiet days, residents,
and financial-milestone rewards—are brainstorming only unless adopted in the
game mechanics plan.

## Product direction

Create a calm, personal settlement that gradually becomes a visible record of the user's financial life. The desired feeling is **“watching a settlement grow”**: paths connect, buildings take shape, gardens mature, residents appear, and familiar places accumulate history.

The settlement should make financial care feel tangible without turning spending into a score. It is a **living financial scrapbook**, not a simulation in which the user must spend, optimize production, or keep residents happy to avoid losing progress.

## Fortune City research

Fortune City combines bookkeeping with a city-building game. Its central loop makes expense tracking produce visible buildings, then adds merge, collection, resident, and mission systems around the city.

### Documented mechanics

- **Records produce category-themed buildings.** Expense categories map to building families; the official help says custom category icon colour is reflected in the buildings it creates.
- **Daily construction is capped.** The help centre says a new city starts with five building slots per day; upgrading the Builder's Hub can increase the allowance. Additional records do not bypass the cap.
- **Unused slots can become parks.** If fewer records are logged than available daily slots, the remainder becomes public space. The help also describes explicitly recording “No Expenses” to count a quiet day toward tracking achievements.
- **Buildings evolve.** Buildings can be merged into higher levels, with multiple possible styles at some levels. The official catalogue shows category-specific progression, such as a food stand progressing to restaurants and a tent progressing to larger homes.
- **Citizens have interests and jobs.** Assigning a citizen to a matching building makes them happier and improves coin production. Dream jobs contribute to a separate happiness/prosperity system.
- **The city has an additional game economy.** Citizens produce coins, which need to be collected; City Hall governs aspects of prosperity and storage. Diamonds support things such as recruiting citizens, themes, and some building merges.
- **Return visits have rewards.** Daily login rewards, consecutive-use special buildings, missions, civic events, collections, and friend rankings give the city ongoing activity.
- **Analytics remain part of the finance app.** The product presents expense and income analysis alongside the game.

The exact limits and economy are product/version dependent. This note records what the official pages described at research time, not a specification to reproduce.

### What seems worth learning from it

1. **Make an abstract habit visible.** A logged record becomes a place the user can remember.
2. **Use category identity for flavour.** Different parts of life can give the world different character.
3. **Let small changes accumulate.** An evolving skyline is more rewarding than a single point counter.
4. **Give the world inhabitants and surprises.** Residents, events, and discoveries make a static collection feel inhabited.
5. **Make quiet days part of the world.** Parks are a strong metaphor: a day with no purchases can still be a positive day.

### What not to copy by default

Fortune City's citizens, coin production, timed collection, premium currency, building merges, streak rewards, and rankings form a deeper management game. They are not necessary for Accountable's desired settlement feeling. In particular, rewarding raw expense count risks making unnecessary purchases or transaction-splitting feel productive.

## Proposed concept: “Your life, taking shape”

Start with a riverside clearing, a small cottage, and a footbridge. Over time, the settlement gains a bakery, garden, library, lantern-lit lane, and civic landmark. Keep the original cottage and let it age gracefully rather than constantly replacing it.

The visual language could combine:

- Fortune City's connection between finance and visible place.
- The peaceful, ever-growing village landscape of [Dorfromantik](https://www.toukana.com/dorfromantik/).
- The low-pressure, creative town-building-toy sensibility of [Townscaper](https://townscaper.org/).

These are references for mood and interaction, not requests to copy their art or exact mechanics. Accountable should develop its own setting, visual assets, names, and progression.

## Three complementary kinds of growth

### 1. Financial-care growth

Reward **care and reflection**, not the amount or frequency of spending. Candidate actions:

- Review a day of transactions.
- Explicitly confirm a no-expense day.
- Complete a weekly or monthly review.
- Update a due manual valuation.
- Complete a personal financial goal.

A reviewed day should count once regardless of whether it contains two transactions or twenty. Repeated app opens, duplicate records, transfers, and transfer-fee rows should not multiply progress. A confirmed no-expense day should be able to contribute just as meaningfully as a spending day.

Accountable cannot currently distinguish a genuinely quiet day from a day with missing data. Any no-expense confirmation would be a new, explicit user action; missing history must never be silently treated as zero activity.

### 2. Financial-milestone landmarks

Connect Accountable's existing net-worth milestones to commemorative unlocks:

| Financial event | Possible place reward |
|---|---|
| Net-worth milestone | Clocktower, observatory, or riverside monument |
| Completed savings goal | Finish or decorate its associated project |
| Emergency reserve established | Granary, shelter, or reservoir |
| Debt-repayment milestone | Complete a bridge or restore a historic building |
| Tracking anniversary | Founders' garden or seasonal festival |

Emergency-reserve and debt-repayment rewards require financial concepts that Accountable does not currently model. Do not infer them from total net worth alone. A landmark can commemorate that a target was reached even if the user's current position later changes; its description should remain honest about current financial data.

Landmarks should celebrate progress without making absolute wealth the sole path to a beautiful settlement. Users at any starting point should be able to grow a lively village.

### 3. Life-shaped visual flavour

Categories and tags can influence **what appears**, rather than how fast the world grows. For example:

- Food: market stalls, bakery details, or a community kitchen.
- Transport: station, bicycle racks, or delivery carts.
- Learning: library, schoolhouse, or observatory.
- Entertainment: theatre or music pavilion.
- Travel tags: postcards, visiting merchants, or regional decorations.

These should be optional, configurable themes—not moral judgments about spending. A clinic should not require medical expenses, nor a library require book purchases. Financial records can inspire the world without locking ordinary community buildings behind particular purchases.

## Mechanics that support the settlement feeling

### Buildings grow in place

Prefer a visible sequence such as **survey stakes → foundation → timber frame → finished cottage → lived-in cottage** over primarily merging buildings away. Later details might add flower boxes, a chimney, a bicycle, a repaired roof, an extension, or warm evening windows.

### One community project at a time

Let the user choose a project—“Footbridge,” “Bakery,” or “Riverside Garden”—and have normal financial-care actions advance it. The user could choose its position and appearance or let the app place it. Keep choice lightweight; no resource inventory or production chain is needed.

### Residents are companions, not workers to optimize

A baker can open the shop shutters, a gardener can visit the river, neighbours can meet by the well, and a cat can sleep near the first cottage. Avoid hunger bars, unhappy-resident penalties, or job assignments required to maintain progress.

### Infrastructure makes a place

Paths connect buildings, dirt lanes gain lanterns, trees mature, a bridge connects another riverbank, and a clearing becomes a square. Connectivity and small environmental changes make the settlement feel coherent rather than like a checklist of sprites.

### Quiet time is valid

Flowers, wildlife, seasonal ambience, or residents enjoying existing spaces can make the settlement feel alive without new financial records. Never demolish or degrade buildings because the user missed a day or week. Distinguish explicitly between a confirmed quiet day, missing financial data, and simply being away.

### Let the user choose a pace and identity

Possible settlement styles include a garden village, harbour town, mountain settlement, or compact small city. More established should not have to mean taller, busier, or more urban.

## Ideas to consider later

- Preserve the oldest buildings as a named historic centre.
- Name streets, districts, the river, and individual buildings.
- Add a “then and now” timeline with snapshots from earlier months or years.
- Offer seasonal ambience independently of financial performance.
- Use monthly festivals to celebrate completed reviews, not perfect budgets.
- Add a travelling merchant for optional cosmetic choices, without countdown pressure or paid currency.
- Let users mark a new job, move, or trip as a life chapter and commemorate it with a district or garden.
- Allow postcard-style settlement exports that do not reveal financial amounts.
- Later, let past years become places in a personal regional atlas.

The strongest long-term combination is **historic centre + settlement chronicle + evolving buildings**: together they turn the city into a record of the user's life, rather than a collection checklist.

## Product guardrails

1. Spending more must not buy faster growth.
2. Do not require purchases or category diversity to unlock essential content.
3. Transfers, transfer-fee expenses, retries, corrections, and duplicate IDs must not multiply rewards.
4. Market losses or a revised valuation must not demolish earned buildings.
5. Do not use streak resets that erase long-term progress; welcome users back without penalty.
6. Keep correcting financial records easy. Never discourage corrections to protect a game reward.
7. Keep the core transaction-entry flow fast. Visiting the settlement is optional.
8. Explain progression clearly: “This bridge was unlocked by your monthly milestone,” not an opaque prosperity score.
9. Show financial status truthfully. A commemorative reward is historical acknowledgement, not a claim that the target is still met.
10. Make sound, animation, reduced-motion behavior, and settlement visibility respectful of user preference.

## Fit with Accountable today

Accountable already has useful inputs:

| Existing capability | Potential use |
|---|---|
| Transactions, categories, tags | Optional settlement flavour |
| Daily financial history | Historical summaries and honest time-range evaluation |
| Net-worth milestones | Commemorative architectural unlocks |
| Income allocations | Potential project-progress connection, if desired |
| Manual valuations | Periodic financial-care action |
| Startup transaction outbox | Show progress as pending until synchronization is confirmed |

Keep settlement progression separate from ledger calculations and source-of-truth financial tables. Layout, names, chosen projects, and unlock history should be persisted as a separate game/presentation dataset. Rebuilds, refreshes, retries, and outbox recovery must not award the same progress twice. Do not mutate transaction, account, valuation, or daily-history data to drive visual progression.

For an early implementation, a responsive 2D isometric scene in Flutter is a plausible direction, but artwork and convincing building transitions will likely take more effort than the reward calculations. Keep the finance app fully usable without this scene.

## Suggested first playable version

Keep the first scope deliberately small:

- One riverside map.
- A cottage, market, workshop, garden, civic building, and landmark.
- Three visible construction stages.
- A few ambient residents.
- One chosen community project at a time.
- Progress from reviewed days and existing financial milestones.
- Automatic layout initially, with optional repositioning later.
- A simple “then and now” view.

Do **not** start with coins, diamonds, staffing, trading, production chains, disasters, leaderboards, or mandatory streaks. First validate whether seeing a small settlement evolve makes financial review more enjoyable and sustainable.

## Open design questions

- Should the settlement be a new primary destination, an Overview card, or a user-selectable home screen?
- What exactly constitutes a reviewed day, and should confirmation be manual, derived from a completed review flow, or both?
- Should the map be curated automatically, user-positioned, or a mix?
- How many building stages and art styles are feasible for an initial release?
- Which existing milestone events are appropriate to commemorate without adding new financial claims?
- How should a user opt out, reset, export, or back up settlement data?
- Should presentation/game state live in a separate Sheets tab, local browser storage, or both?

## Research sources

- [SPARKFUL / Fortune City product page](https://sparkful.app/fortune-city) — product positioning, city themes, collection, tracking, and analysis.
- [Fortune City Help Center](https://fourdesire.helpshift.com/hc/en/5-fortune-city/) — official mechanics below.
- [Lesson 1: Expense Tracker Tips](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/652-lesson-1-expense-tracker-tips/) — income and explicit no-expense records.
- [Lesson 2: Buildings](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/653-lesson-2-buildings/) — daily building allowance, parks, attendance rewards, and merges.
- [Lesson 3: Gold Coins and Diamonds](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/654-lesson-3-gold-coins-and-diamonds/) — game currencies and collection.
- [Lesson 5: Citizens](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/656-lesson-5-citizens/) — citizen interests and jobs.
- [Lesson 6: Missions](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/657-lesson-6-missions/) — city discovery missions.
- [What kind of buildings will my categories create?](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/370-what-kind-of-buildings-will-my-categories-create/) — category colour and building mapping.
- [What is the Civic Square?](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/695-what-s-the-civic-square/) and [Civic Square events](https://fourdesire.helpshift.com/hc/en/5-fortune-city/faq/697-what-are-the-events-at-the-civic-square/) — community events.
- [Fortune City building catalogue](https://sparkful.app/universe/buildings) — category and level examples.
- [Dorfromantik](https://www.toukana.com/dorfromantik/) and [Townscaper](https://townscaper.org/) — mood/interaction references, not implementation requirements.

An older [player-written Fortune City strategy guide](https://waterbottled.wordpress.com/2017/11/10/optimally-playing-fortune-city/) discusses game-economy optimization. It is dated and unofficial; this concept note does not treat it as current product documentation.
