defmodule WaxxWeb.Api.V1.BoardInviteController do
  @moduledoc """
  Board-scoped invite tokens. Owners can mint and revoke; the redemption
  URL is built using `WaxxWeb.PublicUrl` so self-hosted installs get a
  link that works on whatever origin the client used to reach us.

      GET    /api/v1/boards/:board_id/invites
      POST   /api/v1/boards/:board_id/invites   {role?, note?, expires_in_days?}
      DELETE /api/v1/boards/:board_id/invites/:id
  """

  use WaxxWeb, :controller

  alias Waxx.{Kanban, Repo}
  alias Waxx.Kanban.BoardInvite
  alias WaxxWeb.Api.V1.BoardJSON
  alias WaxxWeb.PublicUrl

  action_fallback WaxxWeb.Api.FallbackController

  def index(conn, %{"board_id" => board_id}) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_owner_board(board_id, user) do
      invites = Kanban.list_board_invites(board)
      json(conn, BoardJSON.board_invites_list(invites, PublicUrl.derive(conn)))
    end
  end

  def create(conn, %{"board_id" => board_id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_owner_board(board_id, user),
         attrs <- build_create_attrs(params),
         {:ok, invite} <- Kanban.create_board_invite(board, user, attrs) do
      conn
      |> put_status(:created)
      |> json(BoardJSON.board_invite_response(invite, PublicUrl.derive(conn)))
    end
  end

  def delete(conn, %{"board_id" => board_id, "id" => invite_id}) do
    user = conn.assigns.current_scope.user

    with {:ok, _board} <- fetch_owner_board(board_id, user),
         %BoardInvite{board_id: ^board_id} = invite <-
           Repo.get(BoardInvite, invite_id) || {:error, :not_found},
         {:ok, _} <- Kanban.revoke_board_invite(invite) do
      send_resp(conn, :no_content, "")
    else
      %BoardInvite{} -> {:error, :not_found}
      err -> err
    end
  end

  defp build_create_attrs(params) do
    base = params |> Map.take(["role", "note"])

    case params["expires_in_days"] do
      n when is_integer(n) and n > 0 ->
        Map.put(base, "expires_at", DateTime.utc_now() |> DateTime.add(n * 86_400, :second))

      _ ->
        base
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
