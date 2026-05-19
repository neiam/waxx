defmodule Waxx.Kanban.CardFieldValue do
  @moduledoc """
  The value of a board field on a card. Stored as a single text column
  regardless of `BoardField.kind`: dates as ISO strings, selects as the
  option text, free-text as itself. Empty values are deleted rather than
  stored as `""`.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.{Card, BoardField}

  schema "card_field_values" do
    field :value, :string

    belongs_to :card, Card
    belongs_to :board_field, BoardField

    timestamps(type: :utc_datetime)
  end

  def changeset(value, attrs) do
    value
    |> cast(attrs, [:card_id, :board_field_id, :value])
    |> validate_required([:card_id, :board_field_id])
    |> unique_constraint([:card_id, :board_field_id])
  end
end
