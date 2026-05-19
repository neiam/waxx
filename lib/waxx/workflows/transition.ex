defmodule Waxx.Workflows.Transition do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Workflows.{Template, Stage}

  schema "workflow_template_transitions" do
    field :label, :string

    belongs_to :template, Template
    belongs_to :from_stage, Stage
    belongs_to :to_stage, Stage

    timestamps(type: :utc_datetime)
  end

  def changeset(transition, attrs) do
    transition
    |> cast(attrs, [:template_id, :from_stage_id, :to_stage_id, :label])
    |> validate_required([:template_id, :from_stage_id, :to_stage_id])
    |> validate_no_self_loop()
    |> unique_constraint([:from_stage_id, :to_stage_id], name: :wt_transitions_from_to_index)
    |> check_constraint(:from_stage_id, name: :wt_no_self_loop)
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
