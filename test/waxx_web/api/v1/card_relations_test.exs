defmodule WaxxWeb.Api.V1.CardRelationsTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias Waxx.Kanban

  defp setup_owner do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    %{user: user, board: board, token: api_token_fixture(user)}
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  describe "GET /api/v1/cards/:id" do
    test "returns the card with notes preloaded", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      {:ok, _} = Kanban.add_card_note(card, user, %{"body" => "first note"})

      conn = conn |> auth(token) |> get(~p"/api/v1/cards/#{card.id}")
      assert %{"card" => c} = json_response(conn, 200)
      assert c["id"] == card.id
      assert [%{"body" => "first note"}] = c["notes"]
    end

    test "404 for non-members", %{conn: conn} do
      %{token: token} = setup_owner()
      stranger = confirmed_user_fixture()
      other_board = board_fixture(stranger)
      card = card_fixture(other_board, stranger)

      conn = conn |> auth(token) |> get(~p"/api/v1/cards/#{card.id}")
      assert json_response(conn, 404)
    end
  end

  describe "POST /api/v1/cards/:id/labels/:label_id/toggle" do
    test "toggles the label on, then off", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      label = board_label_fixture(board, name: "Bug")

      conn1 =
        conn |> auth(token) |> post(~p"/api/v1/cards/#{card.id}/labels/#{label.id}/toggle")

      assert %{"card" => c1} = json_response(conn1, 200)
      assert label.id in c1["label_ids"]

      conn2 =
        build_conn()
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/labels/#{label.id}/toggle")

      assert %{"card" => c2} = json_response(conn2, 200)
      refute label.id in c2["label_ids"]
    end

    test "404 when the label doesn't exist", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      fake = Ecto.UUID.generate()

      conn = conn |> auth(token) |> post(~p"/api/v1/cards/#{card.id}/labels/#{fake}/toggle")
      assert json_response(conn, 404)
    end

    test "404 when the label belongs to a different board", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      other = confirmed_user_fixture()
      other_board = board_fixture(other)
      foreign_label = board_label_fixture(other_board)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/labels/#{foreign_label.id}/toggle")

      # invalid_label maps to :not_found per the controller.
      assert json_response(conn, 404)
    end
  end

  describe "PUT /api/v1/cards/:id/fields/:field_id" do
    test "sets a text field value", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      field = board_field_fixture(board, name: "owner", kind: "text")

      conn =
        conn
        |> auth(token)
        |> put(~p"/api/v1/cards/#{card.id}/fields/#{field.id}", %{value: "alice"})

      assert %{"card" => c} = json_response(conn, 200)
      assert Enum.any?(c["field_values"], &(&1["board_field_id"] == field.id))
    end

    test "empty value clears the field", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      field = board_field_fixture(board, name: "owner", kind: "text")

      _ =
        post(
          auth(conn, token),
          ~p"/api/v1/cards/#{card.id}/labels/#{Ecto.UUID.generate()}/toggle"
        )

      _ =
        put(auth(conn, token), ~p"/api/v1/cards/#{card.id}/fields/#{field.id}", %{value: "x"})

      conn =
        conn
        |> auth(token)
        |> put(~p"/api/v1/cards/#{card.id}/fields/#{field.id}", %{value: ""})

      assert %{"card" => c} = json_response(conn, 200)
      assert Enum.all?(c["field_values"], &(&1["board_field_id"] != field.id))
    end

    test "select with an unknown option is validation_failed", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      field = board_field_fixture(board, name: "size", kind: "select", options: ["s", "m", "l"])

      conn =
        conn
        |> auth(token)
        |> put(~p"/api/v1/cards/#{card.id}/fields/#{field.id}", %{value: "xxl"})

      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end
  end

  describe "assignees" do
    test "owner can assign another member", %{conn: conn} do
      %{token: token, board: board, user: owner} = setup_owner()
      teammate = confirmed_user_fixture()
      {:ok, _} = Kanban.add_member(board, teammate, "editor")
      card = card_fixture(board, owner)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/assignees", %{user_id: teammate.id})

      assert %{"card" => c} = json_response(conn, 200)
      assert teammate.id in c["assignee_ids"]
    end

    test "rejects assigning a non-member as forbidden", %{conn: conn} do
      %{token: token, board: board, user: owner} = setup_owner()
      outsider = confirmed_user_fixture()
      card = card_fixture(board, owner)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/assignees", %{user_id: outsider.id})

      assert json_response(conn, 403)
    end

    test "remove drops the assignment", %{conn: conn} do
      %{token: token, board: board, user: owner} = setup_owner()
      teammate = confirmed_user_fixture()
      {:ok, _} = Kanban.add_member(board, teammate, "editor")
      card = card_fixture(board, owner)
      {:ok, _} = Kanban.assign_user(card, teammate)

      conn =
        conn
        |> auth(token)
        |> delete(~p"/api/v1/cards/#{card.id}/assignees/#{teammate.id}")

      assert %{"card" => c} = json_response(conn, 200)
      refute teammate.id in c["assignee_ids"]
    end
  end

  describe "notes" do
    test "create + delete a note", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)

      created =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/notes", %{body: "Standup talked about this"})

      assert %{"note" => n} = json_response(created, 201)
      assert n["body"] == "Standup talked about this"
      assert n["kind"] == "note"

      deleted = build_conn() |> auth(token) |> delete(~p"/api/v1/notes/#{n["id"]}")
      assert response(deleted, 204) == ""
    end

    test "patch toggles done", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      {:ok, note} = Kanban.add_card_note(card, user, %{"body" => "x", "kind" => "todo"})

      conn = conn |> auth(token) |> patch(~p"/api/v1/notes/#{note.id}", %{done: true})
      assert %{"note" => n} = json_response(conn, 200)
      assert n["done"] == true
    end

    test "non-editor (viewer) gets 403 creating", %{conn: conn} do
      owner = confirmed_user_fixture()
      viewer = confirmed_user_fixture()
      board = board_fixture(owner)
      {:ok, _} = Kanban.add_member(board, viewer, "viewer")
      card = card_fixture(board, owner)
      token = api_token_fixture(viewer)

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/notes", %{body: "drive-by"})

      assert json_response(conn, 403)
    end

    test "create accepts an explicit board_stage_id on the same board", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      [_todo, done] = board.stages

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/notes", %{
          body: "log this against Done",
          board_stage_id: done.id
        })

      assert %{"note" => n} = json_response(conn, 201)
      assert n["board_stage_id"] == done.id
    end

    test "create rejects a stage from a different board", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)

      other_owner = confirmed_user_fixture()
      other_board = board_fixture(other_owner)
      [foreign_stage, _] = other_board.stages

      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/cards/#{card.id}/notes", %{
          body: "should fail",
          board_stage_id: foreign_stage.id
        })

      assert json_response(conn, 422)["error"]["code"] == "validation_failed"
    end

    test "update can re-assign the stage", %{conn: conn} do
      %{token: token, board: board, user: user} = setup_owner()
      card = card_fixture(board, user)
      [todo, done] = board.stages
      {:ok, note} = Kanban.add_card_note(card, user, %{"body" => "x"})
      assert note.board_stage_id == todo.id

      conn =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/notes/#{note.id}", %{board_stage_id: done.id})

      assert %{"note" => n} = json_response(conn, 200)
      assert n["board_stage_id"] == done.id
    end
  end
end
