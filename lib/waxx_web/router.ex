defmodule WaxxWeb.Router do
  use WaxxWeb, :router

  import WaxxWeb.UserAuth

  # Master switch for the accounts/auth/invite flow. When false, the
  # /users/* routes are not mounted and the layout drops its auth nav.
  # The scope/session plugs are still installed so other code that looks
  # for :current_scope finds nil instead of crashing.
  @accounts_enabled Application.compile_env(:waxx, :accounts_enabled, true)

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WaxxWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_authenticated do
    plug :accepts, ["json"]
    plug WaxxWeb.Api.Auth
  end

  scope "/", WaxxWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:waxx, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WaxxWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes — only mounted when :accounts_enabled is true.
  if @accounts_enabled do
    scope "/", WaxxWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: [{WaxxWeb.UserAuth, :require_authenticated}] do
        live "/users/settings", UserLive.Settings, :edit
        live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
        live "/users/invites", UserLive.Invites, :index

        live "/workflow-templates", TemplateLive.Index, :index
        live "/workflow-templates/:id", TemplateLive.Edit, :edit

        live "/boards", BoardLive.Index, :index
        live "/boards/:id", BoardLive.Show, :show
        live "/boards/:id/settings", BoardLive.Settings, :edit
        live "/boards/:id/history", BoardLive.History, :index
      end

      post "/users/update-password", UserSessionController, :update_password

      # Card background image bytes, referenced by board tiles + the card
      # modal as `background-image: url(...)`. Auth inherited from the scope.
      get "/cards/:id/background", CardBackgroundController, :show
    end

    scope "/", WaxxWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: [{WaxxWeb.UserAuth, :mount_current_scope}] do
        live "/users/register", UserLive.Registration, :new
        live "/users/log-in", UserLive.Login, :new
        live "/users/log-in/:token", UserLive.Confirmation, :new
      end

      post "/users/log-in", UserSessionController, :create
      delete "/users/log-out", UserSessionController, :delete

      # Board-invite redemption — handles both authenticated and anon users
      # (anon users get bounced to login with the invite URL stored as
      # user_return_to).
      get "/b/:token", BoardInviteController, :show

      # Shared magic-link handoff. Android App Links intercept this URL
      # before the browser sees it; browsers fall through to the existing
      # /users/log-in/:token LiveView flow.
      get "/m/:token", MagicLinkController, :show
    end

    # JSON API for native clients. Public endpoints (no token required)
    # live under the :api pipeline; authenticated ones go through
    # :api_authenticated which installs WaxxWeb.Api.Auth.
    scope "/api/v1", WaxxWeb.Api.V1, as: :api_v1 do
      pipe_through :api

      post "/sessions/request_magic_link", SessionController, :request_magic_link
      post "/sessions/redeem", SessionController, :redeem
    end

    scope "/api/v1", WaxxWeb.Api.V1, as: :api_v1 do
      pipe_through :api_authenticated

      delete "/sessions/current", SessionController, :delete
      get "/users/me", UserController, :me

      get "/boards", BoardController, :index
      post "/boards", BoardController, :create
      get "/boards/:id", BoardController, :show
      get "/boards/:board_id/workflow", BoardController, :workflow
      get "/boards/:board_id/cards", BoardController, :cards
      get "/boards/:board_id/history", BoardController, :history

      post "/boards/:board_id/cards", CardController, :create
      patch "/cards/:id", CardController, :update
      post "/cards/:id/move", CardController, :move
      delete "/cards/:id", CardController, :delete

      get "/cards/:id", CardController, :show
      get "/cards/:id/background", CardController, :background
      post "/cards/:id/labels/:label_id/toggle", CardController, :toggle_label
      put "/cards/:id/fields/:field_id", CardController, :set_field
      post "/cards/:id/assignees", CardController, :add_assignee
      delete "/cards/:id/assignees/:user_id", CardController, :remove_assignee

      post "/cards/:card_id/notes", NoteController, :create
      patch "/notes/:id", NoteController, :update
      delete "/notes/:id", NoteController, :delete

      patch "/boards/:id", BoardController, :update
      delete "/boards/:id", BoardController, :delete

      put "/boards/:board_id/memberships/:user_id", MembershipController, :update
      delete "/boards/:board_id/memberships/:user_id", MembershipController, :delete

      get "/boards/:board_id/invites", BoardInviteController, :index
      post "/boards/:board_id/invites", BoardInviteController, :create
      delete "/boards/:board_id/invites/:id", BoardInviteController, :delete

      get "/users/invites", AppInviteController, :index
      post "/users/invites", AppInviteController, :create
      delete "/users/invites/:id", AppInviteController, :delete

      post "/boards/:board_id/subboards", SubboardController, :create
      patch "/subboards/:id", SubboardController, :update
      delete "/subboards/:id", SubboardController, :delete

      post "/boards/:board_id/labels", BoardLabelController, :create
      patch "/board_labels/:id", BoardLabelController, :update
      delete "/board_labels/:id", BoardLabelController, :delete

      # Workflow templates ---------------------------------------------
      get "/workflow_templates", TemplateController, :index
      post "/workflow_templates", TemplateController, :create
      get "/workflow_templates/:id", TemplateController, :show
      patch "/workflow_templates/:id", TemplateController, :update
      delete "/workflow_templates/:id", TemplateController, :delete

      post "/workflow_templates/:template_id/stages", TemplateController, :add_stage
      patch "/template_stages/:id", TemplateController, :update_stage
      delete "/template_stages/:id", TemplateController, :delete_stage

      post "/workflow_templates/:template_id/transitions", TemplateController, :add_transition
      delete "/template_transitions/:id", TemplateController, :delete_transition

      post "/workflow_templates/:template_id/labels", TemplateController, :add_label
      delete "/template_labels/:id", TemplateController, :delete_label

      post "/workflow_templates/:template_id/fields", TemplateController, :add_field
      patch "/template_fields/:id", TemplateController, :update_field
      delete "/template_fields/:id", TemplateController, :delete_field
    end
  end
end
