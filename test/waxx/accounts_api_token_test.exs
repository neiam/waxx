defmodule Waxx.AccountsApiTokenTest do
  use Waxx.DataCase, async: true

  import Waxx.AccountsFixtures

  alias Waxx.Accounts

  describe "create_api_token/2 label handling" do
    test "stores a trimmed label" do
      user = confirmed_user_fixture()
      _ = Accounts.create_api_token(user, %{label: "  Pixel 7, kitchen  "})

      assert [%{label: "Pixel 7, kitchen"}] = Accounts.list_api_tokens(user)
    end

    test "accepts string-keyed label" do
      user = confirmed_user_fixture()
      _ = Accounts.create_api_token(user, %{"label" => "Work laptop"})

      assert [%{label: "Work laptop"}] = Accounts.list_api_tokens(user)
    end

    test "an empty or whitespace-only label is stored as nil" do
      user = confirmed_user_fixture()
      _ = Accounts.create_api_token(user, %{label: "   "})

      assert [%{label: nil}] = Accounts.list_api_tokens(user)
    end

    test "no label argument means nil label" do
      user = confirmed_user_fixture()
      _ = Accounts.create_api_token(user)

      assert [%{label: nil}] = Accounts.list_api_tokens(user)
    end

    test "truncates labels longer than 80 chars" do
      user = confirmed_user_fixture()
      long = String.duplicate("x", 200)
      _ = Accounts.create_api_token(user, %{label: long})

      [%{label: stored}] = Accounts.list_api_tokens(user)
      assert String.length(stored) == 80
    end
  end

  describe "list_api_tokens/1" do
    test "returns tokens newest-authenticated-first with the expected fields" do
      user = confirmed_user_fixture()
      _ = Accounts.create_api_token(user, %{label: "first"})
      _ = Accounts.create_api_token(user, %{label: "second"})

      tokens = Accounts.list_api_tokens(user)
      assert length(tokens) == 2
      assert Enum.all?(tokens, &Map.has_key?(&1, :label))
      assert Enum.all?(tokens, &Map.has_key?(&1, :sent_to))
      assert Enum.all?(tokens, &Map.has_key?(&1, :authenticated_at))
    end

    test "only returns the calling user's tokens" do
      alice = confirmed_user_fixture()
      bob = confirmed_user_fixture()
      _ = Accounts.create_api_token(alice, %{label: "alice"})
      _ = Accounts.create_api_token(bob, %{label: "bob"})

      assert [%{label: "alice"}] = Accounts.list_api_tokens(alice)
      assert [%{label: "bob"}] = Accounts.list_api_tokens(bob)
    end
  end

  describe "delete_api_token/2" do
    test "owner can revoke their own token" do
      user = confirmed_user_fixture()
      _ = Accounts.create_api_token(user, %{label: "doomed"})
      [%{id: id}] = Accounts.list_api_tokens(user)

      assert :ok = Accounts.delete_api_token(user, id)
      assert [] = Accounts.list_api_tokens(user)
    end

    test "refuses to revoke another user's token" do
      alice = confirmed_user_fixture()
      bob = confirmed_user_fixture()
      _ = Accounts.create_api_token(alice)
      [%{id: id}] = Accounts.list_api_tokens(alice)

      assert {:error, :not_found} = Accounts.delete_api_token(bob, id)
      assert [_] = Accounts.list_api_tokens(alice)
    end
  end
end
