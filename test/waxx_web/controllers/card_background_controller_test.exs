defmodule WaxxWeb.CardBackgroundControllerTest do
  use WaxxWeb.ConnCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias Waxx.Kanban

  # 1x1 transparent PNG.
  @png_data_url "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

  test "serves the image bytes with its content type to a board member", %{conn: conn} do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    card = card_fixture(board, user)
    {:ok, bg} = Kanban.set_card_background(card, @png_data_url)

    conn = conn |> log_in_user(user) |> get(~p"/cards/#{card.id}/background")

    assert response(conn, 200) == bg.image_data
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/png"
  end

  test "404 when the card has no background", %{conn: conn} do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    card = card_fixture(board, user)

    conn = conn |> log_in_user(user) |> get(~p"/cards/#{card.id}/background")
    assert response(conn, 404)
  end

  test "404 when the caller can't see the card's board", %{conn: conn} do
    owner = confirmed_user_fixture()
    board = board_fixture(owner)
    card = card_fixture(board, owner)
    {:ok, _} = Kanban.set_card_background(card, @png_data_url)

    stranger = confirmed_user_fixture()
    conn = conn |> log_in_user(stranger) |> get(~p"/cards/#{card.id}/background")
    assert response(conn, 404)
  end
end
