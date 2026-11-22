defmodule Ashbound.Player do
  @moduledoc """
  Player state and the player-facing actions:

    * the three abilities (`attack/1`, `defend/1`, `ult/1`), which port
      `doAttack` / `doDefend` / `doUlt`;
    * `heal/3` (ports `healPlayer`);
    * `take_damage/3` (ports `playerTakeDamage`);
    * `resolve_strike/1` and `resolve_ult/1`, which the tick calls when a
      scheduled hit lands — these replace the JS `setTimeout` callbacks.

  Every function is `game -> game`.
  """

  alias Ashbound.{Game, Boss, Combat}

  @strike_delay 0.110
  @ult_delay 0.420

  defstruct name: "Challenger",
            hp: 100,
            max_hp: 100,
            shield: 0,
            # offense
            atk_dmg: 18,
            atk_cd: 0.85,
            atk_hits: 1,
            crit: 0.08,
            ult_dmg: 150,
            lifesteal: 0,
            # defense
            ward_reduce: 0.55,
            ward_heal: 8,
            ward_dur: 1.6,
            ward_cd: 6.5,
            armor: 0,
            thorns: 0,
            # arcane
            ult_cd: 14,
            flux: 0,
            burn: 0,
            ult_shield: 0,
            xp_mul: 1,
            chain: 0,
            # runtime
            ward_active: 0,
            cds: %{attack: 0, defend: 0, ult: 0},
            level: 1,
            xp: 0,
            xp_need: 140,
            upgrades: 0,
            taken_hits: 0,
            bob: 0,
            swing: 0,
            hurt: 0,
            cast: 0,
            facing: 1,
            px: 0.0,
            py: 0.0,
            speed: 330,
            move_bob: 0,
            moving: false,
            taken: %{}

  # ------------------------------------------------------------------
  #  Abilities (triggers)
  # ------------------------------------------------------------------

  @doc "Strike. Schedules `atk_hits` hits, 110ms apart. Ports `doAttack`."
  def attack(%Game{p: p} = g) do
    if p.cds.attack > 0 or g.over or g.paused do
      g
    else
      p = %{p | cds: %{p.cds | attack: p.atk_cd}, swing: 0.22, cast: 0.15}

      pending =
        for h <- 0..(p.atk_hits - 1), reduce: g.pending do
          acc -> [%{t: h * @strike_delay, kind: :strike} | acc]
        end

      %{g | p: p, pending: pending}
    end
  end

  @doc "Ward. Instant shield-buff + heal. Ports `doDefend`."
  def defend(%Game{p: p} = g) do
    if p.cds.defend > 0 or g.over or g.paused do
      g
    else
      p = %{p | cds: %{p.cds | defend: p.ward_cd}, ward_active: p.ward_dur}
      heal(%{g | p: p}, p.ward_heal, false)
    end
  end

  @doc "Cataclysm ultimate. Grants shield now, big hit after 420ms. Ports `doUlt`."
  def ult(%Game{p: p} = g) do
    if p.cds.ult > 0 or g.over or g.paused do
      g
    else
      shield = if p.ult_shield > 0, do: min(p.max_hp, p.shield + p.ult_shield), else: p.shield
      p = %{p | cds: %{p.cds | ult: p.ult_cd}, cast: 0.5, swing: 0.4, shield: shield}
      %{g | p: p, pending: [%{t: @ult_delay, kind: :ult} | g.pending]}
    end
  end

  # ------------------------------------------------------------------
  #  Scheduled-hit resolution (was inside the setTimeout callbacks)
  # ------------------------------------------------------------------

  @doc "Land one Strike hit: crit roll, chain bonus, damage, lifesteal, burn, flux."
  def resolve_strike(%Game{over: true} = g), do: g

  def resolve_strike(%Game{p: p} = g) do
    is_crit = :rand.uniform() < p.crit
    dmg = p.atk_dmg

    dmg =
      if is_crit do
        d = dmg * 2
        if p.chain > 0, do: d + p.atk_dmg * p.chain, else: d
      else
        dmg
      end

    color = if is_crit, do: "#ffd34d", else: "#ff9a6a"
    g = Boss.take_damage(g, dmg, is_crit, color)

    p = g.p
    # lifesteal
    g = if p.lifesteal > 0, do: heal(g, dmg * p.lifesteal, true), else: g
    p = g.p
    # burn application
    g =
      if p.burn > 0 do
        stack = %{dps: p.atk_dmg * 0.18 * p.burn, time: 3.0}
        put_in(g.boss.burn_stacks, [stack | g.boss.burn_stacks])
      else
        g
      end

    p = g.p
    # mana flux: chance to reset ward cooldown
    if p.flux > 0 and :rand.uniform() < p.flux do
      %{g | p: %{p | cds: %{p.cds | defend: 0}}} |> Game.log({:flux_reset})
    else
      g
    end
  end

  @doc "Land the Cataclysm hit. Ports the ult `setTimeout` body."
  def resolve_ult(%Game{over: true} = g), do: g

  def resolve_ult(%Game{p: p} = g) do
    is_crit = :rand.uniform() < p.crit
    dmg = p.ult_dmg * if(is_crit, do: 2, else: 1)
    Boss.take_damage(g, dmg, is_crit, "#d7a7ff")
  end

  # ------------------------------------------------------------------
  #  Heal / take damage
  # ------------------------------------------------------------------

  @doc "Heal the player, clamped to max HP. Ports `healPlayer`."
  def heal(%Game{over: true} = g, _amt, _from_steal), do: g
  def heal(g, amt, _from_steal) when amt <= 0, do: g

  def heal(%Game{p: p} = g, amt, from_steal) do
    before = p.hp
    hp = min(p.max_hp, p.hp + amt)
    gained = hp - before
    g = %{g | p: %{p | hp: hp}}
    if gained >= 1, do: Game.log(g, {:heal, round(gained), from_steal}), else: g
  end

  @doc """
  Apply incoming boss damage: armor → ward block (+thorns reflect) →
  shield absorb → HP. Ends the game on death. Ports `playerTakeDamage`.
  """
  def take_damage(%Game{over: true} = g, _raw, _type), do: g

  def take_damage(%Game{p: p} = g, raw, type) do
    dmg = raw * (1 - p.armor)

    {dmg, g} =
      if p.ward_active > 0 do
        blocked = dmg * p.ward_reduce
        g = Game.log(g, {:block})

        g =
          if p.thorns > 0 and blocked > 0 do
            refl = blocked * p.thorns
            Boss.take_damage(g, refl, false, "#9affbf")
          else
            g
          end

        {dmg - blocked, g}
      else
        {dmg, g}
      end

    dmg = max(0, dmg)
    p = g.p

    # shield absorbs first
    {shield, dmg} =
      if p.shield > 0 do
        absorb = min(p.shield, dmg)
        {p.shield - absorb, dmg - absorb}
      else
        {p.shield, dmg}
      end

    hp = max(0, p.hp - dmg)
    p = %{p | shield: shield, hp: hp, hurt: 0.25, taken_hits: p.taken_hits + 1}
    g = %{g | p: p, dmg_taken: g.dmg_taken + dmg}

    g = if dmg > 0.5, do: Game.log(g, {:player_hit, round(dmg), type}), else: g

    if hp <= 0, do: Combat.end_game(g, false), else: g
  end
end
