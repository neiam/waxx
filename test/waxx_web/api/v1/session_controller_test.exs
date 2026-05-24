defmodule WaxxWeb.Api.V1.SessionControllerTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Swoosh.TestAssertions

  alias Waxx.Accounts
  alias Waxx.Accounts.UserToken
  alias Waxx.Repo

  describe "POST /api/v1/sessions/request_magic_link" do
    test "204s and sends an email when the user exists", %{conn: conn} do
      user = confirmed_user_fixture()

      conn = post(conn, ~p"/api/v1/sessions/request_magic_link", %{email: user.email})

      assert response(conn, 204) == ""
      assert_email_sent(to: [{"", user.email}])
    end

    test "204s without sending email when the user is unknown", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/sessions/request_magic_link", %{email: "nobody@example.com"})

      assert response(conn, 204) == ""
      assert_no_email_sent()
    end

    test "validation_failed when email is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sessions/request_magic_link", %{})

      assert %{"error" => %{"code" => "validation_failed"}} = json_response(conn, 422)
    end
  end

  describe "POST /api/v1/sessions/redeem" do
    test "exchanges a magic-link token for an api_token and user", %{conn: conn} do
      user = confirmed_user_fixture()
      magic = magic_link_token_fixture(user)

      conn = post(conn, ~p"/api/v1/sessions/redeem", %{token: magic})

      assert %{"api_token" => api_token, "user" => returned_user} = json_response(conn, 200)
      assert is_binary(api_token)
      assert returned_user["id"] == user.id
      assert returned_user["email"] == user.email

      # The api_token should authenticate the user on subsequent requests.
      {fetched_user, token_id} = Accounts.fetch_user_by_api_token(api_token)
      assert fetched_user.id == user.id
      assert is_binary(token_id)
    end

    test "confirms an unconfirmed user on first redeem", %{conn: conn} do
      user = user_fixture()
      refute user.confirmed_at
      magic = magic_link_token_fixture(user)

      conn = post(conn, ~p"/api/v1/sessions/redeem", %{token: magic})

      assert %{"api_token" => _} = json_response(conn, 200)
      assert Repo.get!(Waxx.Accounts.User, user.id).confirmed_at
    end

    test "the magic-link token is single-use", %{conn: conn} do
      user = confirmed_user_fixture()
      magic = magic_link_token_fixture(user)

      _ = post(conn, ~p"/api/v1/sessions/redeem", %{token: magic})
      conn = post(build_conn(), ~p"/api/v1/sessions/redeem", %{token: magic})

      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end

    test "401 on a bogus token", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sessions/redeem", %{token: "definitely-not-valid"})

      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end
  end

  describe "DELETE /api/v1/sessions/current" do
    test "revokes the calling token and the same token can no longer authenticate", %{conn: conn} do
      user = confirmed_user_fixture()
      api_token = api_token_fixture(user)

      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> api_token)
        |> delete(~p"/api/v1/sessions/current")

      assert response(conn, 204) == ""
      assert is_nil(Accounts.fetch_user_by_api_token(api_token))

      # The DB row is gone.
      refute Repo.get_by(UserToken, user_id: user.id, context: "api")
    end

    test "401s without an Authorization header", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/sessions/current")
      assert %{"error" => %{"code" => "unauthenticated"}} = json_response(conn, 401)
    end
  end
end
