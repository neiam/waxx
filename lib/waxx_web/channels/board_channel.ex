defmodule WaxxWeb.BoardChannel do
  @moduledoc """
  Per-board update stream.

  Topic: `"board:<board-id>"`.

  Join requires the connected user to have a membership on the board —
  the bearer-token connect on `UserSocket` already proved who the user
  is; this channel asserts they're authorized to watch *this* board.

  Once joined, the socket forwards the two existing `Kanban` PubSub
  events as lightweight notifications:

    - `{:cards_changed, board_id}`    → push `"cards_changed"`
    - `{:workflow_changed, board_id}` → push `"workflow_changed"`

  Payloads are intentionally just `%{board_id: ...}` — the client
  re-fetches the affected resource via HTTP. This matches the existing
  LiveView contract; if we want to move to delta payloads later, only
  the push body changes.
  """

  use WaxxWeb, :channel

  alias Waxx.Accounts
  alias Waxx.Kanban

  @impl true
  def join("board:" <> board_id, _params, socket) do
    user_id = socket.assigns.user_id
    user = Accounts.get_user!(user_id)

    if Kanban.role_for(board_id, user) do
      :ok = Kanban.subscribe(board_id)
      {:ok, %{board_id: board_id}, assign(socket, :board_id, board_id)}
    else
      {:error, %{reason: "forbidden"}}
    end
  end

  @impl true
  def handle_info({:cards_changed, board_id}, socket) do
    push(socket, "cards_changed", %{board_id: board_id})
    {:noreply, socket}
  end

  def handle_info({:workflow_changed, board_id}, socket) do
    push(socket, "workflow_changed", %{board_id: board_id})
    {:noreply, socket}
  end

  def handle_info(_other, socket), do: {:noreply, socket}
end
