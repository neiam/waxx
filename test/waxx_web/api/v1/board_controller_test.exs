defmodule WaxxWeb.Api.V1.BoardControllerTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  defp setup_member do
    user = confirmed_user_fixture()
    board = board_fixture(user, name: "My Board")
    token = api_token_fixture(user)
    %{user: user, board: board, token: token}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "GET /api/v1/boards" do
    test "lists the caller's boards with role", %{conn: conn} do
      %{token: token, board: board} = setup_member()
      conn = conn |> auth(token) |> get(~p"/api/v1/boards")
      assert %{"boards" => [b]} = json_response(conn, 200)
      assert b["id"] == board.id
      assert b["role"] == "owner"
      assert b["name"] == "My Board"
    end

    test "excludes boards the caller has no membership on", %{conn: conn} do
      %{token: token} = setup_member()
      other = confirmed_user_fixture()
      _other_board = board_fixture(other)

      conn = conn |> auth(token) |> get(~p"/api/v1/boards")
      assert %{"boards" => boards} = json_response(conn, 200)
      assert length(boards) == 1
    end

    test "401 without auth", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/boards")
      assert json_response(conn, 401)["error"]["code"] == "unauthenticated"
    end
  end

  describe "GET /api/v1/boards/:id" do
    test "returns board metadata + members for a member", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_member()

      conn = conn |> auth(token) |> get(~p"/api/v1/boards/#{board.id}")
      assert %{"board" => b} = json_response(conn, 200)
      assert b["id"] == board.id
      assert b["role"] == "owner"
      assert [m] = b["memberships"]
      assert m["user_id"] == user.id
      assert m["role"] == "owner"
      assert m["email"] == user.email
    end

    test "404 for boards the caller isn't a member of", %{conn: conn} do
      %{token: token} = setup_member()
      other = confirmed_user_fixture()
      other_board = board_fixture(other)

      conn = conn |> auth(token) |> get(~p"/api/v1/boards/#{other_board.id}")
      assert json_response(conn, 404)["error"]["code"] == "not_found"
    end
  end

  describe "GET /api/v1/boards/:id/workflow" do
    test "returns stages, transitions, labels, fields, subboards", %{conn: conn} do
      %{token: token, board: board} = setup_member()

      conn = conn |> auth(token) |> get(~p"/api/v1/boards/#{board.id}/workflow")
      assert %{"workflow" => wf} = json_response(conn, 200)

      assert wf["board_id"] == board.id
      assert length(wf["stages"]) == 2
      assert Enum.map(wf["stages"], & &1["name"]) == ["Todo", "Done"]
      assert [t] = wf["transitions"]
      assert t["label"] == "ship it"
      assert is_list(wf["labels"])
      assert is_list(wf["fields"])
      assert is_list(wf["subboards"])
    end

    test "404 for non-members", %{conn: conn} do
      %{token: token} = setup_member()
      other = confirmed_user_fixture()
      other_board = board_fixture(other)

      conn = conn |> auth(token) |> get(~p"/api/v1/boards/#{other_board.id}/workflow")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/boards/:id/cards" do
    test "returns cards with the expected shape", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_member()
      card = card_fixture(board, user, %{"title" => "Hello"})

      conn = conn |> auth(token) |> get(~p"/api/v1/boards/#{board.id}/cards")
      assert %{"cards" => [c]} = json_response(conn, 200)
      assert c["id"] == card.id
      assert c["title"] == "Hello"
      assert c["board_stage_id"]
      assert Map.has_key?(c, "assignee_ids")
      assert Map.has_key?(c, "label_ids")
      assert Map.has_key?(c, "field_values")
    end
  end

  describe "GET /api/v1/boards/:id/history" do
    test "returns activities newest first", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_member()
      _ = card_fixture(board, user, %{"title" => "A"})
      _ = card_fixture(board, user, %{"title" => "B"})

      conn = conn |> auth(token) |> get(~p"/api/v1/boards/#{board.id}/history")
      assert %{"activities" => acts} = json_response(conn, 200)
      assert length(acts) >= 2
      # Each activity carries action + actor + card_title.
      first = hd(acts)
      assert is_binary(first["action"])
      assert first["actor_id"] == user.id
    end

    test "respects ?limit", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_member()
      for i <- 1..5, do: card_fixture(board, user, %{"title" => "C#{i}"})

      conn = conn |> auth(token) |> get(~p"/api/v1/boards/#{board.id}/history?limit=2")
      assert %{"activities" => acts} = json_response(conn, 200)
      assert length(acts) == 2
    end
  end
end
