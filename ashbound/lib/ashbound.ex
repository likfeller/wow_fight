defmodule Ashbound do
  @moduledoc """
  Ashbound — the FROSTBOUND boss-fight game logic, ported from the single-file
  browser game (`index.html`) to idiomatic, purely-functional Elixir.

  Only the *logic* is ported: state, boss AI, abilities, damage math, upgrades,
  XP/leveling and the per-frame tick. Rendering (canvas drawing, particles,
  floating text, screen shake and the DOM `syncUI`) lives in the browser and is
  intentionally out of scope.

  ## Shape

  Everything is a pure function `game -> game` over an `Ashbound.Game` struct;
  there is no process or global state. Drive it from a loop of your choosing
  (an IEx session, a GenServer, a test):

      g = Ashbound.new() |> Ashbound.start()
      g = Ashbound.press(g, "d")           # hold right
      g = Ashbound.tick(g, 0.016)          # advance one 16ms frame
      g = Ashbound.ability(g, :attack)     # queue a Strike

  When `g.paused` is true an upgrade draft is open; `g.offered` holds the three
  card ids — resolve it with `choose/2`:

      [id | _] = g.offered
      g = Ashbound.choose(g, id)

  `g.over` with `g.outcome` (`:win` / `:lose`) marks the end of a run.
  `g.log` is a newest-first list of non-visual events, handy for tests/observers.
  """

  alias Ashbound.{Game, State, Player, Combat, Tick}

  @doc "Build a fresh game. Accepts `:arena` as `{w, h}`. Ports `newGame`."
  defdelegate new(opts \\ []), to: State

  @doc "Begin the run (flips `started`, clears pause/over). Ports `startGame`."
  def start(%Game{} = g),
    do:
      %{g | started: true, paused: false, over: false}
      |> Game.log({:phase, 1, "PHASE I", "The trial begins"})

  @doc "Advance the simulation by `dt` seconds. Ports `update`."
  defdelegate tick(game, dt), to: Tick, as: :update

  @doc "Trigger an ability (`:attack` / `:defend` / `:ult`). Ports `tryAbility`."
  def ability(%Game{started: false} = g, _name), do: g
  def ability(%Game{over: true} = g, _name), do: g
  def ability(%Game{paused: true} = g, _name), do: g
  def ability(g, :attack), do: Player.attack(g)
  def ability(g, :defend), do: Player.defend(g)
  def ability(g, :ult), do: Player.ult(g)

  @doc "Pick an offered upgrade by id. Ports `chooseUpgrade`."
  defdelegate choose(game, id), to: Combat, as: :choose_upgrade

  @doc "Press/hold a movement key (lower-cased, e.g. `\"w\"`, `\"arrowleft\"`)."
  def press(%Game{held: h} = g, key), do: %{g | held: MapSet.put(h, String.downcase(key))}

  @doc "Release a movement key."
  def release(%Game{held: h} = g, key), do: %{g | held: MapSet.delete(h, String.downcase(key))}

  @doc "Release all movement keys (ports the `window blur` handler)."
  def release_all(%Game{} = g), do: %{g | held: MapSet.new()}
end
