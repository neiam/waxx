defmodule Waxx.UUIDv7 do
  @moduledoc """
  Ecto type producing UUID version 7 values.

  UUIDv7 places a 48-bit Unix-milliseconds timestamp at the start of the
  identifier, so values sort lexicographically by creation time — useful
  for primary keys because most-recent rows cluster, b-tree inserts stay
  near the end of the index, and downstream `ORDER BY id` is "close
  enough" to `ORDER BY inserted_at` for free.

  Cast / dump / load delegate to `Ecto.UUID`; only `autogenerate/0`
  differs. Postgres stores the value in the standard `uuid` column type
  (`type/0` returns `:uuid`).

  ## Layout (RFC 9562 §5.7)

      0                   1                   2                   3
       0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
      |                           unix_ts_ms                          |
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
      |          unix_ts_ms           |  ver  |       rand_a          |
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
      |var|                        rand_b                             |
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
      |                            rand_b                             |
      +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  """
  use Ecto.Type

  @impl true
  def type, do: :uuid

  @impl true
  def cast(value), do: Ecto.UUID.cast(value)

  @impl true
  def dump(value), do: Ecto.UUID.dump(value)

  @impl true
  def load(value), do: Ecto.UUID.load(value)

  @impl true
  def autogenerate, do: generate()

  @spec generate() :: String.t()
  def generate, do: generate_bin() |> Ecto.UUID.cast!()

  @spec generate_bin() :: <<_::128>>
  def generate_bin do
    ts_ms = System.system_time(:millisecond)
    <<rand_a::12, rand_b::62, _::6>> = :crypto.strong_rand_bytes(10)
    <<ts_ms::48, 0b0111::4, rand_a::12, 0b10::2, rand_b::62>>
  end
end
