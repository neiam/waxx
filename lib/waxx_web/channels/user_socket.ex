defmodule WaxxWeb.UserSocket do
  @moduledoc """
  Token-authenticated Phoenix socket for native clients.

  Connects with `?token=<api-token>` (the same bearer the HTTP API uses).
  On a successful connect we assign `:user_id` so channels downstream
  can scope themselves without re-doing the DB hit.
  """

  use Phoenix.Socket

  alias Waxx.Accounts

  channel "board:*", WaxxWeb.BoardChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) when is_binary(token) do
    case Accounts.fetch_user_by_api_token(token) do
      {user, _token_id} ->
        {:ok,
         socket
         |> assign(:user_id, user.id)
         |> assign(:api_token, token)}

      _ ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(%{assigns: %{user_id: user_id}}), do: "user_socket:#{user_id}"
  def id(_socket), do: nil
end
