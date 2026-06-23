defmodule WaxxWeb.BoardLive.ShowTest do
  use WaxxWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias Waxx.Kanban

  # 1x1 transparent PNG.
  @png_data_url "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

  test "renders the board with its cards", %{conn: conn} do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    card = card_fixture(board, user, %{"title" => "Buy milk"})

    {:ok, _lv, html} = live(log_in_user(conn, user), ~p"/boards/#{board.id}")

    assert html =~ "Buy milk"
    refute html =~ "/cards/#{card.id}/background"
  end

  test "a card with a background renders the tile background URL", %{conn: conn} do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    card = card_fixture(board, user, %{"title" => "Has art"})
    {:ok, _} = Kanban.set_card_background(card, @png_data_url)

    {:ok, _lv, html} = live(log_in_user(conn, user), ~p"/boards/#{board.id}")

    # The tile references the lazy image endpoint, not inlined bytes.
    assert html =~ "/cards/#{card.id}/background?v="
    refute html =~ "data:image/png;base64"
  end
end
