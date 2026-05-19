defmodule Waxx.Kanban.BoardStage do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.Board

  schema "board_stages" do
    field :name, :string
    field :position, :integer
    field :color, :string

    belongs_to :board, Board

    timestamps(type: :utc_datetime)
  end

  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:board_id, :name, :position, :color])
    |> validate_required([:board_id, :name, :position])
    |> validate_length(:name, max: 60)
    |> validate_length(:color, max: 32)
  end
end
