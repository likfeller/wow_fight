# Ashbound

The **game logic** of the FROSTBOUND browser boss-fight (`../index.html`),
ported to idiomatic, purely-functional Elixir.

Only the simulation is ported. Rendering — the canvas `draw*` routines,
particles, floating text, screen shake and the DOM `syncUI` — stays in the
browser and is intentionally out of scope. Everything here is a pure function
`game -> game` over an `Ashbound.Game` struct: no processes, no globals.

## Quick start

```elixir
g = Ashbound.new() |> Ashbound.start()

g = Ashbound.press(g, "d")        # hold a movement key
g = Ashbound.tick(g, 0.016)       # advance one ~16ms frame
g = Ashbound.ability(g, :attack)  # :attack | :defend | :ult
g = Ashbound.tick(g, 0.2)         # the queued Strike lands here

# Upgrade draft: when g.paused is true, g.offered holds three card ids
if g.paused, do: g = Ashbound.choose(g, hd(g.offered))

# g.over + g.outcome (:win | :lose) ends a run
# g.log is a newest-first list of non-visual events (for tests/observers)
```

Drive it from anything — an IEx session, a `GenServer` tick loop, or a test.

## Module map (JS → Elixir)

| Browser (`index.html`)                         | Elixir                         |
| ---------------------------------------------- | ------------------------------ |
| `rand`/`randi`/`clamp`/`pick`/`lerp`/`TAU`     | `Ashbound.Rand`                |
| `UPGRADES`, `CAT_LABEL`                         | `Ashbound.Upgrade`             |
| `newGame`, `BOSS_DEFS`, state object           | `Ashbound.State` / `Ashbound.Game` / `Ashbound.BossDef` |
| `p` object, `doAttack`/`doDefend`/`doUlt`, `healPlayer`, `playerTakeDamage` | `Ashbound.Player` |
| `createBoss`, `phaseConfig`, `bossChooseAttack`, `bossTakeDamage`, `enterPhase`, `bossDie`, `nextBoss` | `Ashbound.Boss` |
| `gainXP`, `rollUpgrades`, `openUpgrade`, `chooseUpgrade`, `endGame` | `Ashbound.Combat` |
| `update(dt)`                                   | `Ashbound.Tick`                |
| key handlers, `tryAbility`                     | `Ashbound` (facade)            |

## Notes on the port

- **`setTimeout` damage** (delayed Strike/ult hits) became a `pending` queue on
  the state, drained by `Ashbound.Tick`. No timers, no side effects.
- **The upgrade modal / `recentOffered`** (DOM + a module-global array) became
  plain state: `offered`, `pending_upgrades`, `recent_offered`.
- **Multi-level gains:** the original drained all XP in `gainXP`'s loop, which
  defeated `chooseUpgrade`'s reopen check and silently granted only one card
  after several levels. This port keeps a `pending_upgrades` counter so you
  draft one card **per** level — the behaviour the reopen logic was reaching
  for. See the note in `Ashbound.Combat`.
- **The between-boss beat** (`setTimeout(nextBoss, 2800)`) is a
  `transition_timer` the tick counts down — and it keeps counting even while an
  upgrade draft is open, matching the real-time `setTimeout`.

## Test

```
mix test
```
