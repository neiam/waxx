defmodule WaxxWeb.Api.V1.SubboardController do
  @moduledoc """
  Subboards = rows in the 2-D kanban grid. Owners only.

      POST   /api/v1/boards/:board_id/subboards   {name}
      DELETE /api/v1/subboards/:id

  Cards previously assigned to a deleted subboard fall back to the
  default row via the FK's `on_delete: :nilify_all`.
  """

  use WaxxWeb, :controller

  alias Waxx.{Kanban, Repo}
  alias Waxx.Kanban.Subboard
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  def create(conn, %{"board_id" => board_id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_owner_board(board_id, user),
         attrs <- Map.take(params, ["name"]),
         {:ok, sb} <- Kanban.create_subboard(board, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.subboard_response(sb))
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with %Subboard{board_id: board_id} = sb <-
           Repo.get(Subboard, id) || {:error, :not_found},
         {:ok, _board} <- fetch_owner_board(board_id, user),
         {:ok, _} <- Kanban.delete_subboard(sb) do
      send_resp(conn, :no_content, "")
    else
      {:error, _} = err -> err
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with %Subboard{board_id: board_id} = sb <-
           Repo.get(Subboard, id) || {:error, :not_found},
         {:ok, _board} <- fetch_owner_board(board_id, user),
         {:ok, position} <- require_position(params),
         {:ok, moved} <- Kanban.reorder_subboard(sb, position) do
      json(conn, BoardJSON.subboard_response(moved))
    else
      {:error, _} = err -> err
    end
  end

  defp require_position(%{"position" => p}) when is_integer(p) and p >= 0, do: {:ok, p}

  defp require_position(%{"position" => p}) when is_binary(p) do
    case Integer.parse(p) do
      {n, _} when n >= 0 -> {:ok, n}
      _ -> {:error, :validation_failed}
    end
  end

  defp require_position(_), do: {:error, :validation_failed}

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
