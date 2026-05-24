defmodule Waxx.AccountsFixtures do
  @moduledoc """
  Minimal fixtures for tests that need a `%User{}`.
  """

  alias Waxx.Accounts
  alias Waxx.Accounts.{User, UserToken}
  alias Waxx.Repo

  def unique_user_email do
    "user-#{System.unique_integer([:positive])}@example.com"
  end

  def user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, unique_user_email())

    {:ok, user} =
      %User{}
      |> User.email_changeset(%{email: email})
      |> Repo.insert()

    user
  end

  @doc "Returns a `%User{}` that has gone through magic-link confirmation."
  def confirmed_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    {:ok, user} = user |> User.confirm_changeset() |> Repo.update()
    user
  end

  @doc """
  Mints an encoded magic-link token for `user` and inserts the matching
  `UserToken` row. Returns the encoded token (the same string the user
  would receive in the email).
  """
  def magic_link_token_fixture(%User{} = user) do
    {encoded, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    encoded
  end

  @doc "Mints an API token for `user` and returns the encoded string."
  def api_token_fixture(%User{} = user) do
    Accounts.create_api_token(user)
  end
end
