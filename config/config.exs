# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :waxx, :scopes,
  user: [
    default: true,
    module: Waxx.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Waxx.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :waxx,
  ecto_repos: [Waxx.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# UUIDv7 PKs/FKs everywhere by default. `Waxx.UUIDv7` is the Ecto type
# that fills the generated `id` columns; the migration columns are
# Postgres `uuid` (via `:binary_id`).
config :waxx, Waxx.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id]

# Master switch for the accounts/auth/invite flow ported from diogramos.
# When false, the /users/* routes and the auth nav links are not mounted,
# and the app effectively has no login. Flip to true to enable.
config :waxx, :accounts_enabled, true

# When false, /users/register only accepts visitors who arrived via a
# valid invite token (`/users/register?invite=...`). Existing users can
# generate invite tokens at /users/invites. Flip to true to let anyone
# self-register.
config :waxx, :registration_open, false

# Configure the endpoint
config :waxx, WaxxWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WaxxWeb.ErrorHTML, json: WaxxWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Waxx.PubSub,
  live_view: [signing_salt: "EoK4t/Jz"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :waxx, Waxx.Mailer,
  adapter: Swoosh.Adapters.Local,
  from_name: "Waxx",
  from_address: "noreply@localhost"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  waxx: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  waxx: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Sentry error reporting. The DSN is set in runtime.exs from the
# SENTRY_DSN environment variable; when the DSN is empty or unset,
# Sentry quietly no-ops.
config :sentry,
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()],
  environment_name: Mix.env()

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
