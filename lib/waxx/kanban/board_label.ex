defmodule Waxx.Kanban.BoardLabel do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.Board

  schema "board_labels" do
    field :name, :string
    field :color, :string

    belongs_to :board, Board

    timestamps(type: :utc_datetime)
  end

  def changeset(label, attrs) do
    label
    |> cast(attrs, [:board_id, :name, :color])
    |> validate_required([:board_id, :name])
    |> validate_length(:name, max: 60)
    |> validate_length(:color, max: 32)
    |> unique_constraint([:board_id, :name])
  end
end
