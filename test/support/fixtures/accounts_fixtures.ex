defmodule Waxx.AccountsFixtures do
  @moduledoc """
  Minimal fixtures for tests that need a `%User{}`.
  """

  alias Waxx.Accounts.User
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
end
