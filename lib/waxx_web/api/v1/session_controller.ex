defmodule WaxxWeb.Api.V1.SessionController do
  @moduledoc """
  Session lifecycle for native clients.

      POST   /api/v1/sessions/request_magic_link  {email}   → 204
      POST   /api/v1/sessions/redeem              {token}   → 200 {api_token, user}
      DELETE /api/v1/sessions/current                       → 204

  `request_magic_link` always returns 204 regardless of whether the email
  matches a known user — this avoids leaking account existence. The
  magic-link URL embedded in the email points at `/m/:token` so the
  Android App Link intent filter can intercept it before a browser opens.
  """

  use WaxxWeb, :controller

  alias Waxx.Accounts

  action_fallback WaxxWeb.Api.FallbackController

  def request_magic_link(conn, %{"email" => email}) when is_binary(email) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(user, &url(~p"/m/#{&1}"))
    end

    send_resp(conn, :no_content, "")
  end

  def request_magic_link(_conn, _params), do: {:error, :validation_failed}

  def redeem(conn, %{"token" => token}) when is_binary(token) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _tokens_to_disconnect}} ->
        api_token = Accounts.create_api_token(user)

        conn
        |> put_status(:ok)
        |> json(%{
          api_token: api_token,
          user: %{id: user.id, email: user.email}
        })

      _ ->
        {:error, :unauthenticated}
    end
  end

  def redeem(_conn, _params), do: {:error, :validation_failed}

  def delete(conn, _params) do
    user = conn.assigns.current_scope.user
    token_id = conn.assigns[:current_api_token_id]

    if token_id, do: Accounts.delete_api_token(user, token_id)

    send_resp(conn, :no_content, "")
  end
end
