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

  scope "/", WaxxWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", WaxxWeb do
  #   pipe_through :api
  # end

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
    end
  end
end
