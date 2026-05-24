defmodule WaxxWeb.ChannelCase do
  @moduledoc """
  Test case for channel tests. Wraps `Phoenix.ChannelTest` and sets up
  the SQL sandbox like `WaxxWeb.ConnCase` does.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import WaxxWeb.ChannelCase

      @endpoint WaxxWeb.Endpoint
    end
  end

  setup tags do
    Waxx.DataCase.setup_sandbox(tags)
    :ok
  end
end
