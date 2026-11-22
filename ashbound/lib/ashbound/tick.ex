defmodule Ashbound.Tick do
  @moduledoc """
  The per-frame simulation step. Ports `update(dt)` (the non-visual parts —
  particles, floaters, screen-shake and `syncUI` are rendering concerns and
  are dropped). Scheduled `setTimeout` hits are replaced by the `pending`
  queue, drained here.

  `update/2` is a no-op while the game is paused (upgrade draft) or over,
  matching the browser's `frame()` guard.
  """

  import Ashbound.Rand, only: [rand: 2, clamp: 3, hypot: 2]
  alias Ashbound.{Game, Player, Boss, Combat}

  @doc "Advance the whole simulation by `dt` seconds."
  def update(%Game{over: true} = g, _dt), do: g

  # While an upgrade draft is open the sim is frozen — except the between-boss
  # transition, which ran on a real-time `setTimeout` in the original and so
  # must keep counting even with the modal up.
  def update(%Game{paused: true, transitioning: true} = g, dt), do: death_phase(g, dt)
  def update(%Game{paused: true} = g, _dt), do: g

  def update(g, dt) do
    g = %{g | time: g.time + dt}
    g = move_player(g, dt)
    g = tick_player_timers(g, dt)
    g = tick_boss_timers(g, dt)
    g = step_pending(g, dt)

    cond do
      g.boss.hp <= 0 ->
        death_phase(g, dt)

      true ->
        g = burn_dot(g, dt)
        if g.boss.hp <= 0, do: death_phase(g, dt), else: boss_ai(g, dt)
    end
  end

  # ------------------------------------------------------------------
  #  Movement (WASD / arrows via the held-key set)
  # ------------------------------------------------------------------

  defp move_player(%Game{p: p, held: held, arena: {w, h}} = g, dt) do
    mx = bool(left?(held), -1) + bool(right?(held), 1)
    my = bool(up?(held), -1) + bool(down?(held), 1)

    p =
      if mx != 0 or my != 0 do
        len = hypot(mx, my)
        len = if len == 0, do: 1, else: len
        facing = if mx != 0, do: sign(mx), else: p.facing

        %{
          p
          | px: p.px + mx / len * p.speed * dt,
            py: p.py + my / len * p.speed * dt,
            moving: true,
            move_bob: p.move_bob + dt * 11,
            facing: facing
        }
      else
        %{p | moving: false}
      end

    p = %{p | px: clamp(p.px, w * 0.08, w * 0.92), py: clamp(p.py, h * 0.54, h * 0.90)}
    %{g | p: p}
  end

  defp left?(h), do: "arrowleft" in h or "a" in h
  defp right?(h), do: "arrowright" in h or "d" in h
  defp up?(h), do: "arrowup" in h or "w" in h
  defp down?(h), do: "arrowdown" in h or "s" in h
  defp bool(true, v), do: v
  defp bool(false, _v), do: 0
  defp sign(x) when x > 0, do: 1
  defp sign(_), do: -1

  # ------------------------------------------------------------------
  #  Timer decays
  # ------------------------------------------------------------------

  defp tick_player_timers(%Game{p: p} = g, dt) do
    cds = Map.new(p.cds, fn {k, v} -> {k, max(0, v - dt)} end)

    p = %{
      p
      | cds: cds,
        ward_active: max(0, p.ward_active - dt),
        swing: p.swing - dt,
        cast: p.cast - dt,
        hurt: p.hurt - dt,
        bob: p.bob + dt
    }

    %{g | p: p}
  end

  defp tick_boss_timers(%Game{boss: b} = g, dt) do
    b = %{
      b
      | breathe: b.breathe + dt,
        bob: b.bob + dt,
        hurt: b.hurt - dt,
        enraged: b.enraged - dt,
        phase_flash_t: b.phase_flash_t - dt
    }

    %{g | boss: b}
  end

  # ------------------------------------------------------------------
  #  Pending (scheduled) player hits — replaces setTimeout
  # ------------------------------------------------------------------

  defp step_pending(%Game{pending: []} = g, _dt), do: g

  defp step_pending(%Game{pending: pending} = g, dt) do
    advanced = Enum.map(pending, fn h -> %{h | t: h.t - dt} end)
    {due, remaining} = Enum.split_with(advanced, &(&1.t <= 0))
    g = %{g | pending: remaining}

    Enum.reduce(Enum.reverse(due), g, fn
      %{kind: :strike}, acc -> Player.resolve_strike(acc)
      %{kind: :ult}, acc -> Player.resolve_ult(acc)
    end)
  end

  # ------------------------------------------------------------------
  #  Burn damage-over-time on the boss
  # ------------------------------------------------------------------

  defp burn_dot(%Game{boss: %{burn_stacks: []}} = g, _dt), do: g

  defp burn_dot(%Game{boss: b} = g, dt) do
    total = Enum.sum(Enum.map(b.burn_stacks, fn s -> s.dps * dt end))
    alive = b.burn_stacks |> Enum.map(&%{&1 | time: &1.time - dt}) |> Enum.filter(&(&1.time > 0))
    b = %{b | burn_stacks: alive}
    g = %{g | boss: b}

    if total > 0 do
      hp = max(0, b.hp - total)
      g = %{g | boss: %{b | hp: hp}, dmg_dealt: g.dmg_dealt + total}
      g = Combat.gain_xp(g, total)
      if g.boss.hp <= 0, do: Boss.die(g), else: g
    else
      g
    end
  end

  # ------------------------------------------------------------------
  #  Death / between-boss transition
  # ------------------------------------------------------------------

  defp death_phase(%Game{boss: b} = g, dt) do
    b = if b.death != nil, do: %{b | death: b.death + dt}, else: b
    advance_transition(%{g | boss: b}, dt)
  end

  defp advance_transition(%Game{transition_timer: nil} = g, _dt), do: g

  defp advance_transition(%Game{transition_timer: t} = g, dt) do
    nt = t - dt

    if nt <= 0 and g.transitioning and not g.over do
      Boss.next_boss(g, g.stage + 1)
    else
      %{g | transition_timer: nt}
    end
  end

  # ------------------------------------------------------------------
  #  Boss AI: wind-up → impact → recover
  # ------------------------------------------------------------------

  defp boss_ai(%Game{boss: %{action: nil, atk_timer: t} = b} = g, dt) do
    t = t - dt
    g = %{g | boss: %{b | atk_timer: t}}
    if t <= 0, do: Boss.choose_attack(g), else: g
  end

  defp boss_ai(%Game{boss: %{action: a} = b} = g, dt) do
    a = %{a | warn: a.warn + dt}
    g = %{g | boss: %{b | action: a}}

    g =
      if not a.impact and a.warn >= a.warn_max do
        resolve_impact(g)
      else
        g
      end

    expire_action(g)
  end

  defp resolve_impact(%Game{boss: b} = g) do
    a = b.action
    g = put_in(g.boss.action, %{a | impact: true})
    {px, py} = Game.player_pos(g)

    case a.type do
      :area ->
        if hypot(px - a.cx, py - a.cy) <= a.r,
          do: Player.take_damage(g, a.dmg, :area),
          else: dodge(g)

      :heavy ->
        if Enum.any?(a.spikes, fn sp -> hypot(px - sp.x, py - sp.y) <= sp.r end),
          do: Player.take_damage(g, a.dmg, :heavy),
          else: dodge(g)

      :basic ->
        Player.take_damage(g, a.dmg, :basic)
    end
  end

  defp expire_action(%Game{boss: %{action: a} = b} = g) when not is_nil(a) do
    if a.warn >= a.warn_max + 0.18 do
      {lo, hi} = Boss.phase_config(b.phase).gap
      %{g | boss: %{b | action: nil, atk_timer: rand(lo, hi)}}
    else
      g
    end
  end

  defp expire_action(g), do: g

  defp dodge(g), do: Game.log(g, {:dodge})
end
