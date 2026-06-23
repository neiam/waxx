defmodule Waxx.Kanban.CardBackground do
  @moduledoc """
  A background image a user pasted onto a card. Stored as raw bytes plus a
  content type, one row per card. The board view renders cards from
  `Kanban.list_cards/1`, which does not load this association — the bytes
  only travel to the client when a single card is expanded, where they're
  inlined as a `data:` URL behind a translucent `base-100` overlay so the
  image blends into the card surface.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.Card

  # Pasted screenshots are typically well under this; the cap keeps a stray
  # huge paste from being shipped over the LiveView channel and stored.
  @max_bytes 5_000_000
  @content_types ~w(image/png image/jpeg image/gif image/webp)

  schema "card_backgrounds" do
    field :content_type, :string
    field :image_data, :binary

    belongs_to :card, Card

    timestamps(type: :utc_datetime)
  end

  def max_bytes, do: @max_bytes
  def content_types, do: @content_types

  def changeset(bg, attrs) do
    bg
    |> cast(attrs, [:card_id, :content_type, :image_data])
    |> validate_required([:card_id, :content_type, :image_data])
    |> validate_inclusion(:content_type, @content_types)
    |> validate_byte_size()
    |> unique_constraint(:card_id)
  end

  defp validate_byte_size(changeset) do
    validate_change(changeset, :image_data, fn :image_data, data ->
      if byte_size(data) > @max_bytes do
        [image_data: "is too large (max #{div(@max_bytes, 1_000_000)} MB)"]
      else
        []
      end
    end)
  end
end
