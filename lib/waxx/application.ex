defmodule Waxx.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Forward warnings + errors to Sentry. No-ops when SENTRY_DSN is unset.
    # We wrap the add_handler call so a bad Sentry config can't take the
    # whole VM down at boot — the worst case is "no Sentry today".
    try do
      :logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
        config: %{metadata: [:file, :line]}
      })
    rescue
      e ->
        IO.warn("[waxx] sentry handler not attached: #{Exception.message(e)}")
    end

    topologies = Application.get_env(:libcluster, :topologies, [])

    children =
      [
        WaxxWeb.Telemetry,
        Waxx.Repo,
        {DNSCluster, query: Application.get_env(:waxx, :dns_cluster_query) || :ignore}
      ] ++
        cluster_children(topologies) ++
        [
          {Phoenix.PubSub, name: Waxx.PubSub},
          WaxxWeb.Endpoint
        ]

    opts = [strategy: :one_for_one, name: Waxx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # libcluster is only added to the supervision tree when a topology is
  # configured (prod, via runtime.exs). In dev/test the list is empty and
  # we skip starting a Cluster.Supervisor entirely.
  defp cluster_children([]), do: []

  defp cluster_children(topologies) do
    [{Cluster.Supervisor, [topologies, [name: Waxx.ClusterSupervisor]]}]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WaxxWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
