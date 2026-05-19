defmodule Waxx.Workflows.TemplateLabel do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Workflows.Template

  schema "workflow_template_labels" do
    field :name, :string
    field :color, :string

    belongs_to :template, Template

    timestamps(type: :utc_datetime)
  end

  def changeset(label, attrs) do
    label
    |> cast(attrs, [:template_id, :name, :color])
    |> validate_required([:template_id, :name])
    |> validate_length(:name, max: 60)
    |> validate_length(:color, max: 32)
    |> unique_constraint([:template_id, :name])
  end
end
