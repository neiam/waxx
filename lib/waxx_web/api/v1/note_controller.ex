defmodule WaxxWeb.Api.V1.NoteController do
  @moduledoc """
  Card notes / todos.

      POST   /api/v1/cards/:card_id/notes   {body, kind?, board_stage_id?}
      PATCH  /api/v1/notes/:id              {body?, done?, kind?, board_stage_id?}
      DELETE /api/v1/notes/:id

  `board_stage_id` is optional on create — omitted means "attribute to
  the card's current stage" (what `Kanban.add_card_note` already does).
  Passing an explicit id lets the caller log a note against a different
  stage entirely; PATCH lets them re-assign an existing note. Both paths
  validate the stage belongs to the note's card's board so a crafted
  payload can't pin a note to some other board's stage.

  Same auth/role gating as `CardController`: the caller must have
  owner or editor membership on the note's card's board.
  """

  use WaxxWeb, :controller

  alias Waxx.{Kanban, Repo}
  alias Waxx.Kanban.{BoardStage, Card, CardNote}
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  def create(conn, %{"card_id" => card_id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(card_id, user),
         {:ok, attrs} <- build_create_attrs(card, params),
         {:ok, note} <- Kanban.add_card_note(card, user, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.note_response(note))
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, note} <- fetch_editable_note(id, user),
         {:ok, attrs} <- build_update_attrs(note, params) do
      case Kanban.update_card_note(note, attrs) do
        {:ok, updated} -> json(conn, BoardJSON.note_response(updated))
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp build_create_attrs(%Card{board_id: board_id}, params) do
    attrs = Map.take(params, ["body", "kind"])

    case params["board_stage_id"] do
      nil -> {:ok, attrs}
      "" -> {:ok, attrs}
      stage_id -> with_validated_stage(attrs, board_id, stage_id)
    end
  end

  defp build_update_attrs(%CardNote{card_id: card_id}, params) do
    attrs = Map.take(params, ["body", "done", "kind"])

    if Map.has_key?(params, "board_stage_id") do
      %Card{board_id: board_id} = Repo.get!(Card, card_id)

      case params["board_stage_id"] do
        nil -> {:error, :validation_failed}
        "" -> {:error, :validation_failed}
        stage_id -> with_validated_stage(attrs, board_id, stage_id)
      end
    else
      {:ok, attrs}
    end
  end

  defp with_validated_stage(attrs, board_id, stage_id) do
    case Repo.get(BoardStage, stage_id) do
      %BoardStage{board_id: ^board_id} -> {:ok, Map.put(attrs, "board_stage_id", stage_id)}
      _ -> {:error, :validation_failed}
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, note} <- fetch_editable_note(id, user),
         {:ok, _} <- Kanban.delete_card_note(note) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_editable_card(card_id, user) do
    case Repo.get(Card, card_id) do
      nil ->
        {:error, :not_found}

      %Card{board_id: board_id} = card ->
        role = Kanban.role_for(board_id, user)

        cond do
          is_nil(role) -> {:error, :not_found}
          not Kanban.can_edit?(role) -> {:error, :forbidden}
          true -> {:ok, card}
        end
    end
  end

  defp fetch_editable_note(note_id, user) do
    case Repo.get(CardNote, note_id) do
      nil ->
        {:error, :not_found}

      %CardNote{card_id: card_id} = note ->
        case fetch_editable_card(card_id, user) do
          {:ok, _} -> {:ok, note}
          err -> err
        end
    end
  end
end
