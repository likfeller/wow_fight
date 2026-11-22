defmodule AshboundTest do
  use ExUnit.Case, async: true

  alias Ashbound.{Game, Boss, Combat, Player}

  setup do
    # deterministic randomness per test
    :rand.seed(:exsss, {101, 202, 303})
    g = Ashbound.new() |> Ashbound.start()
    {:ok, g: g}
  end

  test "new game sets up Kel'Thuzad and a full-health player", %{g: g} do
    assert g.boss.name == "Kel'Thuzad"
    assert g.boss.hp == 1000
    assert g.boss.def.phases == 2
    assert g.p.hp == 100
    assert g.p.level == 1
    refute g.over
  end

  test "Strike queues hits that land and damage the boss over time", %{g: g} do
    g = Ashbound.ability(g, :attack)
    assert length(g.pending) == 1
    assert g.boss.hp == 1000, "no damage before the hit lands"

    # advance past the 110ms strike delay
    g = Ashbound.tick(g, 0.2)
    assert g.pending == []
    assert g.boss.hp < 1000
    assert g.dmg_dealt > 0
  end

  test "Cleaving Blow makes Strike hit twice", %{g: g} do
    g = put_in(g.p.atk_hits, 2)
    g = Ashbound.ability(g, :attack)
    assert length(g.pending) == 2
    g = Ashbound.tick(g, 0.3)
    # two base hits of 18 (crit aside) => ~36 dealt
    assert g.dmg_dealt >= 30
  end

  test "Ward sets cooldown and a timed shield buff", %{g: g} do
    g = Ashbound.ability(g, :defend)
    assert g.p.cds.defend == g.p.ward_cd
    assert g.p.ward_active == g.p.ward_dur
  end

  test "Ward blocks part of an incoming hit", %{g: g} do
    g = %{g | p: %{g.p | hp: 100, ward_active: 2.0}}
    g = Player.take_damage(g, 40, :heavy)
    # 40 * (1 - ward_reduce 0.55) = 18 through
    assert_in_delta g.p.hp, 82.0, 0.001
    assert Enum.any?(g.log, &match?({:block}, &1))
  end

  test "ult lands a big hit after its wind-up and can grant a shield", %{g: g} do
    g = put_in(g.p.ult_shield, 50)
    g = Ashbound.ability(g, :ult)
    assert g.p.shield == 50, "shield granted immediately"
    before = g.boss.hp
    g = Ashbound.tick(g, 0.5)
    assert g.boss.hp < before - 100
  end

  test "dealing lots of damage levels up and opens an upgrade draft", %{g: g} do
    g = Combat.gain_xp(g, 1000)
    assert g.paused
    assert length(g.offered) == 3
    assert g.p.level > 1

    # drafting one card per queued level, until play resumes
    g = resolve_all_drafts(g)
    refute g.paused
    assert g.offered == []
    assert g.p.upgrades == g.p.level - 1
  end

  test "choosing an upgrade applies its effect", %{g: g} do
    g = Combat.open_upgrade(g)
    # force a known card to be offered
    g = %{g | offered: [:sharp], pending_upgrades: 1}
    before = g.p.atk_dmg
    g = Ashbound.choose(g, :sharp)
    assert_in_delta g.p.atk_dmg, before * 1.25, 0.001
    assert g.p.taken[:sharp] == 1
  end

  test "boss advances a phase as its health crosses the threshold", %{g: g} do
    # two-phase boss: phase 2 begins once below 50% HP
    g = Boss.take_damage(g, 600, false, "#fff")
    assert g.boss.phase == 2
    assert Enum.any?(g.log, &match?({:phase, 2, _, _}, &1))
  end

  test "killing the first boss transitions to the Lich King, keeping the build", %{g: g} do
    g = put_in(g.p.atk_dmg, 999)
    g = Boss.take_damage(g, 2000, false, "#fff")
    assert g.transitioning
    assert g.transition_timer != nil
    refute g.over

    g = Ashbound.tick(g, 3.0)
    assert g.boss.name == "The Lich King"
    assert g.stage == 1
    assert g.p.atk_dmg == 999, "upgrades carry over"
  end

  test "killing the final boss wins the game", %{g: g} do
    g = Boss.take_damage(g, 2000, false, "#fff")
    g = Ashbound.tick(g, 3.0)
    assert g.boss.name == "The Lich King"

    g = Boss.take_damage(g, 2000, false, "#fff")
    assert g.over
    assert g.outcome == :win
  end

  test "dropping to zero HP loses the game", %{g: g} do
    g = %{g | p: %{g.p | hp: 10, armor: 0}}
    g = Player.take_damage(g, 50, :heavy)
    assert g.p.hp == 0
    assert g.over
    assert g.outcome == :lose
  end

  test "held keys move the player and the arena clamps position", %{g: g} do
    {w, _h} = g.arena
    start_x = g.p.px
    g = Ashbound.press(g, "d")
    g = Ashbound.tick(g, 0.1)
    assert g.p.px > start_x
    assert g.p.px <= w * 0.92

    # hold right for a long time → clamp to the right wall
    g = Enum.reduce(1..100, g, fn _, g -> Ashbound.tick(g, 0.1) end)
    assert_in_delta g.p.px, w * 0.92, 0.001
  end

  test "boss basic attack telegraphs then connects for unavoidable chip damage", %{g: g} do
    # force an attack to be chosen, then run until something resolves
    g = put_in(g.boss.atk_timer, 0.0)

    g =
      Enum.reduce_while(1..400, g, fn _, g ->
        g = Ashbound.tick(g, 0.016)
        if g.p.hp < 100, do: {:halt, g}, else: {:cont, g}
      end)

    assert g.p.hp < 100
  end

  defp resolve_all_drafts(%Game{paused: true} = g) do
    [id | _] = g.offered
    g |> Ashbound.choose(id) |> resolve_all_drafts()
  end

  defp resolve_all_drafts(g), do: g
end
