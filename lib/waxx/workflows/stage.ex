defmodule Waxx.Workflows.Stage do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Workflows.Template

  schema "workflow_template_stages" do
    field :name, :string
    field :position, :integer
    field :color, :string

    belongs_to :template, Template

    timestamps(type: :utc_datetime)
  end

  def changeset(stage, attrs) do
    stage
    |> cast(attrs, [:template_id, :name, :position, :color])
    |> validate_required([:template_id, :name, :position])
    |> validate_length(:name, max: 60)
    |> validate_length(:color, max: 32)
  end
end
