defmodule Waxx.Workflows.Template do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Workflows.{Stage, Transition, TemplateLabel, TemplateField}

  schema "workflow_templates" do
    field :name, :string
    field :description, :string

    belongs_to :created_by, User
    has_many :stages, Stage, foreign_key: :template_id, preload_order: [asc: :position]
    has_many :transitions, Transition, foreign_key: :template_id
    has_many :labels, TemplateLabel, foreign_key: :template_id, preload_order: [asc: :name]

    has_many :fields, TemplateField,
      foreign_key: :template_id,
      preload_order: [asc: :position, asc: :id]

    timestamps(type: :utc_datetime)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :created_by_id])
    |> validate_required([:name])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 500)
  end
end
