defmodule Waxx.Kanban.BoardTransition do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.{Board, BoardStage}

  schema "board_transitions" do
    field :label, :string

    belongs_to :board, Board
    belongs_to :from_stage, BoardStage
    belongs_to :to_stage, BoardStage

    timestamps(type: :utc_datetime)
  end

  def changeset(transition, attrs) do
    transition
    |> cast(attrs, [:board_id, :from_stage_id, :to_stage_id, :label])
    |> validate_required([:board_id, :from_stage_id, :to_stage_id])
    |> validate_no_self_loop()
    |> unique_constraint([:from_stage_id, :to_stage_id], name: :b_transitions_from_to_index)
    |> check_constraint(:from_stage_id, name: :b_no_self_loop)
  end

  defp validate_no_self_loop(changeset) do
    from_id = get_field(changeset, :from_stage_id)
    to_id = get_field(changeset, :to_stage_id)

    if from_id && to_id && from_id == to_id do
      add_error(changeset, :to_stage_id, "must differ from the source stage")
    else
      changeset
    end
  end
end
