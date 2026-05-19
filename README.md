# Waxx

Multi-user kanban with branching workflows, reusable templates, labels,
custom fields, and a workflow-aware drag-and-drop UI. Phoenix LiveView
on top of PostgreSQL.

The point of Waxx is that the board's columns aren't just buckets:
they're a directed graph. You draw the graph once on a template
(stages = nodes, transitions = edges), spin up boards from it, and
cards can only move along edges the workflow allows. Both the UI and
the server enforce it.

## Features

- **Branching workflows** — visual graph editor, server-side transition
  enforcement, click-to-connect stage editor, backward edges loop out
  to the right of the column.
- **Reusable workflow templates** — stages, transitions, labels and
  custom fields live on a template. Boards clone the template at
  creation; later template edits propagate by stage/label/field name
  to boards that haven't drifted.
- **Custom fields** — text / date / datetime / select, with a
  per-field "show on card" toggle that surfaces the value as a chip on
  the kanban tile.
- **Labels** — coloured tag chips; click-to-toggle in the card modal.
  Tailwind colour swatches + native picker for choosing colours.
- **Drag and drop** — HTML5 DnD with green / red drop highlights driven
  by the workflow graph. Reorder within a column or drop into another;
  invalid drops can't be released (`dragover` never `preventDefault`s
  on a forbidden target).
- **Live multiplayer** — Phoenix PubSub broadcasts every card mutation
  and every template-driven workflow change to subscribed boards.
- **Auto-archive** — boards have an `archive_terminal_after_days`
  setting (default 7). Cards in a terminal stage (no outgoing edges)
  longer than the threshold drop out of the kanban view automatically.
  Set to blank to never archive. Per-stage entry timestamp on each card
  is the source of truth — title/description edits don't reset it.
- **Board history** — every card mutation (create / move / update /
  delete / assign / label / field) is logged with actor, timestamp,
  and a denormalised meta blob so the log keeps reading cleanly even
  after referenced rows are renamed or deleted. Visit `/boards/:id/history`.
- **Label-text toggle** — per-user, per-board preference to render
  label chips as just coloured dots instead of name + colour. Stored
  on the user as a jsonb pref, falls back to a user-wide default.
  Toggle button lives next to History/Settings on each board.
- **Tabbed template editor** — `/workflow-templates/:id?tab=workflow|labels|fields`
  splits the editor into three URL-addressable tabs with counts in
  the tab labels.
- **Accounts** — magic-link login by default, password optional, sudo
  mode for sensitive changes, session tokens with reissue.
- **Two invite systems** — app-level (`/users/invites` + `mix phx.gen.invite`)
  gates registration; board-level (`/boards/:id/settings`) grants
  membership with a role (owner / editor / viewer).
- **Subboards (2-D grid)** — split a board into rows. The kanban view
  becomes a grid: subboards down the side, stages across the top.
  Cards start in the default row and drag/drop into a subboard cell;
  the server moves stage and subboard atomically per drop. Configure
  from the board's settings page.
- **Themes** — daisyUI with six ported from neiam-co plus a blueprint
  palette. Pick from the dropdown; choice persists to localStorage.
- **UUIDv7 primary keys** — time-ordered, so `ORDER BY id` is almost
  `ORDER BY inserted_at` for free and the b-tree stays warm at the
  end.

## Quick start

```sh
# 1. Bring up Postgres (compose maps 54328 → 5432 inside)
podman-compose up -d  # or docker compose up -d

# 2. Install deps, create + migrate the dev DB, build assets
mix setup

# 3. Start the dev server
mix phx.server
```

Then open <http://localhost:4000>.

Registration is invite-only by default. Mint a registration link from
the CLI:

```sh
mix phx.gen.invite you@example.com
```

The task prints a URL — visit it to create your account.

## Configuration switches

- `:accounts_enabled` (`config/config.exs`) — master switch. When
  `false` the `/users/*` and `/boards/*` routes are not mounted and the
  auth nav vanishes. Useful for read-only / pre-launch deployments.
- `:registration_open` — when `false`, `/users/register` only accepts
  visitors who carry a valid invite token. Existing users mint invite
  links from the UI or the mix task.

## Layout

```
lib/
  waxx/
    accounts/        # user, user_token, invite (app-level), notifier
    workflows/       # template, stage, transition, label, field
    kanban/          # board, board_stage, board_transition, board_label,
                     # board_field, board_activity, membership,
                     # board_invite, card, card_assignee, card_label,
                     # card_field_value
    accounts.ex      # account context (registration, login, invites, prefs)
    workflows.ex     # template CRUD + propagation calls into kanban
    kanban.ex        # boards, cards, transitions, broadcasts, history log
    uuidv7.ex        # Ecto type
    schema.ex        # use-macro: UUIDv7 PK + FK defaults
    themes.ex        # theme catalog
  waxx_web/
    live/
      template_live/ # /workflow-templates and the visual editor (tabbed)
      board_live/    # /boards, /boards/:id, settings, history, invites
      user_live/     # login, registration, settings, app-invites
    components/
      core_components.ex   # buttons, inputs, the colour picker
      layouts.ex           # navbar + flash group + theme toggle
    controllers/
      board_invite_controller.ex   # /b/:token redemption
      user_session_controller.ex   # login/logout/update-password
priv/repo/migrations/
test/
```

