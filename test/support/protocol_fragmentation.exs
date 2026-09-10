defmodule ExAgent.Test.ProtocolFragmentation do
  @moduledoc false

  def seeds, do: [37_556, 106_033, 910_247]

  # Independent byte partitions: random 1..23-byte intervals plus forced cuts
  # inside every UTF-8 codepoint. No global random state or generated atoms.
  def partition(wire, seed) do
    random = :rand.seed_s(:exsss, {seed, 17, 29})
    cuts = random_cuts(byte_size(wire), 0, random, [0, byte_size(wire)])

    utf8_cuts =
      wire
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.flat_map(fn {byte, index} -> if byte in 128..191, do: [index], else: [] end)

    (cuts ++ utf8_cuts)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [first, last] -> binary_part(wire, first, last - first) end)
  end

  defp random_cuts(size, offset, random, cuts) do
    {width, random} = :rand.uniform_s(23, random)
    next = offset + width

    if next >= size,
      do: cuts,
      else: random_cuts(size, next, random, [next | cuts])
  end
end
