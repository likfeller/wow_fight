defmodule Ashbound.BossDef do
  @moduledoc "Static definition of a boss in the roster (ports a `BOSS_DEFS` entry)."
  defstruct [:kind, :name, :sub, :hp, :dmg_mul, :phases, :phase_names, :intro, :fall]
end

defmodule Ashbound.Game do
  @moduledoc """
  The whole game state. Ports the object returned by `newGame`, plus a few
  fields the browser version kept outside the state object:

    * `arena` — `{w, h}` logical arena size (the JS read live canvas `W`/`H`).
    * `held` — `MapSet` of currently-held movement keys.
    * `pending` — scheduled hits that replace the JS `setTimeout` damage.
    * `transition_timer` — countdown driving the between-boss / death beat.
    * `offered` / `pending_upgrades` / `recent_offered` — upgrade-draft state
      (the JS held `recentOffered` at module scope and the modal in the DOM).
    * `log` — newest-first list of non-visual game events, for tests/observers.
  """

  alias Ashbound.{Player, Boss}

  @type t :: %__MODULE__{}

  defstruct p: %Player{},
            boss: %Boss{},
            stage: 0,
            transitioning: false,
            time: 0,
            kills: 0,
            dmg_dealt: 0,
            over: false,
            outcome: nil,
            paused: false,
            started: false,
            dmg_taken: 0,
            levels_gained: 0,
            arena: {1280, 720},
            held: MapSet.new(),
            pending: [],
            transition_timer: nil,
            offered: [],
            pending_upgrades: 0,
            recent_offered: [],
            log: []

  @doc "Center point of the boss sprite — `{W*0.5, H*0.43}` in the original."
  def boss_center(%__MODULE__{arena: {w, h}}), do: {w * 0.5, h * 0.43}

  @doc "Current player position `{px, py}`."
  def player_pos(%__MODULE__{p: p}), do: {p.px, p.py}

  @doc "Append a non-visual event to the log (newest first, bounded)."
  def log(%__MODULE__{log: log} = g, event), do: %{g | log: Enum.take([event | log], 200)}
end

defmodule Ashbound.State do
  @moduledoc """
  Game construction. Ports `newGame`.

  `new/1` accepts `:arena` as `{w, h}`; the player starts centred near the
  bottom (`W*0.5`, `H*0.74`), exactly as the browser placed them.
  """

  alias Ashbound.{Game, Player, Boss}

  @spec new(keyword()) :: Ashbound.Game.t()
  def new(opts \\ []) do
    {w, h} = arena = Keyword.get(opts, :arena, {1280, 720})

    p = %Player{px: w * 0.5, py: h * 0.74}
    boss = Boss.create(0)

    %Game{p: p, boss: boss, arena: arena, started: false}
  end
end
