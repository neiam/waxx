import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/waxx start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :waxx, WaxxWeb.Endpoint, server: true
end

config :waxx, WaxxWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []
  pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Prefer discrete POSTGRES_* env vars (composes safely even when the
  # password contains URL-significant characters like @ / : + & — which
  # is common with StackGres / KubeDB-generated passwords). Fall back to
  # DATABASE_URL when those aren't present.
  cond do
    System.get_env("POSTGRES_HOST") ->
      config :waxx, Waxx.Repo,
        hostname: System.get_env("POSTGRES_HOST"),
        port: String.to_integer(System.get_env("POSTGRES_PORT") || "5432"),
        username:
          System.get_env("POSTGRES_USER") ||
            raise("POSTGRES_USER is required when POSTGRES_HOST is set"),
        password:
          System.get_env("POSTGRES_PASSWORD") ||
            raise("POSTGRES_PASSWORD is required when POSTGRES_HOST is set"),
        database: System.get_env("POSTGRES_DB") || "waxx",
        pool_size: pool_size,
        socket_options: maybe_ipv6

    System.get_env("DATABASE_URL") ->
      config :waxx, Waxx.Repo,
        url: System.get_env("DATABASE_URL"),
        pool_size: pool_size,
        socket_options: maybe_ipv6

    true ->
      raise """
      Database configuration missing. Set either:
        - POSTGRES_HOST + POSTGRES_USER + POSTGRES_PASSWORD (preferred), or
        - DATABASE_URL (e.g. ecto://USER:PASS@HOST/DATABASE)
      """
  end

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :waxx, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Sentry: only emits when DSN is non-empty, so the secret can be left
  # blank (or absent) in environments where reporting is off.
  config :sentry,
    dsn: System.get_env("SENTRY_DSN"),
    environment_name: :prod,
    release: System.get_env("APP_VERSION") || System.get_env("CI_COMMIT_SHA")

  # libcluster — Kubernetes endpoints lookup against the headless
  # service we deploy alongside the app. RBAC (pods + endpoints) is
  # granted to the `waxx` ServiceAccount in app.yml.
  config :libcluster,
    topologies: [
      waxx: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :ip,
          # Both keys are required by libcluster 3.5 even in :endpoints
          # lookup mode — it filters endpoints by selector.
          kubernetes_selector: "name=waxx",
          kubernetes_service_name: "waxx-headless",
          kubernetes_node_basename: "waxx",
          kubernetes_namespace: "waxx",
          polling_interval: 10_000
        ]
      ]
    ]

  # Mailer adapter selection:
  #
  #   * SMTP_RELAY set  → Swoosh.Adapters.SMTP (via gen_smtp)
  #   * otherwise       → Swoosh.Adapters.Logger
  #
  # The Logger adapter doesn't actually send mail — it logs the
  # rendered email at :info — but it gets us off Swoosh.Adapters.Local
  # (the dev mailbox), so the magic-link flow at least leaves a trail
  # in the pod log when SMTP isn't configured.
  # Map env-string to a literal atom. `String.to_existing_atom/1` doesn't
  # work here in a release: runtime.exs runs before the application that
  # owns these atoms has loaded, so the atoms aren't in the table yet.
  smtp_tri = fn var, default ->
    case System.get_env(var, default) do
      "always" -> :always
      "if_available" -> :if_available
      "never" -> :never
      other -> raise "#{var} must be one of always|if_available|never, got: #{inspect(other)}"
    end
  end

  # Eager-load the OS CA bundle into OTP's `public_key` cache. Without
  # this, `:public_key.cacerts_get/0` returns `:undefined`, and
  # `gen_smtp`'s internal default `tls_options` injects
  # `cacerts: :undefined` — which `:ssl` then rejects as incompatible
  # with `verify: :verify_peer`, clobbering our explicit `cacertfile`.
  case :public_key.cacerts_load() do
    :ok ->
      :ok

    {:error, reason} ->
      require Logger
      Logger.warning("public_key:cacerts_load failed: #{inspect(reason)} — TLS verify may fail")
  end

  # CA bundle for TLS verification. We pass both `cacertfile` (path)
  # and rely on the cacerts_load above for `cacerts_get/0` to work,
  # belt-and-braces. Override `SMTP_CACERTFILE` if your image puts the
  # bundle elsewhere; set `SMTP_TLS_VERIFY=verify_none` for self-signed
  # / private relays where you'd rather skip cert validation.
  smtp_cacertfile =
    System.get_env("SMTP_CACERTFILE", "/etc/ssl/certs/ca-certificates.crt")

  smtp_verify =
    case System.get_env("SMTP_TLS_VERIFY", "verify_peer") do
      "verify_peer" -> :verify_peer
      "verify_none" -> :verify_none
      other -> raise "SMTP_TLS_VERIFY must be verify_peer or verify_none, got: #{inspect(other)}"
    end

  # Resolve the CA store NOW (after `cacerts_load`) rather than letting
  # the downstream stack call `cacerts_get/0` lazily. gen_smtp / ssl
  # has a habit of evaluating it in a context where it still returns
  # `:undefined`, which then collides with our `cacertfile`. Passing
  # `cacerts: <list>` explicitly is unambiguous — `:ssl` honors it
  # and never re-derives.
  smtp_cacerts =
    case :public_key.cacerts_get() do
      certs when is_list(certs) and certs != [] -> certs
      _ -> nil
    end

  mailer_opts =
    if relay = System.get_env("SMTP_RELAY") do
      tls_options =
        [
          verify: smtp_verify,
          server_name_indication: String.to_charlist(relay),
          depth: 99
        ] ++
          cond do
            smtp_verify != :verify_peer ->
              []

            is_list(smtp_cacerts) ->
              [cacerts: smtp_cacerts]

            true ->
              [cacertfile: smtp_cacertfile]
          end

      # Pin modern TLS at both the top level (read by gen_smtp before
      # it calls :ssl.connect) and inside tls_options (read by :ssl
      # itself). Matches the working pattern from gitgud.
      tls_versions = [:"tlsv1.2", :"tlsv1.3"]

      # gen_smtp 1.2 has two distinct connection paths with different
      # option keys:
      #
      #   * `ssl: true` (port 465 implicit TLS) reads its TLS opts
      #     from `sockopts`. `tls_options` is ignored on this path.
      #   * `tls: :always|:if_available` (STARTTLS upgrade) reads from
      #     `tls_options` — only used during do_STARTTLS.
      #
      # Without sockopts on the implicit-TLS path, OTP 28's `:ssl`
      # falls through to its own defaults (verify_peer +
      # `public_key.cacerts_get()` which returns `:undefined`) and
      # bails with `{options, incompatible, [verify: verify_peer,
      # cacerts: undefined]}`. Putting the same opts on both keys
      # covers both relay setups.
      ssl_opts = [{:versions, tls_versions} | tls_options]

      [
        adapter: Swoosh.Adapters.SMTP,
        relay: relay,
        port: String.to_integer(System.get_env("SMTP_PORT", "587")),
        username: System.get_env("SMTP_USERNAME"),
        password: System.get_env("SMTP_PASSWORD"),
        tls: smtp_tri.("SMTP_TLS", "if_available"),
        ssl: System.get_env("SMTP_SSL", "false") == "true",
        auth: smtp_tri.("SMTP_AUTH", "if_available"),
        allowed_tls_versions: tls_versions,
        sockopts: ssl_opts,
        tls_options: ssl_opts,
        retries: 1,
        no_mx_lookups: false
      ]
    else
      [adapter: Swoosh.Adapters.Logger, level: :info]
    end

  config :waxx, Waxx.Mailer, mailer_opts

  config :waxx, Waxx.Mailer,
    from_name: System.get_env("MAIL_FROM_NAME", "Waxx"),
    from_address: System.get_env("MAIL_FROM_ADDRESS") || "noreply@#{host}"

  config :waxx, WaxxWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    # Accept both http and https origins for the configured host. The
    # `//host` form matches any scheme/port. Without this the LiveView
    # WebSocket upgrade is rejected silently when the proxy forwards a
    # subtly-different Origin header (no Logger event, nothing in Sentry).
    check_origin: ["//#{host}", "https://#{host}"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :waxx, WaxxWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :waxx, WaxxWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :waxx, Waxx.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
