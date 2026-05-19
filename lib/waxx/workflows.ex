defmodule Waxx.Workflows do
  @moduledoc """
  Org-wide reusable workflow templates: a named graph of stages (nodes) and
  transitions (directed edges). Boards are created from a template by
  cloning the graph into per-board tables in `Waxx.Kanban`.
  """

  import Ecto.Query, warn: false
  alias Waxx.Repo
  alias Waxx.Accounts.User
  alias Waxx.Workflows.{Template, Stage, Transition, TemplateLabel, TemplateField}

  ## Templates -----------------------------------------------------------

  @doc "Lists all templates, newest first, with stages + transitions preloaded."
  def list_templates do
    from(t in Template, order_by: [desc: t.inserted_at])
    |> Repo.all()
    |> Repo.preload([:stages, transitions: [:from_stage, :to_stage]])
  end

  @doc "Gets a template with stages, transitions, labels, and fields preloaded, or nil."
  def get_template(id) do
    case Repo.get(Template, id) do
      nil ->
        nil

      template ->
        Repo.preload(template, [
          :stages,
          :labels,
          :fields,
          transitions: [:from_stage, :to_stage]
        ])
    end
  end

  def get_template!(id) do
    Template
    |> Repo.get!(id)
    |> Repo.preload([:stages, :labels, :fields, transitions: [:from_stage, :to_stage]])
  end

  def change_template(%Template{} = template, attrs \\ %{}) do
    Template.changeset(template, attrs)
  end

  def create_template(%User{id: user_id}, attrs) do
    attrs = Map.put(stringify_keys(attrs), "created_by_id", user_id)

    %Template{}
    |> Template.changeset(attrs)
    |> Repo.insert()
  end

  def update_template(%Template{} = template, attrs) do
    template
    |> Template.changeset(attrs)
    |> Repo.update()
  end

  def delete_template(%Template{} = template), do: Repo.delete(template)

  ## Stages --------------------------------------------------------------

  @doc """
  Appends a stage to a template at the next available position. Also
  propagates the new stage to every board currently created from this
  template — see `Waxx.Kanban.propagate_template_stage_added/4`.
  """
  def add_stage(%Template{} = template, attrs) do
    next_position =
      Repo.one(from(s in Stage, where: s.template_id == ^template.id, select: max(s.position)))

    next = if is_nil(next_position), do: 0, else: next_position + 1

    result =
      %Stage{}
      |> Stage.changeset(
        stringify_keys(attrs)
        |> Map.put("template_id", template.id)
        |> Map.put_new("position", next)
      )
      |> Repo.insert()

    case result do
      {:ok, stage} ->
        Waxx.Kanban.propagate_template_stage_added(
          template.id,
          stage.name,
          stage.position,
          stage.color
        )

      _ ->
        :ok
    end

    result
  end

  @doc """
  Updates a template stage and, when the `name` changes, propagates the
  rename to all boards using this template — see
  `Waxx.Kanban.propagate_template_stage_renamed/3`.
  """
  def update_stage(%Stage{} = stage, attrs) do
    old_name = stage.name

    case stage |> Stage.changeset(attrs) |> Repo.update() do
      {:ok, updated} = result ->
        if updated.name != old_name do
          Waxx.Kanban.propagate_template_stage_renamed(
            updated.template_id,
            old_name,
            updated.name
          )
        end

        result

      other ->
        other
    end
  end

  @doc """
  Deletes a template stage and propagates the removal to boards that use
  this template. A board only loses its matching stage when that stage
  has no cards — otherwise the board keeps the column rather than lose
  data. See `Waxx.Kanban.propagate_template_stage_removed/2`.
  """
  def delete_stage(%Stage{} = stage) do
    case Repo.delete(stage) do
      {:ok, _} = result ->
        Waxx.Kanban.propagate_template_stage_removed(stage.template_id, stage.name)
        result

      other ->
        other
    end
  end

  ## Transitions ---------------------------------------------------------

  @doc """
  Adds a directed transition between two template stages. Also propagates
  the equivalent transition to every board currently created from this
  template, matching stages by name.
  """
  def add_transition(%Template{} = template, from_stage_id, to_stage_id, label \\ nil) do
    result =
      %Transition{}
      |> Transition.changeset(%{
        template_id: template.id,
        from_stage_id: from_stage_id,
        to_stage_id: to_stage_id,
        label: label
      })
      |> Repo.insert()

    case result do
      {:ok, _} ->
        from_name = stage_name(from_stage_id)
        to_name = stage_name(to_stage_id)

        if from_name && to_name do
          Waxx.Kanban.propagate_template_transition_added(
            template.id,
            from_name,
            to_name,
            label
          )
        end

      _ ->
        :ok
    end

    result
  end

  @doc """
  Removes a transition. Propagates the removal to all boards using this
  template (matched by stage names).
  """
  def delete_transition(%Transition{} = transition) do
    transition = Repo.preload(transition, [:from_stage, :to_stage])
    from_name = transition.from_stage && transition.from_stage.name
    to_name = transition.to_stage && transition.to_stage.name
    template_id = transition.template_id

    case Repo.delete(transition) do
      {:ok, _} = result ->
        if from_name && to_name do
          Waxx.Kanban.propagate_template_transition_removed(template_id, from_name, to_name)
        end

        result

      other ->
        other
    end
  end

  defp stage_name(id) do
    Repo.one(from(s in Stage, where: s.id == ^id, select: s.name))
  end

  ## Labels --------------------------------------------------------------

  @doc """
  Adds a label to a template. Propagates the label to every board
  currently using this template (idempotent: existing board labels with
  the same name are left untouched).
  """
  def add_label(%Template{} = template, attrs) do
    result =
      %TemplateLabel{}
      |> TemplateLabel.changeset(
        stringify_keys(attrs)
        |> Map.put("template_id", template.id)
      )
      |> Repo.insert()

    case result do
      {:ok, label} ->
        Waxx.Kanban.propagate_template_label_added(template.id, label.name, label.color)

      _ ->
        :ok
    end

    result
  end

  @doc """
  Deletes a template label and propagates the removal to boards that use
  this template. A board only loses the matching board label when no
  cards reference it (the propagation in `Waxx.Kanban` enforces this).
  """
  def delete_label(%TemplateLabel{} = label) do
    case Repo.delete(label) do
      {:ok, _} = result ->
        Waxx.Kanban.propagate_template_label_removed(label.template_id, label.name)
        result

      other ->
        other
    end
  end

  ## Fields --------------------------------------------------------------

  @doc """
  Adds a custom field to a template. Propagates to every board using
  this template (matched by name).
  """
  def add_field(%Template{} = template, attrs) do
    next_position =
      Repo.one(
        from(f in TemplateField,
          where: f.template_id == ^template.id,
          select: max(f.position)
        )
      )

    next = if is_nil(next_position), do: 0, else: next_position + 1

    result =
      %TemplateField{}
      |> TemplateField.changeset(
        stringify_keys(attrs)
        |> Map.put("template_id", template.id)
        |> Map.put_new("position", next)
      )
      |> Repo.insert()

    case result do
      {:ok, f} ->
        Waxx.Kanban.propagate_template_field_added(template.id, %{
          name: f.name,
          kind: f.kind,
          options: f.options,
          show_on_card: f.show_on_card,
          position: f.position
        })

      _ ->
        :ok
    end

    result
  end

  @doc """
  Updates a template field and propagates kind/options/show_on_card/position
  changes to the matching board fields. Rename is not supported through
  this path — delete and re-add to rename.
  """
  def update_field(%TemplateField{} = field, attrs) do
    result =
      field
      |> TemplateField.changeset(stringify_keys(attrs))
      |> Repo.update()

    case result do
      {:ok, f} ->
        Waxx.Kanban.propagate_template_field_updated(f.template_id, f.name, %{
          kind: f.kind,
          options: f.options,
          show_on_card: f.show_on_card,
          position: f.position
        })

      _ ->
        :ok
    end

    result
  end

  @doc """
  Deletes a template field. The matching board field is removed only on
  boards where no card has stored a value for it
  (`Waxx.Kanban.propagate_template_field_removed/2`).
  """
  def delete_field(%TemplateField{} = field) do
    case Repo.delete(field) do
      {:ok, _} = result ->
        Waxx.Kanban.propagate_template_field_removed(field.template_id, field.name)
        result

      other ->
        other
    end
  end

  ## Helpers -------------------------------------------------------------

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
