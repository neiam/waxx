defmodule WaxxWeb.Api.V1.BoardController do
  @moduledoc """
  Read-only board endpoints (Phase 2).

      GET /api/v1/boards                  — list of boards the caller has access to
      GET /api/v1/boards/:id              — board metadata + members
      GET /api/v1/boards/:id/workflow     — stages + transitions + labels +
                                            fields + subboards (static
                                            structure, refreshed on
                                            :workflow_changed)
      GET /api/v1/boards/:id/cards        — cards with assignees/labels/
                                            field values (refreshed on
                                            :cards_changed)
      GET /api/v1/boards/:id/history      — paginated activity log

  Membership is required on every board endpoint — `Kanban.get_board_for_user/2`
  returns nil when the caller isn't a member, which the controller turns
  into a `:not_found` (we don't leak the existence of boards the user
  can't see).
  """

  use WaxxWeb, :controller

  alias Waxx.{Kanban, Workflows}
  alias Waxx.Repo
  alias Waxx.Workflows.Template
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  def index(conn, _params) do
    user = conn.assigns.current_scope.user

    boards_with_roles =
      user
      |> Kanban.list_boards_for()
      |> Enum.map(fn b -> {b, Kanban.role_for(b.id, user)} end)

    json(conn, BoardJSON.boards_list(boards_with_roles))
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_board(id, user) do
      role = Kanban.role_for(board.id, user)
      members = Kanban.list_members(board.id)
      json(conn, BoardJSON.board(board, role, members))
    end
  end

  def workflow(conn, %{"board_id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, _board} <- fetch_board(id, user) do
      board = Kanban.get_board_with_workflow!(id, user)
      json(conn, BoardJSON.workflow(board))
    end
  end

  def cards(conn, %{"board_id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, _} <- fetch_board(id, user) do
      board = Kanban.get_board_with_workflow!(id, user)
      cards = Kanban.list_cards(board)
      json(conn, BoardJSON.cards(cards, Kanban.background_versions(board)))
    end
  end

  def history(conn, %{"board_id" => id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_board(id, user) do
      limit = parse_limit(params["limit"])
      activities = Kanban.list_activities(board, limit: limit)
      json(conn, BoardJSON.activities(activities))
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_scope.user

    with {:ok, template_id} <- fetch_str(params, "template_id"),
         %Template{} = template <-
           Workflows.get_template(template_id) || {:error, :not_found},
         attrs <- Map.take(params, ["name", "description", "archive_terminal_after_days"]),
         {:ok, board} <- Kanban.create_board_from_template(user, template, attrs) do
      role = Kanban.role_for(board.id, user)
      members = Kanban.list_members(board.id)

      conn
      |> put_status(:created)
      |> json(BoardJSON.board(board, role, members))
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_owner_board(id, user),
         attrs <-
           Map.take(params, ["name", "description", "archive_terminal_after_days"]),
         {:ok, updated} <- Kanban.update_board(board, attrs) do
      role = Kanban.role_for(updated.id, user)
      members = Kanban.list_members(updated.id)
      json(conn, BoardJSON.board(updated, role, members))
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_owner_board(id, user),
         {:ok, _} <- Kanban.delete_board(board) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_board(id, user) do
    case Kanban.get_board_for_user(id, user) do
      nil -> {:error, :not_found}
      board -> {:ok, Repo.preload(board, [])}
    end
  end

  defp fetch_owner_board(id, user) do
    with {:ok, board} <- fetch_board(id, user) do
      if Kanban.can_manage?(Kanban.role_for(board.id, user)),
        do: {:ok, board},
        else: {:error, :forbidden}
    end
  end

  defp parse_limit(nil), do: 200

  defp parse_limit(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} when n > 0 and n <= 500 -> n
      _ -> 200
    end
  end

  defp parse_limit(_), do: 200

  defp fetch_str(params, key) do
    case Map.get(params, key) do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, :validation_failed}
    end
  end
end
