defmodule Waxx.Kanban.Subboard do
  @moduledoc """
  Named row within a board. Each card belongs to at most one subboard;
  cards with `subboard_id = nil` live in the implicit "default" row that
  always renders first in the grid view.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.{Board, Card}

  schema "board_subboards" do
    field :name, :string
    field :position, :integer, default: 0

    belongs_to :board, Board
    has_many :cards, Card

    timestamps(type: :utc_datetime)
  end

  def changeset(subboard, attrs) do
    subboard
    |> cast(attrs, [:board_id, :name, :position])
    |> validate_required([:board_id, :name])
    |> validate_length(:name, max: 120)
    |> unique_constraint([:board_id, :name])
  end
end
