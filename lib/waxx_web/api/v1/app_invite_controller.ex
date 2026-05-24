defmodule WaxxWeb.Api.V1.AppInviteController do
  @moduledoc """
  App-level registration invites. Any authenticated user can mint one
  (matches the LiveView `/users/invites` UI which any logged-in user
  can reach).

      GET    /api/v1/users/invites
      POST   /api/v1/users/invites   {note?, expires_in_days?}
      DELETE /api/v1/users/invites/:id
  """

  use WaxxWeb, :controller

  alias Waxx.Accounts
  alias WaxxWeb.Api.V1.BoardJSON
  alias WaxxWeb.PublicUrl

  action_fallback WaxxWeb.Api.FallbackController

  def index(conn, _params) do
    user = conn.assigns.current_scope.user
    invites = Accounts.list_invites(user)
    json(conn, BoardJSON.app_invites_list(invites, PublicUrl.derive(conn)))
  end

  def create(conn, params) do
    user = conn.assigns.current_scope.user
    attrs = build_create_attrs(params)

    case Accounts.create_invite(user, attrs) do
      {:ok, invite} ->
        conn
        |> put_status(:created)
        |> json(BoardJSON.app_invite_response(invite, PublicUrl.derive(conn)))

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    case find_owned_invite(user, id) do
      nil -> {:error, :not_found}
      invite -> handle_revoke(conn, user, invite)
    end
  end

  defp handle_revoke(conn, user, invite) do
    case Accounts.revoke_invite(user, invite) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp find_owned_invite(user, id) do
    Enum.find(Accounts.list_invites(user), &(&1.id == id))
  end

  defp build_create_attrs(params) do
    base = params |> Map.take(["note"])

    case params["expires_in_days"] do
      n when is_integer(n) and n > 0 ->
        Map.put(base, "expires_at", DateTime.utc_now() |> DateTime.add(n * 86_400, :second))

      _ ->
        base
    end
  end
end
