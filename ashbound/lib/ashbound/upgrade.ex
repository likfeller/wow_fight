defmodule Ashbound.Upgrade do
  @moduledoc """
  The upgrade-card roster. Ports the JS `UPGRADES` array.

  Three categories: `:off` (Offense), `:def` (Defense), `:arc` (Arcane).
  Each card carries an `apply` function `(player -> player)` and a `desc`
  function `(player -> String.t())`, mirroring the originals.
  """

  import Ashbound.Rand, only: [clamp: 3]

  defstruct [:id, :cat, :name, :icon, :stack, :desc, :apply]

  @type t :: %__MODULE__{
          id: atom(),
          cat: :off | :def | :arc,
          name: String.t(),
          icon: String.t(),
          stack: boolean(),
          desc: (map() -> String.t()),
          apply: (map() -> map())
        }

  @cat_label %{off: "Offense", def: "Defense", arc: "Arcane"}
  def cat_label, do: @cat_label
  def cat_label(cat), do: Map.fetch!(@cat_label, cat)

  @doc "The full list of upgrade definitions, in roster order."
  @spec all() :: [t()]
  def all do
    [
      # ---- OFFENSE ----
      u(:sharp, :off, "Honed Edge", "🗡️", true,
        fn _ -> "+25% Strike damage." end,
        fn p -> %{p | atk_dmg: p.atk_dmg * 1.25} end),
      u(:swift, :off, "Swift Hands", "💨", true,
        fn _ -> "Strike cooldown −18%." end,
        fn p -> %{p | atk_cd: p.atk_cd * 0.82} end),
      u(:crit, :off, "Killer Instinct", "🎯", true,
        fn _ -> "+15% crit chance (crits deal 2×)." end,
        fn p -> %{p | crit: clamp(p.crit + 0.15, 0, 0.9)} end),
      u(:cleave, :off, "Cleaving Blow", "🪓", false,
        fn _ -> "Strike hits twice in one swing." end,
        fn p -> %{p | atk_hits: p.atk_hits + 1} end),
      u(:ultpow, :off, "Dire Cataclysm", "🔥", true,
        fn _ -> "+40% Cataclysm damage." end,
        fn p -> %{p | ult_dmg: p.ult_dmg * 1.4} end),
      u(:lifesteal, :off, "Vampiric Edge", "🩸", true,
        fn _ -> "Heal for 12% of Strike damage dealt." end,
        fn p -> %{p | lifesteal: p.lifesteal + 0.12} end),

      # ---- DEFENSE ----
      u(:vigor, :def, "Iron Vigor", "❤️", true,
        fn _ -> "+40 Max HP (and heal 40)." end,
        fn p -> %{p | max_hp: p.max_hp + 40, hp: min(p.max_hp + 40, p.hp + 40)} end),
      u(:bulwark, :def, "Bulwark", "🛡️", true,
        fn _ -> "Ward damage reduction +12% (while active)." end,
        fn p -> %{p | ward_reduce: clamp(p.ward_reduce + 0.12, 0, 0.95)} end),
      u(:mend, :def, "Mending Light", "✨", true,
        fn _ -> "Ward heals +14 HP." end,
        fn p -> %{p | ward_heal: p.ward_heal + 14} end),
      u(:endure, :def, "Endurance", "⏳", true,
        fn _ -> "Ward lasts +0.6s and cooldown −15%." end,
        fn p -> %{p | ward_dur: p.ward_dur + 0.6, ward_cd: p.ward_cd * 0.85} end),
      u(:plate, :def, "Cinder Plate", "🪖", true,
        fn _ -> "Permanent −10% damage taken." end,
        fn p -> %{p | armor: clamp(p.armor + 0.10, 0, 0.75)} end),
      u(:thorns, :def, "Thornmail", "🌵", true,
        fn _ -> "Reflect 60% of blocked damage back." end,
        fn p -> %{p | thorns: p.thorns + 0.6} end),

      # ---- ARCANE ----
      u(:haste, :arc, "Arcane Haste", "⚡", true,
        fn _ -> "Cataclysm cooldown −22%." end,
        fn p -> %{p | ult_cd: p.ult_cd * 0.78} end),
      u(:flux, :arc, "Mana Flux", "🔮", true,
        fn _ -> "25% chance a Strike resets Ward cooldown." end,
        fn p -> %{p | flux: p.flux + 0.25} end),
      u(:burn, :arc, "Searing Brand", "🔆", true,
        fn _ -> "Strikes apply a burn (DoT) to the boss." end,
        fn p -> %{p | burn: p.burn + 1} end),
      u(:barrier, :arc, "Spellward", "💠", true,
        fn _ -> "Cataclysm grants a 50-pt shield." end,
        fn p -> %{p | ult_shield: p.ult_shield + 50} end),
      u(:attune, :arc, "Essence Attunement", "🌀", true,
        fn _ -> "+30% essence gained (level up faster)." end,
        fn p -> %{p | xp_mul: p.xp_mul * 1.3} end),
      u(:chain, :arc, "Chain Lightning", "🌩️", true,
        fn _ -> "Crits unleash lightning for +60% bonus." end,
        fn p -> %{p | chain: p.chain + 0.6} end)
    ]
  end

  @doc "Look up an upgrade by id."
  @spec get(atom()) :: t() | nil
  def get(id), do: Enum.find(all(), &(&1.id == id))

  defp u(id, cat, name, icon, stack, desc, apply) do
    %__MODULE__{id: id, cat: cat, name: name, icon: icon, stack: stack, desc: desc, apply: apply}
  end
end
