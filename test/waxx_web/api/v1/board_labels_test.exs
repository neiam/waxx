defmodule WaxxWeb.Api.V1.BoardLabelsTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias Waxx.{Kanban, Repo}
  alias Waxx.Kanban.BoardLabel

  defp setup_owner do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    %{user: user, board: board, token: api_token_fixture(user)}
  end

  defp setup_editor do
    owner = confirmed_user_fixture()
    editor = confirmed_user_fixture()
    board = board_fixture(owner)
    {:ok, _} = Kanban.add_member(board, editor, "editor")
    %{owner: owner, board: board, token: api_token_fixture(editor)}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "POST /api/v1/boards/:board_id/labels" do
    test "owner can add a label", %{conn: conn} do
      %{token: token, board: board} = setup_owner()

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/labels", %{name: "urgent", color: "#ff0000"})

      assert %{"label" => label} = json_response(conn, 201)
      assert label["name"] == "urgent"
      assert label["color"] == "#ff0000"
      assert Repo.get_by(BoardLabel, board_id: board.id, name: "urgent")
    end

    test "duplicate name on the same board is a 422", %{conn: conn} do
      %{token: token, board: board} = setup_owner()
      board_label_fixture(board, name: "urgent")

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/labels", %{name: "urgent"})

      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end

    test "non-owner gets 403", %{conn: conn} do
      %{token: token, board: board} = setup_editor()

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/labels", %{name: "nope"})

      assert json_response(conn, 403)
    end
  end

  describe "PATCH /api/v1/board_labels/:id" do
    test "owner can rename and recolor", %{conn: conn} do
      %{token: token, board: board} = setup_owner()
      label = board_label_fixture(board, name: "urgent")

      conn =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/board_labels/#{label.id}", %{name: "blocked", color: "#00ff00"})

      assert %{"label" => l} = json_response(conn, 200)
      assert l["name"] == "blocked"
      assert l["color"] == "#00ff00"
    end

    test "non-owner gets 403", %{conn: conn} do
      %{token: token, board: board} = setup_editor()
      label = board_label_fixture(board)

      conn = conn |> auth(token) |> patch(~p"/api/v1/board_labels/#{label.id}", %{name: "x"})
      assert json_response(conn, 403)
    end
  end

  describe "DELETE /api/v1/board_labels/:id" do
    test "owner can delete an unused label", %{conn: conn} do
      %{token: token, board: board} = setup_owner()
      label = board_label_fixture(board)

      conn = conn |> auth(token) |> delete(~p"/api/v1/board_labels/#{label.id}")
      assert response(conn, 204) == ""
      refute Repo.get(BoardLabel, label.id)
    end

    test "refuses to delete a label still attached to a card", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      label = board_label_fixture(board)
      card = card_fixture(board, user)
      {:ok, _} = Kanban.toggle_card_label(card, label)

      conn = conn |> auth(token) |> delete(~p"/api/v1/board_labels/#{label.id}")
      assert json_response(conn, 422)["error"]["code"] == "in_use"
      assert Repo.get(BoardLabel, label.id)
    end

    test "non-owner gets 403", %{conn: conn} do
      %{token: token, board: board} = setup_editor()
      label = board_label_fixture(board)

      conn = conn |> auth(token) |> delete(~p"/api/v1/board_labels/#{label.id}")
      assert json_response(conn, 403)
    end

    test "non-member gets 404", %{conn: conn} do
      %{board: board} = setup_owner()
      label = board_label_fixture(board)
      stranger = confirmed_user_fixture()

      conn =
        conn
        |> auth(api_token_fixture(stranger))
        |> delete(~p"/api/v1/board_labels/#{label.id}")

      assert json_response(conn, 404)
    end
  end
end
