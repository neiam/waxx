defmodule Mix.Tasks.Phx.Gen.Invite do
  @shortdoc "Mint an account-registration invite token"

  @moduledoc """
  Mints an account-registration invite and prints a URL you can share.

  Useful when registration is invite-only
  (`config :waxx, :registration_open, false`) and you need to onboard
  someone without already being logged in to the app.

      mix phx.gen.invite alice@example.com

  The email is recorded in the invite's `note` field for audit; the task
  does NOT send mail. Copy the printed URL and share it however you like.

  In a release (no `mix` available) the equivalent is:

      bin/waxx rpc 'Waxx.Accounts.create_system_invite(%{note: "for alice@example.com"}) |> elem(1) |> Map.fetch!(:token) |> IO.puts()'
  """

  use Mix.Task

  @email_regex ~r/^[^@,;\s]+@[^@,;\s]+$/

  @impl Mix.Task
  def run(args) do
    case args do
      [email] ->
        unless email =~ @email_regex do
          Mix.raise(~s("#{email}" doesn't look like an email address.))
        end

        Mix.Task.run("app.start")
        mint_and_print(email)

      _ ->
        Mix.raise("Usage: mix phx.gen.invite EMAIL")
    end
  end

  defp mint_and_print(email) do
    case Waxx.Accounts.create_system_invite(%{note: "for #{email}"}) do
      {:ok, invite} ->
        url = WaxxWeb.Endpoint.url() <> "/users/register?invite=#{invite.token}"

        Mix.shell().info("""

        Invite created for #{email}.

        Share this URL:

          #{url}

        Token: #{invite.token}
        """)

      {:error, changeset} ->
        Mix.raise("Could not create invite: #{inspect(changeset.errors)}")
    end
  end
end
