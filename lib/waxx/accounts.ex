defmodule Waxx.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Waxx.Repo

  alias Waxx.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.
  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Registers an anonymous user.
  """
  def register_anonymous_user(attrs \\ %{}) do
    %User{}
    |> User.anonymous_changeset(attrs)
    |> Repo.insert()
  end

  ## Invites ----------------------------------------------------------------

  alias Waxx.Accounts.Invite

  @doc """
  Returns true when public registration is open. When false, registration
  requires a valid invite token.
  """
  @spec registration_open?() :: boolean()
  def registration_open? do
    Application.get_env(:waxx, :registration_open, false) == true
  end

  @doc "Creates an invite token, owned by the given user."
  def create_invite(%User{id: id}, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("created_by_id", id)

    %Invite{}
    |> Invite.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an unowned (system) invite. Used by the `mix phx.gen.invite` task
  and anywhere else there is no logged-in user to attribute the invite to.
  """
  def create_system_invite(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.delete("created_by_id")

    %Invite{}
    |> Invite.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists invites created by a user, newest first, with redeemer preloaded."
  def list_invites(%User{id: id}) do
    from(i in Invite,
      where: i.created_by_id == ^id,
      order_by: [desc: i.inserted_at],
      preload: [:consumed_by]
    )
    |> Repo.all()
  end

  @doc "Looks up an invite by token and returns it if active."
  @spec get_active_invite(binary()) :: Invite.t() | nil
  def get_active_invite(token) when is_binary(token) do
    case Repo.get_by(Invite, token: token) do
      nil -> nil
      invite -> if Invite.active?(invite), do: invite, else: nil
    end
  end

  def get_active_invite(_), do: nil

  @doc "Marks an invite as consumed by the given user."
  def consume_invite(%Invite{} = invite, %User{} = user) do
    invite
    |> Invite.consume_changeset(user)
    |> Repo.update()
  end

  @doc "Revokes an invite by setting consumed_at without a consumer."
  def revoke_invite(%User{id: owner_id}, %Invite{created_by_id: owner_id} = invite) do
    invite
    |> Ecto.Changeset.change(
      consumed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      consumed_by_id: nil
    )
    |> Repo.update()
  end

  def revoke_invite(_, _), do: {:error, :forbidden}

  ## User preferences --------------------------------------------------

  @doc """
  Looks up the user's preference for hiding label *text* (showing only
  the coloured swatch) on a given board. Per-board override falls back
  to the user-wide default, which itself defaults to `false` (show text).
  """
  def hide_label_text?(%User{preferences: prefs}, board_id) do
    prefs = prefs || %{}

    Map.get(
      prefs,
      "hide_label_text:#{board_id}",
      Map.get(prefs, "hide_label_text_default", false)
    ) == true
  end

  @doc """
  Sets the per-board "hide label text" preference for `user` to `value`.

  Reloads the user from the DB first so a stale in-memory `preferences`
  (e.g. from a LiveView socket assign) doesn't clobber settings another
  session wrote. Returns `{:ok, updated_user}`.
  """
  def set_hide_label_text(%User{id: id}, board_id, value) when is_boolean(value) do
    fresh = Repo.get!(User, id)
    prefs = Map.put(fresh.preferences || %{}, "hide_label_text:#{board_id}", value)

    fresh
    |> Ecto.Changeset.change(preferences: prefs)
    |> Repo.update()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.
  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.
  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Delivers the update email instructions to the given user.
  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## API tokens (native clients) ---------------------------------------

  @doc """
  Mints a new API token for a user. Returns the encoded token string.
  Hand it to the client exactly once — the DB only stores the hash.

  Accepts an optional `attrs` map with a `:label` (or `"label"`) used to
  distinguish tokens in the device list.
  """
  def create_api_token(%User{} = user, attrs \\ %{}) do
    {encoded_token, user_token} = UserToken.build_api_token(user, attrs)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Looks up a user by API token. Returns `{user, token_id}` or `nil` if the
  token is missing, malformed, expired, or revoked. On success,
  opportunistically refreshes `authenticated_at` if it's older than the
  refresh threshold so an active client never gets logged out.

  The token_id is returned so the auth plug can assign it on the conn,
  which `DELETE /api/v1/sessions/current` uses to revoke the current
  device specifically.
  """
  def fetch_user_by_api_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_api_token_query(token),
         {user, token_struct} <- Repo.one(query) do
      maybe_touch_api_token(token_struct)
      {user, token_struct.id}
    else
      _ -> nil
    end
  end

  def fetch_user_by_api_token(_), do: nil

  defp maybe_touch_api_token(%UserToken{} = token_struct) do
    if UserToken.api_token_needs_refresh?(token_struct) do
      now = DateTime.utc_now(:second)

      Repo.update_all(
        from(t in UserToken, where: t.id == ^token_struct.id),
        set: [authenticated_at: now]
      )
    end

    :ok
  end

  @doc "Lists a user's active API tokens, newest first."
  def list_api_tokens(%User{id: id}) do
    from(t in UserToken,
      where: t.user_id == ^id and t.context == "api",
      order_by: [desc: t.authenticated_at],
      select: %{
        id: t.id,
        label: t.label,
        sent_to: t.sent_to,
        authenticated_at: t.authenticated_at,
        inserted_at: t.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc "Revokes a single API token by id, scoped to its owner."
  def delete_api_token(%User{id: user_id}, token_id) do
    {count, _} =
      Repo.delete_all(
        from(t in UserToken,
          where: t.id == ^token_id and t.user_id == ^user_id and t.context == "api"
        )
      )

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
