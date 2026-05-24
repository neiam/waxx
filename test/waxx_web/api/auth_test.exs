defmodule WaxxWeb.Api.AuthTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures

  alias WaxxWeb.Api.Auth

  describe "Auth plug" do
    test "401s when no Authorization header is sent", %{conn: conn} do
      conn = conn |> put_req_header("accept", "application/json") |> Auth.call([])

      assert conn.halted
      assert conn.status == 401
      assert %{"error" => %{"code" => "unauthenticated"}} = json_body(conn)
    end

    test "401s when the header is not Bearer", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic dXNlcjpwYXNz")
        |> Auth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "401s on a malformed token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-a-real-token")
        |> Auth.call([])

      assert conn.halted
      assert conn.status == 401
    end

    test "assigns current_scope and current_api_token_id on a valid token", %{conn: conn} do
      user = confirmed_user_fixture()
      token = api_token_fixture(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> Auth.call([])

      refute conn.halted
      assert conn.assigns.current_scope.user.id == user.id
      assert is_binary(conn.assigns.current_api_token_id)
    end
  end

  defp json_body(conn) do
    {:ok, decoded} = Jason.decode(conn.resp_body)
    decoded
  end
end
