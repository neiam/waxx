defmodule WaxxWeb.CardBackgroundController do
  @moduledoc """
  Serves a card's pasted background image so the kanban board tiles can
  reference it as a plain `background-image: url(...)` rather than inlining
  the bytes into the board payload. Access is gated on the caller being able
  to see the card's board.
  """
  use WaxxWeb, :controller

  alias Waxx.Kanban

  def show(conn, %{"id" => card_id}) do
    user = conn.assigns.current_scope.user

    case Kanban.fetch_card_background_for_user(card_id, user) do
      {:ok, bg} ->
        conn
        # The URL is cache-busted by a `?v=<updated_at>` param, so the bytes
        # for a given version are immutable and safe to cache privately.
        |> put_resp_header("cache-control", "private, max-age=31536000, immutable")
        |> put_resp_content_type(bg.content_type, nil)
        |> send_resp(200, bg.image_data)

      :error ->
        conn
        |> put_status(:not_found)
        |> text("Not found")
    end
  end
end
