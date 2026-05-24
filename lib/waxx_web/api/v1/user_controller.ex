defmodule WaxxWeb.Api.V1.UserController do
  @moduledoc """
  Authenticated user endpoints.

      GET   /api/v1/users/me        → 200 {id, email, confirmed_at, preferences}

  `me` is the standard "is this bearer token still good?" probe — the
  Android pairing flow calls it right after writing the token to local
  storage to confirm the server actually accepts it before declaring the
  pair successful.
  """

  use WaxxWeb, :controller

  action_fallback WaxxWeb.Api.FallbackController

  def me(conn, _params) do
    user = conn.assigns.current_scope.user

    json(conn, %{
      id: user.id,
      email: user.email,
      confirmed_at: user.confirmed_at,
      preferences: user.preferences || %{}
    })
  end
end
