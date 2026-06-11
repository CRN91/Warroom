# Warroom — Architecture Notes (post-refactor)

## Layout

```
Game.gd (composition root — wiring only, no gameplay logic)
├── Grid            (HexGrid)         tilemap, piece lookup, A*, highlights
├── Board           (Board)           units/cities/trains, spawning, buying, death
├── TurnManager     (TurnManager)     day counter + end-of-turn pipeline
├── InputController (InputController) selection, orders, rail keys, path preview
├── WeatherManager  (WeatherManager)  calendar, seasons, weather lifecycle
├── ModifierManager (ModifierManager) every active buff/debuff, queried by stat
├── TerrainManager  (TerrainManager)  mountains, rivers, bridges, tunnels
├── RailNetwork     (RailNetwork)     rail routes + trains
├── FowManager      (FOWManager)      fog of war
├── EnemyAI         (EnemyAI)         opposing commander
├── CardManager     (CardManager)     deck, draws, triggers, scheduling
│   ├── Deck / CardLibrary / CardResolver / CardScripts
└── UI              (UIManager)       top bar, panels, toasts, cards, game over

Autoload: Events (scripts/event_bus.gd) — global signal bus
```

## The two plumbing patterns

**GameServices (`scripts/services.gd`)** — built once in `Game._ready()`, holds a
typed reference to every system. Systems get it via `setup(s)` and pull what
they need (`s.board`, `s.modifiers`, ...). Card scripts get full access through
it — that's the escape hatch for bespoke card effects.

**Events (autoload)** — facts get announced, listeners react. e.g. `City.capture()`
emits `city_captured`; CardManager turns that into story triggers, with no
reference between them. `Events.notify("...")` shows a toast.
Signals: `day_advanced, unit_died, city_captured, rail_established, rail_broken,
rail_repaired, weather_changed, decision_pending, game_over, toast`.

Units/components don't use either — Board injects exactly what they need
(`grid`, `modifiers`, `terrain`) via `unit.inject(...)` at registration.
**All spawning must go through Board** (`add_unit`, `spawn_unit`,
`spawn_unit_near_city`) so injection and FOW stay correct.

## Turn pipeline (TurnManager.advance_day)

unfreeze → modifiers.tick → weather expiry → scheduled card effects → enemy AI
→ movement (player manual, player auto, enemy) → combat (simultaneous)
→ resupply → card draw/display → city income/siege → starvation deaths → cull
→ unfreeze → FOW → intent arrows → UI refresh.

## Line of control (the map table)

`ControlMap` (scene node, z under terrain) paints every hex red/green/grey:

- Initial paint = the map generator's territory split. Each week, every COMBAT
  unit projects control over its hex + 6 neighbours (engineers/trains project
  nothing); cities project for their owner. Both sides projecting → grey
  no-man's-land (no debuff — its danger is the guns covering it). Unprojected
  hexes keep their last owner.
- **Pockets**: a region of paint containing none of its side's units/cities is
  absorbed by the other side. **Isolation**: paint with no path to its side's
  capital flags everything in it `cut_off` (red icon + panel warning).
- **Sieges**: a cut-off, empty city surrenders to the surrounding side after
  3 weeks; until then it raids haulers within 2 hexes.
- Haulers ending the week on enemy paint lose ~20 to partisans (battle log).
- Top bar shows territory %; tints render map-wide (staff estimate, not FOW).

## Artillery doctrine

Artillery must SET UP to fire: D key (or AI logic) spends the action; moving
packs it up (`on_moved`). Deployed guns show an emplacement ring, telegraph as
normal, and provide withdrawal fire; mobile guns are blind. Infantry pushes
the line (damage 20); deployed artillery breaks attacks (damage 30, range 3).

## Rotation (12 weeks on, 6 off)

Combat units carry a deployment clock (4th panel meter). Past 12 weeks
fatigue ramps: attack ×0.9 / ×0.8 / ×0.7 at 13/17/21 weeks (modifiers, scope
unit). The **Garrison** button rests a division inside an adjacent friendly
city for 6 weeks — off the board, clock and fatigue reset, refilled from the
city's actual stores on redeploy. **If the city falls while they rest, they
are lost.** Max fatigue fires the deserters card (`unit_exhausted` trigger).
The enemy fatigues too but never rests — long wars grind both sides down.

## Run variance (FTL-style)

- **Doctrine pick**: the first card of every run offers ONE of three corps —
  Field Army (2 inf/arty/eng), Iron Rain (2 arty/inf/eng), Railway Corps
  (inf/arty/2 eng + train + 5 rails). `CardManager.doctrine_offer`, shown by
  `TurnManager.prepare_first_turn`. Enemy always fields a standard corps.
