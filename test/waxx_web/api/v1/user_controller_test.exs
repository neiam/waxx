defmodule WaxxWeb.Api.V1.UserControllerTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures

  describe "GET /api/v1/users/me" do
    test "returns the user's identity when the bearer is valid", %{conn: conn} do
      user = confirmed_user_fixture()
      token = api_token_fixture(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> token)
        |> get(~p"/api/v1/users/me")

      assert %{
               "id" => id,
               "email" => email,
               "confirmed_at" => _,
               "preferences" => %{}
             } = json_response(conn, 200)

      assert id == user.id
      assert email == user.email
    end

    test "401 without an Authorization header", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/users/me")
      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end

    test "401 with a bogus token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer not-real")
        |> get(~p"/api/v1/users/me")

      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end
  end
end
