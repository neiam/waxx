defmodule WaxxWeb.UserSocketTest do
  use WaxxWeb.ChannelCase, async: true

  import Waxx.AccountsFixtures

  alias WaxxWeb.UserSocket

  test "connects with a valid api token" do
    user = confirmed_user_fixture()
    token = api_token_fixture(user)

    assert {:ok, socket} = connect(UserSocket, %{"token" => token})
    assert socket.assigns.user_id == user.id
  end

  test "rejects connect without a token" do
    assert :error = connect(UserSocket, %{})
  end

  test "rejects connect with a bogus token" do
    assert :error = connect(UserSocket, %{"token" => "definitely-not-a-token"})
  end
end