## Architecture notes

- **Schemas** all `use Waxx.Schema`, which sets UUIDv7 PKs and FKs.
- **Migrations** use `migration_primary_key: [type: :binary_id]` from
  `config/config.exs`; columns are Postgres `uuid`.
- **Template → board propagation** matches by *name*. Renaming a stage
  on a board makes it "drift" — subsequent template edits touching that
  name skip the drifted board. Deletes only propagate when the matching
  board entity isn't in use (no cards in the stage, no card has the
  label, no value for the field). Drift over data loss.
- **Transition enforcement** lives in `Kanban.move_card/3`: same-stage
  calls fall through to `reorder_card/2`; cross-stage requires a
  `BoardTransition` from current → target. Server returns
  `{:error, :invalid_transition}` if you bypass the UI.
- **PubSub topic** is `"board:#{id}"`. `Kanban.subscribe/1` joins;
  the kanban LiveView re-fetches cards on `:cards_changed` and the
  full workflow snapshot on `:workflow_changed`.
- **Activity log** writes are best-effort, post-mutation. The mutation
  succeeds or fails on its own merits; logging never blocks the
  business operation. Meta is stored as denormalised strings so the
  history view stays readable after referenced rows change.
- **User preferences** live in a single `users.preferences :map`
  (jsonb) column. Keys follow `"<feature>:<scope_id>"` for per-scope
  overrides and `"<feature>_default"` for user-wide defaults — see
  `Accounts.hide_label_text?/2` for the lookup pattern.

## Development

```sh
mix precommit   # compile --warnings-as-errors, deps.unlock --unused, format, test
mix test        # 35 tests, mostly context-level
mix phx.gen.invite EMAIL   # mint an account-registration invite
```

If you change the schema and want to start from a clean dev DB:

```sh
PGPASSWORD=postgres psql -h localhost -p 54328 -U postgres -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity \
      WHERE datname IN ('waxx_dev','waxx_test') AND pid <> pg_backend_pid();"
mix ecto.drop && mix ecto.create && mix ecto.migrate
MIX_ENV=test mix ecto.drop && MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate
```

## Deployment

The repo ships a Kubernetes deploy plan modelled on the one used for
diogramos. The pieces:

- **`Dockerfile`** — multi-stage build on
  `hexpm/elixir:1.17.3-erlang-27.2-debian-bookworm-…`, produces an
  Elixir release at `/app/bin/waxx`. Entry point goes through `tini`
  so SIGTERM closes Postgres connections cleanly.
- **`rel/env.sh.eex`** — long-name distribution from `POD_IP` so
  libcluster can connect peers as `waxx@<pod-ip>`.
- **`rel/overlays/bin/{server,migrate}`** — `server` starts the
  release with `PHX_SERVER=true`; `migrate` runs `Waxx.Release.migrate`
  from a running container without Mix.
- **`lib/waxx/release.ex`** — `migrate / rollback / init` ops tasks
  callable via `bin/waxx eval …`.
- **`app.yml`** — Namespace, ServiceAccount + RBAC (pods + endpoints,
  for libcluster's K8s strategy), Deployment with 2 replicas (rolling
  update, max-surge 1, max-unavail 0), regular Service, headless
  Service for peer discovery, Traefik redirect-https Middleware, and
  Ingress with cert-manager.
- **`pg.yml`** — StackGres SGCluster with the `citext` extension
  enabled (`users.email` is a `citext` column).
- **`app-secrets.example.yml`** — template Secret carrying
  `secret_key_base` and `erlang_cookie`. The Postgres password comes
  from the StackGres-managed `postgres` Secret in the same namespace.
- **`.gitlab-ci.yml`** — Kaniko build to the container registry on
  pushes to `master`.

### Clustering

In prod, `config/runtime.exs` configures libcluster with
`Cluster.Strategy.Kubernetes`:

```elixir
config :libcluster,
  topologies: [
    waxx: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        mode: :ip,
        kubernetes_selector: "name=waxx",
        kubernetes_service_name: "waxx-headless",
        kubernetes_node_basename: "waxx",
        kubernetes_namespace: "waxx",
        polling_interval: 10_000
      ]
    ]
  ]
```

`Waxx.Application` only starts `Cluster.Supervisor` when a topology is
configured, so dev/test don't try to join a cluster. Phoenix.PubSub
broadcasts (every `:cards_changed` / `:workflow_changed` event) fan
out automatically across connected nodes, so a drag on replica A
is visible in real time to a user on replica B.

### Going live

```sh
# 1. Apply the database
kubectl apply -f pg.yml

# 2. Fill in + apply the app secret
cp app-secrets.example.yml app-secrets.yml
$EDITOR app-secrets.yml
kubectl apply -f app-secrets.yml

# 3. Apply the rest
kubectl apply -f app.yml

# 4. Run migrations and seed the first user
kubectl -n waxx exec deploy/waxx -- /app/bin/migrate
kubectl -n waxx exec deploy/waxx -- /app/bin/waxx eval \
  'Waxx.Release.init("admin@example.com", "a-strong-password")'
```

## License

Not yet specified.
