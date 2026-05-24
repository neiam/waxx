defmodule WaxxWeb.MagicLinkController do
  @moduledoc """
  The shared handoff endpoint for magic-link emails.

  The Android client registers an intent filter on
  `https://<host>/m/:token` (an App Link). When the OS routes the URL to
  the app, the app calls `POST /api/v1/sessions/redeem` directly and the
  user never sees this controller.

  When the same URL is opened in a browser (no Android handoff happened),
  this controller redirects to the existing web magic-link confirmation
  page so the user lands in the LiveView flow.
  """

  use WaxxWeb, :controller

  def show(conn, %{"token" => token}) do
    redirect(conn, to: ~p"/users/log-in/#{token}")
  end
end
