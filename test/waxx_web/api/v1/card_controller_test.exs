defmodule WaxxWeb.Api.V1.CardControllerTest do
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

  describe "POST /api/v1/boards/:id/cards" do
    test "creates a card", %{conn: conn} do
      %{token: token, board: board} = setup_owner()

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/cards", %{title: "Hello", description: "World"})

      assert %{"card" => c} = json_response(conn, 201)
      assert c["title"] == "Hello"
      assert c["description"] == "World"
      assert c["board_stage_id"]
    end

    test "validation_failed when title is missing", %{conn: conn} do
      %{token: token, board: board} = setup_owner()

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/cards", %{description: "no title"})

      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end

    test "404 when caller isn't a member", %{conn: conn} do
      %{token: token} = setup_owner()
      other = confirmed_user_fixture()
      other_board = board_fixture(other)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{other_board.id}/cards", %{title: "X"})

      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end

    test "403 when caller is a viewer", %{conn: conn} do
      owner = confirmed_user_fixture()
      viewer = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, viewer, "viewer")
      token = api_token_fixture(viewer)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/boards/#{board.id}/cards", %{title: "X"})

      assert json_response(conn, 403)["error"]["code"] == "forbidden"
    end
  end

  describe "PATCH /api/v1/cards/:id" do
    test "updates title + description", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user, %{"title" => "old"})

      conn =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/cards/#{card.id}", %{title: "new", description: "added"})

      assert %{"card" => c} = json_response(conn, 200)
      assert c["title"] == "new"
      assert c["description"] == "added"
    end

    test "404 for someone else's card", %{conn: conn} do
      owner = confirmed_user_fixture()
      board = board_fixture(owner)
      card = card_fixture(board, owner)

      stranger = confirmed_user_fixture()
      token = api_token_fixture(stranger)

      conn =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/cards/#{card.id}", %{title: "x"})

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/v1/cards/:id/move" do
    test "moves along a valid transition", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      [_todo, done] = board.stages

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/move", %{board_stage_id: done.id})

      assert %{"card" => c} = json_response(conn, 200)
      assert c["board_stage_id"] == done.id
    end

    test "422 invalid_transition for a backwards move", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      [todo, done] = board.stages

      # Step it forward first.
      _ = post(auth(conn, token), ~p"/api/v1/cards/#{card.id}/move", %{board_stage_id: done.id})

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/move", %{board_stage_id: todo.id})

      assert json_response(conn, 422)["error"]["code"] == "invalid_transition"
    end

    test "validation_failed without board_stage_id", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/move", %{})

      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end
  end

  describe "GET /api/v1/cards/:id" do
    # 1x1 transparent PNG.
    @png_data_url "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

    test "detail payload carries a background once one is set", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)

      # No background yet.
      conn1 = conn |> auth(token) |> get(~p"/api/v1/cards/#{card.id}")
      assert json_response(conn1, 200)["card"]["background"] == nil

      {:ok, _} = Kanban.set_card_background(card, @png_data_url)

      conn2 = build_conn() |> auth(token) |> get(~p"/api/v1/cards/#{card.id}")

      assert %{"content_type" => "image/png", "data" => data} =
               json_response(conn2, 200)["card"]["background"]

      # Round-trips as decodable base64.
      assert {:ok, _bytes} = Base.decode64(data)
    end
  end

  describe "DELETE /api/v1/cards/:id" do
    test "deletes the card", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)

      conn = conn |> auth(token) |> delete(~p"/api/v1/cards/#{card.id}")
      assert response(conn, 204) == ""

      refute Waxx.Repo.get(Waxx.Kanban.Card, card.id)
    end

    test "403 for a viewer", %{conn: conn} do
      owner = confirmed_user_fixture()
      viewer = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, viewer, "viewer")
      card = card_fixture(board, owner)
      token = api_token_fixture(viewer)

      conn = conn |> auth(token) |> delete(~p"/api/v1/cards/#{card.id}")
      assert json_response(conn, 403)
    end
  end
end
