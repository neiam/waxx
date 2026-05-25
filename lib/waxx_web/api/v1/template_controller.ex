defmodule WaxxWeb.Api.V1.TemplateController do
  @moduledoc """
  Workflow templates and their graph (stages, transitions, labels,
  fields). Org-wide — any authenticated user can read, create, and
  edit, matching the existing LiveView surface at `/workflow-templates`.

  Read:
      GET    /api/v1/workflow_templates
      GET    /api/v1/workflow_templates/:id        — full graph

  Templates:
      POST   /api/v1/workflow_templates                       {name, description?}
      PATCH  /api/v1/workflow_templates/:id                   {name?, description?}
      DELETE /api/v1/workflow_templates/:id

  Stages:
      POST   /api/v1/workflow_templates/:template_id/stages   {name, color?}
      PATCH  /api/v1/template_stages/:id                      {name?, color?}
      DELETE /api/v1/template_stages/:id

  Transitions:
      POST   /api/v1/workflow_templates/:template_id/transitions
                                                              {from_stage_id, to_stage_id, label?}
      DELETE /api/v1/template_transitions/:id

  Labels:
      POST   /api/v1/workflow_templates/:template_id/labels   {name, color?}
      DELETE /api/v1/template_labels/:id

  Fields:
      POST   /api/v1/workflow_templates/:template_id/fields   {name, kind, options?, show_on_card?}
      PATCH  /api/v1/template_fields/:id                      {name?, kind?, options?, show_on_card?}
      DELETE /api/v1/template_fields/:id

  All mutation paths propagate to existing boards using the template —
  the underlying `Waxx.Workflows` helpers handle the cascade and skip
  any board that has drifted (renamed entity, has cards in a stage
  that's being removed, etc.).
  """

  use WaxxWeb, :controller

  alias Waxx.{Repo, Workflows}
  alias Waxx.Workflows.{Stage, Transition, Template, TemplateField, TemplateLabel}
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  ## Templates ---------------------------------------------------------

  def index(conn, _params) do
    json(conn, BoardJSON.templates_list(Workflows.list_templates()))
  end

  def show(conn, %{"id" => id}) do
    case Workflows.get_template(id) do
      nil -> {:error, :not_found}
      template -> json(conn, BoardJSON.template_response(template))
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    attrs = Map.take(params, ["name", "description"])

    case Workflows.create_template(user, attrs) do
      {:ok, template} ->
        conn
        |> put_status(:created)
        |> json(BoardJSON.template_response(Workflows.get_template!(template.id)))

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def update(conn, %{"id" => id} = params) do
    with %Template{} = template <- Workflows.get_template(id) || {:error, :not_found},
         attrs <- Map.take(params, ["name", "description"]),
         {:ok, updated} <- Workflows.update_template(template, attrs) do
      json(conn, BoardJSON.template_response(Workflows.get_template!(updated.id)))
    end
  end

  def delete(conn, %{"id" => id}) do
    with %Template{} = template <- Workflows.get_template(id) || {:error, :not_found},
         {:ok, _} <- Workflows.delete_template(template) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Stages ------------------------------------------------------------

  def add_stage(conn, %{"template_id" => template_id} = params) do
    with %Template{} = template <- Workflows.get_template(template_id) || {:error, :not_found},
         attrs <- Map.take(params, ["name", "color"]),
         {:ok, stage} <- Workflows.add_stage(template, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.template_stage_response(stage))
    end
  end

  def update_stage(conn, %{"id" => id} = params) do
    with %Stage{} = stage <- Repo.get(Stage, id) || {:error, :not_found},
         attrs <- Map.take(params, ["name", "color"]),
         {:ok, updated} <- Workflows.update_stage(stage, attrs) do
      json(conn, BoardJSON.template_stage_response(updated))
    end
  end

  def delete_stage(conn, %{"id" => id}) do
    with %Stage{} = stage <- Repo.get(Stage, id) || {:error, :not_found},
         {:ok, _} <- Workflows.delete_stage(stage) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Transitions ------------------------------------------------------

  def add_transition(conn, %{"template_id" => template_id} = params) do
    with %Template{} = template <- Workflows.get_template(template_id) || {:error, :not_found},
         {:ok, from_id} <- fetch_str(params, "from_stage_id"),
         {:ok, to_id} <- fetch_str(params, "to_stage_id"),
         label <- params["label"],
         {:ok, transition} <- Workflows.add_transition(template, from_id, to_id, label) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.template_transition_response(transition))
    end
  end

  def delete_transition(conn, %{"id" => id}) do
    with %Transition{} = transition <- Repo.get(Transition, id) || {:error, :not_found},
         {:ok, _} <- Workflows.delete_transition(transition) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Labels -----------------------------------------------------------

  def add_label(conn, %{"template_id" => template_id} = params) do
    with %Template{} = template <- Workflows.get_template(template_id) || {:error, :not_found},
         attrs <- Map.take(params, ["name", "color"]),
         {:ok, label} <- Workflows.add_label(template, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.template_label_response(label))
    end
  end

  def delete_label(conn, %{"id" => id}) do
    with %TemplateLabel{} = label <- Repo.get(TemplateLabel, id) || {:error, :not_found},
         {:ok, _} <- Workflows.delete_label(label) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Fields -----------------------------------------------------------

  def add_field(conn, %{"template_id" => template_id} = params) do
    with %Template{} = template <- Workflows.get_template(template_id) || {:error, :not_found},
         attrs <- Map.take(params, ["name", "kind", "options", "show_on_card"]),
         {:ok, field} <- Workflows.add_field(template, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.template_field_response(field))
    end
  end

  def update_field(conn, %{"id" => id} = params) do
    with %TemplateField{} = field <- Repo.get(TemplateField, id) || {:error, :not_found},
         attrs <- Map.take(params, ["name", "kind", "options", "show_on_card"]),
         {:ok, updated} <- Workflows.update_field(field, attrs) do
      json(conn, BoardJSON.template_field_response(updated))
    end
  end

  def delete_field(conn, %{"id" => id}) do
    with %TemplateField{} = field <- Repo.get(TemplateField, id) || {:error, :not_found},
         {:ok, _} <- Workflows.delete_field(field) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Helpers ----------------------------------------------------------

  defp fetch_str(params, key) do
    case Map.get(params, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, :validation_failed}
    end
  end
end
