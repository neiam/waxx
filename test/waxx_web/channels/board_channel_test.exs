defmodule WaxxWeb.BoardChannelTest do
  use WaxxWeb.ChannelCase, async: true

  import Waxx.AccountsFixtures
  import Waxx.KanbanFixtures

  alias WaxxWeb.{BoardChannel, UserSocket}

  defp connected_socket(user) do
    token = api_token_fixture(user)
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    socket
  end

  test "members can join their board channel" do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    socket = connected_socket(user)

    {:ok, reply, _socket} = subscribe_and_join(socket, BoardChannel, "board:" <> board.id)
    assert reply == %{board_id: board.id}
  end

  test "non-members are refused" do
    member = confirmed_user_fixture()
    stranger = confirmed_user_fixture()
    board = board_fixture(member)
    socket = connected_socket(stranger)

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, BoardChannel, "board:" <> board.id)
  end

  test "broadcasts cards_changed when a card mutation lands" do
    user = confirmed_user_fixture()
    board = board_fixture(user)
    socket = connected_socket(user)
    {:ok, _, _} = subscribe_and_join(socket, BoardChannel, "board:" <> board.id)

    # Trigger an actual mutation; the existing PubSub broadcast in
    # Kanban routes through to the channel.
    _ = card_fixture(board, user)

    assert_push("cards_changed", %{board_id: board_id})
    assert board_id == board.id
  end
end
