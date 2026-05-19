defmodule WaxxWeb.BoardInviteController do
  use WaxxWeb, :controller

  alias Waxx.Kanban

  def show(conn, %{"token" => token}) do
    case Kanban.get_active_board_invite(token) do
      nil ->
        conn
        |> put_flash(:error, "That board invite is invalid, used, or expired.")
        |> redirect(to: ~p"/")

      invite ->
        case conn.assigns[:current_scope] do
          %{user: user} when not is_nil(user) ->
            case Kanban.redeem_board_invite(invite, user) do
              {:ok, board} ->
                conn
                |> put_flash(:info, "Joined #{board.name}.")
                |> redirect(to: ~p"/boards/#{board.id}")

              {:error, _} ->
                conn
                |> put_flash(:error, "Could not redeem invite.")
                |> redirect(to: ~p"/")
            end

          _ ->
            # Send unauthenticated users through the login flow; they'll be
            # bounced back to /b/:token by user_return_to.
            conn
            |> put_session(:user_return_to, ~p"/b/#{invite.token}")
            |> put_flash(:info, "Log in to accept the invite to “#{invite.board.name}”.")
            |> redirect(to: ~p"/users/log-in")
        end
    end
  end
end
