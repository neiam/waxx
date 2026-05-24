defmodule WaxxWeb.Api.V1.MembershipController do
  @moduledoc """
  Board membership management. Owners only.

      PUT    /api/v1/boards/:board_id/memberships/:user_id   {role}
      DELETE /api/v1/boards/:board_id/memberships/:user_id

  We expose memberships by `user_id` rather than the membership row id —
  user_id is what the caller already has from `board.memberships` on the
  board show endpoint, and it makes the URL idempotent (one membership
  per (board, user) by table uniqueness).
  """

  use WaxxWeb, :controller

  import Ecto.Query

  alias Waxx.{Kanban, Repo}
  alias Waxx.Kanban.Membership
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  def update(conn, %{"board_id" => board_id, "user_id" => user_id, "role" => role}) do
    actor = conn.assigns.current_scope.user

    with {:ok, _board} <- fetch_owner_board(board_id, actor),
         {:ok, membership} <- fetch_membership(board_id, user_id),
         {:ok, updated} <- Kanban.update_member_role(membership, role) do
      json(conn, BoardJSON.membership_response(Repo.preload(updated, :user)))
    end
  end

  def update(_conn, _params), do: {:error, :validation_failed}

  def delete(conn, %{"board_id" => board_id, "user_id" => user_id}) do
    actor = conn.assigns.current_scope.user

    with {:ok, _board} <- fetch_owner_board(board_id, actor),
         {:ok, membership} <- fetch_membership(board_id, user_id),
         _ <- guard_last_owner(membership) || throw_forbidden(),
         {:ok, _} <- Kanban.remove_member(membership) do
      send_resp(conn, :no_content, "")
    end
  catch
    :forbidden -> {:error, :forbidden}
  end

  defp guard_last_owner(%Membership{role: "owner", board_id: board_id} = m) do
    other_owners =
      Repo.aggregate(
        from(o in Membership,
          where: o.board_id == ^board_id and o.role == "owner" and o.id != ^m.id
        ),
        :count
      )

    other_owners > 0
  end

  defp guard_last_owner(_), do: true

  defp throw_forbidden, do: throw(:forbidden)

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

  defp fetch_membership(board_id, user_id) do
    case Repo.get_by(Membership, board_id: board_id, user_id: user_id) do
      nil -> {:error, :not_found}
      m -> {:ok, m}
    end
  end
end
