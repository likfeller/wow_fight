defmodule Ashbound.Combat do
  @moduledoc """
  Progression and flow: XP gain, leveling, the three-card upgrade draft, and
  ending the game. Ports `gainXP`, `rollUpgrades`, `openUpgrade`,
  `chooseUpgrade`, and `endGame`.

  Note on multi-level gains: the original drained all pending XP in `gainXP`'s
  loop, which defeated `chooseUpgrade`'s "reopen if xp still high" check and
  silently granted only one card even after several levels. This port keeps a
  `pending_upgrades` counter so you draft one card *per* level gained — the
  behaviour the reopen logic was clearly reaching for.
  """

  alias Ashbound.{Game, Upgrade}

  # ------------------------------------------------------------------
  #  XP / leveling
  # ------------------------------------------------------------------

  @doc "Grant XP for damage dealt and process any level-ups. Ports `gainXP`."
  def gain_xp(%Game{over: true} = g, _dmg), do: g

  def gain_xp(%Game{p: p} = g, dmg) do
    g = %{g | p: %{p | xp: p.xp + dmg * p.xp_mul * 0.9}}
    g = level_up_loop(g)

    if g.pending_upgrades > 0 and g.offered == [] and not g.over do
      open_upgrade(g)
    else
      g
    end
  end

  defp level_up_loop(%Game{over: true} = g), do: g

  defp level_up_loop(%Game{p: p} = g) when p.xp >= p.xp_need do
    p = %{
      p
      | xp: p.xp - p.xp_need,
        level: p.level + 1,
        upgrades: p.upgrades + 1,
        xp_need: round(p.xp_need * 1.28 + 40)
    }

    %{g | p: p, levels_gained: g.levels_gained + 1, pending_upgrades: g.pending_upgrades + 1}
    |> level_up_loop()
  end

  defp level_up_loop(g), do: g

  # ------------------------------------------------------------------
  #  Upgrade draft
  # ------------------------------------------------------------------

  @doc "Pause and present three upgrade cards. Ports `openUpgrade`."
  def open_upgrade(g) do
    {ids, recent} = roll_upgrades(g)
    %{g | paused: true, offered: ids, recent_offered: recent} |> Game.log({:upgrade_offer, ids})
  end

  @doc """
  Pick a balanced set of (up to) three upgrade ids, biased away from recent
  offers, one per category where possible. Ports `rollUpgrades`.

  Returns `{offered_ids, new_recent_offered}`.
  """
  def roll_upgrades(%Game{p: p, recent_offered: recent}) do
    by_cat =
      Enum.reduce(Upgrade.all(), %{off: [], def: [], arc: []}, fn u, acc ->
        taken = Map.get(p.taken, u.id, 0)

        if not u.stack and taken > 0 do
          acc
        else
          Map.update!(acc, u.cat, &(&1 ++ [u]))
        end
      end)

    # one per category first (balanced mix)
    chosen =
      Enum.reduce([:off, :def, :arc], [], fn c, chosen ->
        pool = Enum.reject(by_cat[c], &(&1 in chosen))

        case draw_from(pool, recent) do
          nil -> chosen
          u -> chosen ++ [u]
        end
      end)

    # fill to 3 from whatever's left
    all = by_cat.off ++ by_cat.def ++ by_cat.arc
    chosen = fill_to_three(chosen, all, recent)

    ids = chosen |> Enum.take(3) |> Enum.map(& &1.id)
    new_recent = (recent ++ ids) |> Enum.take(-6)
    {ids, new_recent}
  end

  defp fill_to_three(chosen, _all, _recent) when length(chosen) >= 3, do: chosen

  defp fill_to_three(chosen, all, recent) do
    pool = Enum.reject(all, &(&1 in chosen))

    case draw_from(pool, recent) do
      nil -> chosen
      u -> fill_to_three(chosen ++ [u], all, recent)
    end
  end

  # weighted draw: cards offered recently get weight 1, others weight 3
  defp draw_from([], _recent), do: nil

  defp draw_from(pool, recent) do
    weighted = Enum.map(pool, fn u -> {u, if(u.id in recent, do: 1, else: 3)} end)
    total = Enum.sum(Enum.map(weighted, fn {_u, w} -> w end))
    pick_weighted(weighted, :rand.uniform() * total)
  end

  defp pick_weighted([{u, _w}], _r), do: u

  defp pick_weighted([{u, w} | rest], r) do
    if r - w <= 0, do: u, else: pick_weighted(rest, r - w)
  end

  @doc """
  Apply the chosen upgrade, then either present the next queued draft or
  resume play. Ports `chooseUpgrade`.
  """
  def choose_upgrade(%Game{p: p} = g, id) do
    up = Upgrade.get(id)
    taken = Map.update(p.taken, id, 1, &(&1 + 1))
    p = up.apply.(%{p | taken: taken})

    g =
      %{g | p: p, pending_upgrades: max(0, g.pending_upgrades - 1)}
      |> Game.log({:upgrade_choose, id})

    if g.pending_upgrades > 0 do
      open_upgrade(g)
    else
      %{g | paused: false, offered: []}
    end
  end

  # ------------------------------------------------------------------
  #  Game over
  # ------------------------------------------------------------------

  @doc "End the run. Ports `endGame`."
  def end_game(%Game{over: true} = g, _win), do: g

  def end_game(g, win) do
    outcome = if win, do: :win, else: :lose
    %{g | over: true, outcome: outcome, paused: false} |> Game.log({:game_over, outcome})
  end
end
