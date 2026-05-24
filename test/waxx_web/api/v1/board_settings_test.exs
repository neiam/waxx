defmodule WaxxWeb.Api.V1.BoardSettingsTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias Waxx.Kanban

  defp setup_owner do
    user = confirmed_user_fixture()
    board = board_fixture(user, name: "B")
    %{user: user, board: board, token: api_token_fixture(user)}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "PATCH /api/v1/boards/:id" do
    test "owner can rename + change archive days", %{conn: conn} do
      %{token: token, board: board} = setup_owner()

      conn =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/boards/#{board.id}", %{
          name: "Renamed",
          archive_terminal_after_days: 30
        })

      assert %{"board" => b} = json_response(conn, 200)
      assert b["name"] == "Renamed"
      assert b["archive_terminal_after_days"] == 30
    end

    test "editor (non-owner) gets 403", %{conn: conn} do
      owner = confirmed_user_fixture()
      editor = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, editor, "editor")
      token = api_token_fixture(editor)

      conn = conn |> auth(token) |> patch(~p"/api/v1/boards/#{board.id}", %{name: "nope"})
      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/v1/boards/:id" do
    test "owner can delete the board", %{conn: conn} do
      %{token: token, board: board} = setup_owner()

      conn = conn |> auth(token) |> delete(~p"/api/v1/boards/#{board.id}")
      assert response(conn, 204) == ""
      refute Waxx.Repo.get(Waxx.Kanban.Board, board.id)
    end

    test "editor gets 403", %{conn: conn} do
      owner = confirmed_user_fixture()
      editor = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, editor, "editor")
      token = api_token_fixture(editor)

      conn = conn |> auth(token) |> delete(~p"/api/v1/boards/#{board.id}")
      assert json_response(conn, 403)
    end
  end

  describe "PUT /api/v1/boards/:board_id/memberships/:user_id" do
    test "owner can promote an editor to owner", %{conn: conn} do
      %{token: token, board: board} = setup_owner()
      teammate = confirmed_user_fixture()
      {:ok, _} = Kanban.add_member(board, teammate, "editor")

      conn =
        conn
        |> auth(token)
        |> put(~p"/api/v1/boards/#{board.id}/memberships/#{teammate.id}", %{role: "owner"})

      assert %{"membership" => m} = json_response(conn, 200)
      assert m["role"] == "owner"
    end

    test "non-owner gets 403", %{conn: conn} do
      owner = confirmed_user_fixture()
      editor = confirmed_user_fixture()
      target = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, editor, "editor")
      {:ok, _} = Kanban.add_member(board, target, "viewer")
      token = api_token_fixture(editor)

      conn =
        conn
        |> auth(token)
        |> put(~p"/api/v1/boards/#{board.id}/memberships/#{target.id}", %{role: "editor"})

      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/v1/boards/:board_id/memberships/:user_id" do
    test "owner can remove a teammate", %{conn: conn} do
      %{token: token, board: board} = setup_owner()
      teammate = confirmed_user_fixture()
      {:ok, _} = Kanban.add_member(board, teammate, "editor")

      conn =
        conn
        |> auth(token)
        |> delete(~p"/api/v1/boards/#{board.id}/memberships/#{teammate.id}")

      assert response(conn, 204) == ""
      refute Kanban.role_for(board.id, teammate)
    end

    test "refuses to remove the last owner", %{conn: conn} do
      %{token: token, board: board, user: owner} = setup_owner()

      conn =
        conn
        |> auth(token)
        |> delete(~p"/api/v1/boards/#{board.id}/memberships/#{owner.id}")

      assert json_response(conn, 403)
      assert Kanban.role_for(board.id, owner) == "owner"
    end
  end

  describe "Board invites" do
    test "owner can list + create + revoke", %{conn: conn} do
      %{token: token, board: board} = setup_owner()

      list1 = conn |> auth(token) |> get(~p"/api/v1/boards/#{board.id}/invites")
      assert %{"invites" => []} = json_response(list1, 200)

      created =
        build_conn()
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/invites", %{role: "viewer", note: "QA folks"})

      assert %{"invite" => inv} = json_response(created, 201)
      assert inv["role"] == "viewer"
      assert inv["note"] == "QA folks"
      assert is_binary(inv["token"])
      assert String.contains?(inv["redemption_url"], "/b/" <> inv["token"])

      list2 = build_conn() |> auth(token) |> get(~p"/api/v1/boards/#{board.id}/invites")
      assert %{"invites" => [_]} = json_response(list2, 200)

      revoked =
        build_conn()
        |> auth(token)
        |> delete(~p"/api/v1/boards/#{board.id}/invites/#{inv["id"]}")

      assert response(revoked, 204) == ""
    end

    test "non-owner gets 403 on create", %{conn: conn} do
      owner = confirmed_user_fixture()
      editor = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, editor, "editor")
      token = api_token_fixture(editor)

      conn = conn |> auth(token) |> post(~p"/api/v1/boards/#{board.id}/invites", %{})
      assert json_response(conn, 403)
    end
  end

  describe "App invites" do
    test "any user can mint + revoke their own", %{conn: conn} do
      user = confirmed_user_fixture()
      token = api_token_fixture(user)

      created =
        conn
        |> auth(token)
        |> post(~p"/api/v1/users/invites", %{note: "onboarding"})

      assert %{"invite" => inv} = json_response(created, 201)
      assert inv["note"] == "onboarding"
      assert String.contains?(inv["redemption_url"], "/users/register?invite=")

      listing = build_conn() |> auth(token) |> get(~p"/api/v1/users/invites")
      assert %{"invites" => [_]} = json_response(listing, 200)

      revoked =
        build_conn() |> auth(token) |> delete(~p"/api/v1/users/invites/#{inv["id"]}")

      assert response(revoked, 204) == ""
    end

    test "can't revoke someone else's invite", %{conn: conn} do
      alice = confirmed_user_fixture()
      bob = confirmed_user_fixture()
      {:ok, invite} = Waxx.Accounts.create_invite(alice)
      bob_token = api_token_fixture(bob)

      conn = conn |> auth(bob_token) |> delete(~p"/api/v1/users/invites/#{invite.id}")
      assert json_response(conn, 404)
    end
  end
end
