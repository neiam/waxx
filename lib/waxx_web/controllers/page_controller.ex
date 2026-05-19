defmodule WaxxWeb.PageController do
  use WaxxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
