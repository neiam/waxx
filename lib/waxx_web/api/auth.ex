defmodule WaxxWeb.Api.Auth do
  @moduledoc """
  Bearer-token authentication plug for `/api/v1` routes.

  Looks for `Authorization: Bearer <token>` on the request, resolves it to
  a user via `Waxx.Accounts.fetch_user_by_api_token/1`, and assigns
  `:current_scope` so downstream controllers can use the same interface as
  the browser scope.

  On missing or invalid credentials the plug halts with a JSON 401 in the
  shared error shape (see `WaxxWeb.Api.ErrorJSON`).
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Waxx.Accounts
  alias Waxx.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    with [header] <- get_req_header(conn, "authorization"),
         {:ok, token} <- parse_bearer(header),
         {user, token_id} <- Accounts.fetch_user_by_api_token(token) do
      conn
      |> assign(:current_scope, Scope.for_user(user))
      |> assign(:current_api_token_id, token_id)
    else
      _ -> unauthenticated(conn)
    end
  end

  defp parse_bearer("Bearer " <> token) when byte_size(token) > 0, do: {:ok, token}
  defp parse_bearer("bearer " <> token) when byte_size(token) > 0, do: {:ok, token}
  defp parse_bearer(_), do: :error

  defp unauthenticated(conn) do
    body = %{error: %{code: "unauthenticated", message: "Missing or invalid token."}}

    conn
    |> put_status(:unauthorized)
    |> json(body)
    |> halt()
  end
end
