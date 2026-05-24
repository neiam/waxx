defmodule WaxxWeb.Api.V1.NoteController do
  @moduledoc """
  Card notes (Phase 4b).

      POST   /api/v1/cards/:card_id/notes   {body, kind?}
      PATCH  /api/v1/notes/:id              {body?, done?}
      DELETE /api/v1/notes/:id

  Same auth/role gating as `CardController`: the caller must have
  owner or editor membership on the note's card's board.
  """

  use WaxxWeb, :controller

  alias Waxx.{Kanban, Repo}
  alias Waxx.Kanban.{Card, CardNote}
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  def create(conn, %{"card_id" => card_id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(card_id, user),
         attrs <- Map.take(params, ["body", "kind"]),
         {:ok, note} <- Kanban.add_card_note(card, user, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.note_response(note))
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, note} <- fetch_editable_note(id, user) do
      attrs = Map.take(params, ["body", "done"])

      case Kanban.update_card_note(note, attrs) do
        {:ok, updated} -> json(conn, BoardJSON.note_response(updated))
        {:error, changeset} -> {:error, changeset}
      end
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
