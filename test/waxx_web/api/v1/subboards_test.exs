defmodule WaxxWeb.Api.V1.SubboardsTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias Waxx.{Kanban, Repo}

  defp setup_owner do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    %{user: user, board: board, token: api_token_fixture(user)}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "POST /api/v1/boards/:id/subboards" do
    test "owner can create a subboard", %{conn: conn} do
      %{token: token, board: board} = setup_owner()

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/subboards", %{name: "Backend"})

      assert %{"subboard" => sb} = json_response(conn, 201)
      assert sb["name"] == "Backend"
      assert sb["position"] == 0
    end

    test "non-owner gets 403", %{conn: conn} do
      owner = confirmed_user_fixture()
      editor = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, editor, "editor")
      token = api_token_fixture(editor)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/subboards", %{name: "X"})

      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/v1/subboards/:id" do
    test "owner can delete; cards fall back to default row", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      {:ok, sb} = Kanban.create_subboard(board, %{"name" => "QA"})
      card = card_fixture(board, user)
      {:ok, _} = Kanban.set_card_subboard(card, sb)

      conn = conn |> auth(token) |> delete(~p"/api/v1/subboards/#{sb.id}")
      assert response(conn, 204) == ""

      refreshed = Repo.get!(Waxx.Kanban.Card, card.id)
      assert is_nil(refreshed.subboard_id)
    end

    test "non-owner gets 403", %{conn: conn} do
      owner = confirmed_user_fixture()
      editor = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, editor, "editor")
      {:ok, sb} = Kanban.create_subboard(board, %{"name" => "X"})
      token = api_token_fixture(editor)

      conn = conn |> auth(token) |> delete(~p"/api/v1/subboards/#{sb.id}")
      assert json_response(conn, 403)
    end
  end

  describe "POST /api/v1/cards/:id/move with subboard_id" do
    test "moves the card to the target subboard", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      {:ok, sb} = Kanban.create_subboard(board, %{"name" => "Backend"})
      card = card_fixture(board, user)
      [_todo, done] = board.stages

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/move", %{
          board_stage_id: done.id,
          subboard_id: sb.id
        })

      assert %{"card" => c} = json_response(conn, 200)
      assert c["board_stage_id"] == done.id
      assert c["subboard_id"] == sb.id
    end

    test "null subboard_id clears the assignment", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      {:ok, sb} = Kanban.create_subboard(board, %{"name" => "Backend"})
      card = card_fixture(board, user)
      {:ok, _} = Kanban.set_card_subboard(card, sb)
      [_todo, done] = board.stages

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/move", %{
          board_stage_id: done.id,
          subboard_id: nil
        })

      assert %{"card" => c} = json_response(conn, 200)
      assert c["subboard_id"] == nil
    end

    test "rejects a subboard from a different board", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      [_todo, done] = board.stages

      other = confirmed_user_fixture()
      other_board = board_fixture(other)
      {:ok, foreign_sb} = Kanban.create_subboard(other_board, %{"name" => "X"})

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/move", %{
          board_stage_id: done.id,
          subboard_id: foreign_sb.id
        })

      assert json_response(conn, 422)["error"]["code"] == "invalid_subboard"
    end
  end
end
