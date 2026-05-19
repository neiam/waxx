defmodule Waxx.Kanban.CardLabel do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.{Card, BoardLabel}

  schema "card_labels" do
    belongs_to :card, Card
    belongs_to :board_label, BoardLabel

    timestamps(type: :utc_datetime)
  end

  def changeset(card_label, attrs) do
    card_label
    |> cast(attrs, [:card_id, :board_label_id])
    |> validate_required([:card_id, :board_label_id])
    |> unique_constraint([:card_id, :board_label_id])
  end
end
