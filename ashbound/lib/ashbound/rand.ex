defmodule Ashbound.Rand do
  @moduledoc """
  Ports the small math/random helpers from the JS game
  (`rand`, `randi`, `clamp`, `pick`, `lerp`, `TAU`).

  Randomness uses the process-local `:rand` state. Seed it in tests
  via `:rand.seed(:exsss, {1, 2, 3})` for deterministic runs.
  """

  @tau :math.pi() * 2
  def tau, do: @tau

  @doc "Uniform float in [a, b)."
  def rand(a, b), do: a + :rand.uniform() * (b - a)

  @doc "Uniform integer in [a, b] inclusive."
  def randi(a, b), do: floor(rand(a, b + 1))

  @doc "Clamp v into [a, b]."
  def clamp(v, a, b), do: max(a, min(b, v))

  @doc "Pick a random element of a non-empty list."
  def pick(list) when is_list(list) and list != [],
    do: Enum.at(list, floor(:rand.uniform() * length(list)))

  @doc "Linear interpolation."
  def lerp(a, b, t), do: a + (b - a) * t

  @doc "Distance between two points."
  def hypot(dx, dy), do: :math.sqrt(dx * dx + dy * dy)
end
