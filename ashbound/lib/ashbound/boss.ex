defmodule Ashbound.Boss do
  @moduledoc """
  Boss state, the roster, and all boss behaviour:

    * `roster/0`, `create/1` — port `BOSS_DEFS` and `createBoss`.
    * `phase_config/1` — ports `phaseConfig`.
    * `choose_attack/1` — ports `bossChooseAttack` (builds a telegraphed action).
    * `take_damage/4` — ports `bossTakeDamage` (damage, XP, phase, death).
    * `enter_phase/2`, `die/1`, `next_boss/2` — ports of the same.

  Actions are plain maps so they serialise cleanly; a `:type` of `:basic`,
  `:heavy`, or `:area` mirrors the three JS attack kinds.
  """

  import Ashbound.Rand, only: [rand: 2, clamp: 3, tau: 0]
  alias Ashbound.{Game, BossDef, Combat}

  defstruct [
    :kind,
    :name,
    :def,
    hp: 0,
    max_hp: 0,
    phase: 1,
    atk_timer: 2.2,
    action: nil,
    burn_stacks: [],
    bob: 0,
    breathe: 0,
    death: nil,
    hurt: 0,
    enraged: 0,
    phase_flash_t: 0
  ]

  # ------------------------------------------------------------------
  #  Roster
  # ------------------------------------------------------------------

  @roster [
    %BossDef{
      kind: :lich,
      name: "Kel'Thuzad",
      sub: "Archlich of Naxxramas",
      hp: 1000,
      dmg_mul: 1.0,
      phases: 2,
      phase_names: ["Rimecaller", "Frozen Tempest"],
      intro: ["KEL'THUZAD", "Archlich of Naxxramas"],
      fall: "Kel'Thuzad shatters into frozen dust... but a far colder power now stirs."
    },
    %BossDef{
      kind: :lichking,
      name: "The Lich King",
      sub: "Arthas · Wielder of Frostmourne",
      hp: 1500,
      dmg_mul: 1.3,
      phases: 3,
      phase_names: ["Frostmourne Hungers", "Remorseless Winter", "The Scourge Unleashed"],
      intro: ["THE LICH KING", "Arthas · Frostmourne"],
      fall: "The Lich King falls. Frostmourne shatters. The Scourge is broken — you are free."
    }
  ]

  @doc "The ordered boss roster."
  def roster, do: @roster

  @doc "Build a live boss from roster index `idx`. Ports `createBoss`."
  def create(idx) do
    d = Enum.at(@roster, idx)
    %__MODULE__{kind: d.kind, name: d.name, def: d, hp: d.hp, max_hp: d.hp, phase: 1, atk_timer: 2.2}
  end

  # ------------------------------------------------------------------
  #  Phase tuning
  # ------------------------------------------------------------------

  @doc "Per-phase pacing/damage config. Ports `phaseConfig`."
  def phase_config(1),
    do: %{gap: {2.0, 2.8}, heavy: 0.22, area: 0.16, basic_dmg: 7, heavy_dmg: 22, area_dmg: 18, warn_mul: 1.0, spikes: 1, name: "PHASE I", theme: "Rimecaller"}

  def phase_config(2),
    do: %{gap: {1.5, 2.1}, heavy: 0.34, area: 0.26, basic_dmg: 10, heavy_dmg: 28, area_dmg: 24, warn_mul: 0.88, spikes: 2, name: "PHASE II", theme: "Frozen Tempest"}

  def phase_config(3),
    do: %{gap: {1.0, 1.5}, heavy: 0.44, area: 0.34, basic_dmg: 13, heavy_dmg: 34, area_dmg: 30, warn_mul: 0.76, spikes: 3, name: "FINAL PHASE", theme: "Absolute Zero"}

  # ------------------------------------------------------------------
  #  Attack selection
  # ------------------------------------------------------------------

  @doc "Choose and telegraph the next boss attack. Ports `bossChooseAttack`."
  def choose_attack(%Game{boss: b, arena: {w, h}} = g) do
    cfg = phase_config(b.phase)
    m = if b.def, do: b.def.dmg_mul, else: 1
    r = :rand.uniform()

    type =
      cond do
        r < cfg.area -> :area
        r < cfg.area + cfg.heavy -> :heavy
        true -> :basic
      end

    {px, py} = Game.player_pos(g)

    action =
      case type do
        :basic ->
          %{type: :basic, warn: 0, warn_max: 0.55 * cfg.warn_mul, impact: false, dmg: cfg.basic_dmg * m}

        :heavy ->
          spikes =
            for i <- 0..(cfg.spikes - 1) do
              {x, y} =
                if i == 0 do
                  {px + rand(-20, 20), py + rand(-10, 10)}
                else
                  ang = rand(0, tau())
                  d = rand(130, 230)
                  {px + :math.cos(ang) * d, py + :math.sin(ang) * d * 0.55}
                end

              %{x: clamp(x, w * 0.1, w * 0.9), y: clamp(y, h * 0.52, h * 0.9), r: 78}
            end

          %{type: :heavy, warn: 0, warn_max: 1.35 * cfg.warn_mul, impact: false, dmg: cfg.heavy_dmg * m, spikes: spikes}

        :area ->
          %{
            type: :area,
            warn: 0,
            warn_max: 1.55 * cfg.warn_mul,
            impact: false,
            dmg: cfg.area_dmg * m,
            cx: px + rand(-40, 40),
            cy: py + rand(-10, 20),
            r: 150
          }
      end

    put_in(g.boss.action, action)
  end

  # ------------------------------------------------------------------
  #  Taking damage / phases / death
  # ------------------------------------------------------------------

  @doc "Apply damage to the boss, grant XP, handle phase & death. Ports `bossTakeDamage`."
  def take_damage(%Game{boss: %{hp: hp}} = g, _amount, _crit, _color) when hp <= 0, do: g

  def take_damage(%Game{boss: b} = g, amount, is_crit, _color) do
    hp = max(0, b.hp - amount)
    g = %{g | boss: %{b | hp: hp, hurt: 0.12}, dmg_dealt: g.dmg_dealt + amount}
    g = Game.log(g, {:boss_hit, round(amount), is_crit})

    g = Combat.gain_xp(g, amount)

    b = g.boss
    pct = b.hp / b.max_hp
    count = b.def.phases || 3
    new_phase = clamp(floor((1 - pct) * count) + 1, 1, count)

    g =
      if new_phase > b.phase and b.hp > 0 do
        enter_phase(g, new_phase)
      else
        g
      end

    if g.boss.hp <= 0, do: die(g), else: g
  end

  @doc "Advance to phase `n`: reset the wind-up beat and flag enrage. Ports `enterPhase`."
  def enter_phase(%Game{boss: b} = g, n) do
    cfg = phase_config(n)
    count = b.def.phases || 3
    is_final = n == count
    name = if is_final, do: "FINAL PHASE", else: cfg.name
    theme = Enum.at(b.def.phase_names || [], n - 1) || cfg.theme

    b = %{b | phase: n, phase_flash_t: 0.6, enraged: 1, action: nil, atk_timer: 0.8}
    %{g | boss: b} |> Game.log({:phase, n, name, theme})
  end

  @doc "Boss death: either advance to the next boss after a beat, or win. Ports `bossDie`."
  def die(%Game{boss: b} = g) do
    g = put_in(g.boss, %{b | death: 0.0001, action: nil})
    next_idx = g.stage + 1

    if next_idx < length(@roster) do
      %{g | transitioning: true, transition_timer: 2.8}
      |> Game.log({:boss_fall, b.name})
    else
      Combat.end_game(g, true)
    end
  end

  @doc """
  Swap in the next boss, keeping the player's build. Restores 40% HP and
  clears cooldowns. Ports `nextBoss`. Called by the tick when the
  transition timer elapses.
  """
  def next_boss(%Game{p: p} = g, idx) do
    heal = round(p.max_hp * 0.4)
    p = %{p | hp: min(p.max_hp, p.hp + heal), cds: %{attack: 0, defend: 0, ult: 0}}
    boss = create(idx)

    %{g | p: p, boss: boss, stage: idx, transitioning: false, transition_timer: nil}
    |> Game.log({:next_boss, boss.name})
  end
end
