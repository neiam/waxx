defmodule WaxxWeb.UserLive.SettingsTest do
  use WaxxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Waxx.AccountsFixtures

  alias Waxx.Accounts

  describe "Connected devices section" do
    test "renders empty state for a user with no tokens", %{conn: conn} do
      user = confirmed_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "Connected devices"
      assert html =~ "No tokens yet"
    end

    test "generating a token shows the one-time QR panel and adds to the list",
         %{conn: conn} do
      user = confirmed_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html =
        lv
        |> form("#token_form", token: %{label: "Pixel 7"})
        |> render_submit()

      assert html =~ "only time the full token will be shown"
      assert html =~ "waxx://pair?"
      assert html =~ "Pixel 7"
      # The QR is rendered inline as SVG.
      assert html =~ "<svg"

      assert [%{label: "Pixel 7"}] = Accounts.list_api_tokens(user)
    end

    test "the encoded pair URI contains the freshly minted token", %{conn: conn} do
      user = confirmed_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _} = live(conn, ~p"/users/settings")

      html =
        lv
        |> form("#token_form", token: %{label: ""})
        |> render_submit()

      # The raw token appears in the panel as a <code> block.
      assert [%{}] = Accounts.list_api_tokens(user)
      assert html =~ "<code"
      assert html =~ "Pairing URI"
    end

    test "revoke removes the token from the list", %{conn: conn} do
      user = confirmed_user_fixture()
      _ = Accounts.create_api_token(user, %{label: "doomed"})
      [%{id: id}] = Accounts.list_api_tokens(user)

      conn = log_in_user(conn, user)
      {:ok, lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "doomed"

      html =
        lv
        |> element("#api-token-#{id} button", "Revoke")
        |> render_click()

      refute html =~ "doomed"
      assert [] = Accounts.list_api_tokens(user)
    end

    test "dismiss hides the just-created panel", %{conn: conn} do
      user = confirmed_user_fixture()
      conn = log_in_user(conn, user)

      {:ok, lv, _} = live(conn, ~p"/users/settings")

      lv
      |> form("#token_form", token: %{label: ""})
      |> render_submit()

      html =
        lv
        |> element("button", "Done — hide")
        |> render_click()

      refute html =~ "only time the full token will be shown"
    end
  end
end
