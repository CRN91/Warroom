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

## Economy (FTL-style scarcity)

There is **no open shop**. The player acquires units and stock only through
cards: rare paid supply offers (pity timer: guaranteed within 12 weeks, then
5–9 weeks apart), the periodic requisition (infrastructure only — never units),
and story decisions like conscription that trade permanent income for a unit.
City resources exist to feed the front and pay for card choices. The enemy AI
spawns units through `Board.spawn_unit_near_city` directly.

## Cards

- Daily cycle: intel → event → decision (turn 1 = intel).
- Every 6th week the decision slot is a **free requisition offer**
  (`CardManager.requisition_offer`); paid shops stay on their own pity timer.
- Card sets: `ambient` + `story_seeds` start in the deck; `consequences`,
  story chains and `supply_offers` enter only via injection/scheduling.
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
| Left click | select / order (move, attack, supply, build) |
| Right click / Esc | deselect (Esc also cancels a rail plan) |
| M / F | clear movement / clear attack target |
| R / T | plan rail on hovered hex / commit route |
| F3 | debug overlay (modifiers, weather, deck size) |
| Click rail hex with train selected | drive train manually |

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
