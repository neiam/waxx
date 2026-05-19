defmodule Waxx.Workflows.TemplateField do
  @moduledoc """
  A custom field defined on a template. Cloned into per-board `BoardField`
  rows when a board is created from the template; further template edits
  propagate by name.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Workflows.Template

  @kinds ~w(text date datetime select)

  schema "workflow_template_fields" do
    field :name, :string
    field :kind, :string
    field :options, {:array, :string}
    field :show_on_card, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :template, Template

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(field, attrs) do
    field
    |> cast(attrs, [:template_id, :name, :kind, :options, :show_on_card, :position])
    |> validate_required([:template_id, :name, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:name, max: 60)
    |> normalize_options()
    |> validate_options_for_select()
    |> unique_constraint([:template_id, :name])
    |> check_constraint(:kind, name: :wtf_kind_check)
  end

  defp normalize_options(changeset) do
    case get_change(changeset, :options) do
      nil ->
        changeset

      list when is_list(list) ->
        cleaned =
          list
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.uniq()

        put_change(changeset, :options, cleaned)
    end
  end

  defp validate_options_for_select(changeset) do
    case get_field(changeset, :kind) do
      "select" ->
        opts = get_field(changeset, :options) || []

        if opts == [],
          do: add_error(changeset, :options, "select fields need at least one option"),
          else: changeset

      _ ->
        changeset
    end
  end
end
