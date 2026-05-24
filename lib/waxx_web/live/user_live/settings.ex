defmodule WaxxWeb.UserLive.Settings do
  use WaxxWeb, :live_view

  on_mount {WaxxWeb.UserAuth, :require_sudo_mode}

  alias Waxx.Accounts
  alias WaxxWeb.{PublicUrl, QR}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="text-center">
        <.header>
          Account Settings
          <:subtitle>Manage your account email address and password settings</:subtitle>
        </.header>
      </div>

      <.form for={@email_form} id="email_form" phx-submit="update_email" phx-change="validate_email">
        <.input
          field={@email_form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button variant="primary" phx-disable-with="Changing...">Change Email</.button>
      </.form>

      <div class="divider" />

      <.form
        for={@password_form}
        id="password_form"
        action={~p"/users/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="Saving...">
          Save Password
        </.button>
      </.form>

      <div class="divider" />

      <section id="api-tokens" class="text-left">
        <.header>
          Connected devices
          <:subtitle>
            API tokens issued to native clients (Android, scripts). Generate one
            here and scan the QR with the app to pair it.
          </:subtitle>
        </.header>

        <.form
          for={@token_form}
          id="token_form"
          phx-submit="generate_api_token"
          class="mt-4"
        >
          <.input
            field={@token_form[:label]}
            type="text"
            label="Label (optional)"
            placeholder="e.g. Pixel 7, kitchen"
            maxlength="80"
          />
          <.button variant="primary" phx-disable-with="Generating...">
            Generate token
          </.button>
        </.form>

        <div :if={@just_created} class="card bg-base-200 p-4 mt-6 space-y-3">
          <div class="alert alert-warning">
            <.icon name="hero-exclamation-triangle" class="size-5" />
            <span>
              This is the only time the full token will be shown. Scan or copy it now.
            </span>
          </div>

          <div class="flex flex-col md:flex-row items-center gap-4">
            <div class="bg-white p-3 rounded">
              {raw(@just_created.qr_svg)}
            </div>
            <div class="space-y-2 text-sm break-all">
              <div><strong>Server URL</strong></div>
              <code class="text-xs block">{@just_created.base_url}</code>
              <div><strong>Token</strong></div>
              <code class="text-xs block">{@just_created.token}</code>
              <div><strong>Pairing URI</strong></div>
              <code class="text-xs block">{@just_created.pair_uri}</code>
            </div>
          </div>

          <div>
            <button
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="dismiss_token_panel"
            >
              Done — hide
            </button>
          </div>
        </div>

        <div class="mt-6">
          <h3 class="font-bold mb-2">Active tokens</h3>
          <div :if={@api_tokens == []} class="text-sm opacity-70">
            No tokens yet. Generate one above to pair a device.
          </div>
          <ul :if={@api_tokens != []} class="divide-y divide-base-300">
            <li
              :for={t <- @api_tokens}
              id={"api-token-" <> t.id}
              class="flex items-center justify-between py-2"
            >
              <div class="text-sm">
                <div class="font-medium">
                  {t.label || "(no label)"}
                </div>
                <div class="opacity-70 text-xs">
                  Issued {format_ts(t.inserted_at)} ·
                  Last seen {format_ts(t.authenticated_at)}
                </div>
              </div>
              <button
                type="button"
                class="btn btn-ghost btn-sm text-error"
                phx-click="revoke_api_token"
                phx-value-id={t.id}
                data-confirm="Revoke this token? The paired device will be logged out."
              >
                Revoke
              </button>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_scope.user, token) do
        {:ok, _user} ->
          put_flash(socket, :info, "Email changed successfully.")

        {:error, _} ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:token_form, to_form(%{"label" => ""}, as: "token"))
      |> assign(:just_created, nil)
      |> assign(:api_tokens, Accounts.list_api_tokens(user))
      |> assign(:public_base_url, PublicUrl.derive(socket))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm-email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("generate_api_token", %{"token" => params}, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    encoded = Accounts.create_api_token(user, params)
    base_url = socket.assigns.public_base_url
    pair_uri = "waxx://pair?" <> URI.encode_query(%{base: base_url, token: encoded})

    just_created = %{
      token: encoded,
      base_url: base_url,
      pair_uri: pair_uri,
      qr_svg: QR.svg(pair_uri)
    }

    {:noreply,
     socket
     |> assign(:just_created, just_created)
     |> assign(:token_form, to_form(%{"label" => ""}, as: "token"))
     |> assign(:api_tokens, Accounts.list_api_tokens(user))}
  end

  def handle_event("revoke_api_token", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user
    _ = Accounts.delete_api_token(user, id)

    {:noreply, assign(socket, :api_tokens, Accounts.list_api_tokens(user))}
  end

  def handle_event("dismiss_token_panel", _params, socket) do
    {:noreply, assign(socket, :just_created, nil)}
  end

  defp format_ts(nil), do: "—"

  defp format_ts(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end
end
