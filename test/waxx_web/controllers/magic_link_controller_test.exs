defmodule WaxxWeb.MagicLinkControllerTest do
  use WaxxWeb.ConnCase, async: true

  test "GET /m/:token redirects to the web magic-link confirmation page", %{conn: conn} do
    conn = get(conn, ~p"/m/abc123")
    assert redirected_to(conn) == "/users/log-in/abc123"
  end
end