- **Shops are single take-it-or-leave-it offers** (one unit type per card,
  random which arrives, no-repeat, pity ≤10 weeks): risk it now or wait.
- `reveal_area` effect type = photography flights: lifts fog around a point
  until next turn (`decision_recon_flight` card pays 50 to photograph the
  enemy capital). Use in cards: { "type": "reveal_area", "near": ..., "radius": N }.

## Enemy AI behaviours

Beyond charge-at-nearest: engineers run standing capital→neediest-town supply
shuttles (same automation as the player's Set Route); divisions at fatigue
stage 2+ rotate home and garrison (same rules, same risk); artillery packs up
and falls back when enemies reach the muzzle. Posture-level AI (attack/hold/
raid) is the next planned layer.

## Endgame: two victories

- **Take the enemy capital** (lose yours = defeat), or
- **Destroy the coalition expedition**: warnings at weeks 16/30/44, landfall
  week 52 (`coalition_landfall` script) — orange team-3 units (allied with the
  enemy via `Sides`; orange = red sprites tinted) led by the Land Dreadnought
  'Sovereign' (400 supplies, attack 50) with escorts over 3 waves. Wipe the
  expedition and the enemy sues for peace.
Game-over screens carry a headline + run stats. Teams resolve through
`Sides.side_of/hostile` everywhere (targeting, movement, sieges, withdrawal).

## Map generation

- The river is the meandering border between two territories grown outward
  from each capital by random flood fill (`TerrainManager._grow_territories`) —
  a different course every run, with exactly one pre-built bridge whose
  endpoint hexes are protected from mountain placement.
- 1–3 neutral towns spawn at random sites each run (≥3 hexes from capitals and
  each other — `Game._pick_town_hexes`). Mountains avoid city surroundings.
- **Capitals** (win/loss condition): 1000 stores, 100/week income, drawn larger.
  **Towns**: 400 stores, 40/week, drawn smaller — quick to capture, worth
  holding for supply position and the stories they trigger (see below).
- Captured cities change hands with half their stores.

## Economy (FTL-style scarcity)

There is **no open shop and nothing is free**. Units and stock come only from
paid shop cards (guaranteed within 10 weeks, then 4–7 apart, never the same
shop twice in a row) and story decisions like conscription. Capitals earn just
50/week — holding towns (40/week each) IS the economy, so captures directly
fund the war. The enemy AI spawns units through `Board.spawn_unit_near_city`
directly. (Town militias were tried and removed; if towns need defenders
later, frame them as partisans.)

## Units are people (service records)

- Every unit gets a generated company name ("3rd Veldt Rifles") and can be
  renamed from the stats panel, FTL-style. Player cities can be renamed too.
- Three visible stats: **damage**, **drain/week**, **max supplies** — shown
  with veterancy progress meters in the stats panel:
  - survive 14 weeks → +5 max supplies; 28 weeks → +2 more
  - 3 kills → +3 damage; 5 kills → +2 more (infantry: 35 → 38 → 40)
  - 10 weeks without resupply → drain −1 (infantry: 3 → 2)
- Milestones toast when earned; kills/weeks tracked per unit (`Unit` service
  record section). Cards can target one specific unit with the modifier scope
  `name:<unit name>` (plus existing `unit:<id>` and `tag:` scopes).
- Infantry rebalanced: damage 35 (was 75), drain 3 (was 1).

## Telegraphed attacks (honest)

At end of turn every combatant (both sides) locks the target it will shoot
next turn (`TurnManager._telegraph_attacks` → `Attack.acquire_target`), and the
red intent arrows render it. The lock is binding: `Attack.get_target` no longer
scans opportunistically, so **a unit can only be hit by an attack that was
telegraphed** (or manually ordered) — no move-in-and-shoot surprise deaths.
Firing also flashes the attacker visible through fog until next turn
(`FOWManager.flash`), so hidden artillery reveals itself when it shells you.

## Combat feedback

Kill and withdrawal events go to `Events.battle_event`, collect in
`CardManager.battle_log`, and surface as a FIELD REPORT intel card (the intel
filler slot, or any card with `"dynamic_text": "war_report"`) — combat news
arrives through the card game, not toast spam. The stats panel is FTL-style:
a supply bar plus thin colored veterancy meters (red = kills→damage,
blue = weeks→capacity, yellow = unsupplied streak→drain), with exact numbers
in hover tooltips. The frozen-unit dim was removed.

## Cards

- Daily cycle: intel → event → decision (turn 1 = intel).
- Every 6th week the decision slot is a **free requisition offer**
  (`CardManager.requisition_offer`); paid shops stay on their own pity timer.
- Card sets: `ambient` + `story_seeds` start in the deck; `consequences`,
  `city_stories`, `bear_story`, `coalition`, story chains and `supply_offers`
  enter only via injection/scheduling/triggers.
- **Capture stories**: taking a neutral town triggers a loyalty decision
  (pillage vs protect, with consequences); the 2nd town triggers the mayor's
  bargain; taking an enemy city triggers rebels enlisting.
- **Coalition doom clock**: day-triggered intel at weeks 14/28/40 warns of a
  growing coalition; at week 48 their vanguard arrives (enemy reinforcements +
  permanent buff). Keeps long runs under pressure — race to the enemy capital.
- **The bear** is in the deck. Leave it be.
- Intel cards with `"dynamic_text": "recon_report" | "economy_report"` get text
  generated from the real board at draw time (`scripts/intel_generator.gd`).
  Intel **filler** also produces a live recon report.
- Intel/event cards have no buttons (click to dismiss). Decision cards disable
  End Turn until answered (`Events.decision_pending`).
- deck.json schema unchanged — the card editor still works. New optional key:
  `dynamic_text`.

## Controls

| Input | Action |
|---|---|
| Left click | select / order. Clicking a destination **replaces** the unit's goal |
| Shift + click | append manual waypoints for an exact route |
| Click selected unit | cancel its orders (click again to deselect) |
| Right click / Esc | deselect (Esc also cancels a rail plan) |
| M / F | clear movement / clear attack target |
| D | artillery: set up (costs the action) / pack up (free) |
| R / T | plan rail on hovered hex (needs Engineers nearby) / commit or extend line |
| Esc | also cancels a Set Route pick in progress |
| C | cycle territory overlay: tints + line / line only / hidden |
| H | field manual (how to play + controls) — also via the ? Help button |
| F3 | debug overlay (modifiers, weather, deck size) |
| Click rail hex with train selected | drive train manually |
| Panel buttons | **Garrison** (rest in adjacent city), **Deliver** (engineers unload into city), **Set Route** (engineers: click source city, then destination — standing supply run; manual move orders cancel it) |

## Combat & movement rules

- Movement resolves in up to 3 passes, so a column can advance into hexes
  vacated the same turn. No swaps: a hex must actually be free.
- Auto-goals route **around** other units when possible, and only queue
  through traffic when fully boxed in.
- **Withdrawal fire**: breaking contact with an adjacent enemy combatant costs
  a parting shot (half its damage). Retreat is possible, never free.
- Friendly fire is impossible (including cities you've just captured), and
  stale attack targets clear when a target changes sides.

## Rails (Engineers)

- Rail can only be planned (R) on hexes adjacent to your **Engineers** unit —
  they're the builders (class `Engineers`; internal ids stay "logistics").
- Rail cannot cross a river edge until a bridge stands there.
- T on a plan touching an existing line's end **extends** that route (the
  running train adopts the longer line, no new train needed); otherwise it
  commits a new line, which needs ≥2 hexes and a train in stock.
- Trains halt at broken rail *or* broken bridges until Engineers repair them.

## Fixed bugs (from before the refactor)

- City buy menu was broken, then removed entirely by design (see Economy above).
- `refresh_stats` never worked (`current_viewed_piece` was never set).
- `morale_collapse` card script crashed (wrong `select_pieces` arity).
- `rail_established` trigger (armoured train story) was never emitted.
- The weekly requisition offer existed but was never wired in.
- Jan/Feb counted as spring in `current_season`.
- Manual attack orders were consumed by the intent renderer (`refresh_intent`
  popped `pending_attack`).
- Hex (0,0) was treated as "no selection"/"no hex" (falsy `Vector2i` sentinels);
  movement now uses `null`.
- Trains could spawn on top of an occupied route hex.
- Stats panel showed attack target as "Destination", and path/goal info never displayed.
- Dead-code removal: duplicate city-menu state in Game, `pending_cards`,
  `pending_restores`, `_occupied_hexes`, `_next_day_button`, `Deck.len/pop`,
  duplicate `ally`/`piece` refs in Attack, `valid_hex` duplication in Movement.

## Notes

- `scripts/*.gd.bak` are old backups; they're ignored by Godot. Delete when comfortable.
- Starting scenario lives in `Game._spawn_starting_forces()` — city names are
  placeholders (Aldermark / Veslograd / Brennfeld) and feed intel reports, so
  name cities meaningfully when you add map generation.
