defmodule WaxxWeb.Api.V1.BoardLabelController do
  @moduledoc """
  Board-level label management. Owners only. Lets a board grow its own
  labels beyond the set cloned from its template.

      POST   /api/v1/boards/:board_id/labels   {name, color}
      PATCH  /api/v1/board_labels/:id          {name, color}
      DELETE /api/v1/board_labels/:id

  Deletion is refused (422 `in_use`) while any card still wears the
  label — same rule as template-label removal propagation.
  """

  use WaxxWeb, :controller

  alias Waxx.{Kanban, Repo}
  alias Waxx.Kanban.BoardLabel
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  def create(conn, %{"board_id" => board_id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_owner_board(board_id, user),
         attrs <- Map.take(params, ["name", "color"]),
         {:ok, label} <- Kanban.create_board_label(board, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.board_label_response(label))
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with %BoardLabel{board_id: board_id} = label <-
           Repo.get(BoardLabel, id) || {:error, :not_found},
         {:ok, _board} <- fetch_owner_board(board_id, user),
         attrs <- Map.take(params, ["name", "color"]),
         {:ok, updated} <- Kanban.update_board_label(label, attrs) do
      json(conn, BoardJSON.board_label_response(updated))
    else
      {:error, _} = err -> err
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with %BoardLabel{board_id: board_id} = label <-
           Repo.get(BoardLabel, id) || {:error, :not_found},
         {:ok, _board} <- fetch_owner_board(board_id, user),
         {:ok, _} <- Kanban.delete_board_label(label) do
      send_resp(conn, :no_content, "")
    else
      {:error, _} = err -> err
    end
  end

  defp fetch_owner_board(board_id, user) do
    case Kanban.get_board_for_user(board_id, user) do
      nil ->
        {:error, :not_found}

      board ->
        if Kanban.can_manage?(Kanban.role_for(board.id, user)),
          do: {:ok, board},
          else: {:error, :forbidden}
    end
  end
end
