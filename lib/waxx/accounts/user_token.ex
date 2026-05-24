defmodule Waxx.Accounts.UserToken do
  use Waxx.Schema
  import Ecto.Query
  alias Waxx.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # It is very important to keep the magic link token expiry short,
  # since someone with access to the email may take over the account.
  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 14

  # API tokens (context "api") issued to native clients. Expiry is measured
  # against authenticated_at, which is bumped by the auth plug at most once
  # per refresh window so an active client never gets logged out.
  @api_token_validity_in_days 90
  @api_token_refresh_after_seconds 24 * 60 * 60

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :label, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, Waxx.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.
  """
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the magic link token is valid and returns its underlying lookup query.
  """
  def verify_magic_link_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, "login"),
            join: user in assoc(token, :user),
            where: token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
            where: token.sent_to == user.email,
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Checks if the email-change token is valid and returns its underlying lookup query.
  """
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end

  ## API tokens ---------------------------------------------------------

  @doc """
  Builds an API token for native clients. Returns `{encoded_token, struct}`
  — the caller is expected to insert the struct and hand `encoded_token`
  back to the client over a secure channel exactly once.

  Accepts an optional `label` (e.g. "Pixel 7, kitchen") to distinguish
  tokens in the device list.
  """
  def build_api_token(user, attrs \\ %{}) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)
    now = DateTime.utc_now(:second)
    label = attrs |> normalise_label() |> truncate_label()

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: "api",
       sent_to: user.email,
       label: label,
       authenticated_at: now,
       user_id: user.id
     }}
  end

  defp normalise_label(attrs) do
    case Map.get(attrs, :label) || Map.get(attrs, "label") do
      nil -> nil
      str when is_binary(str) -> str |> String.trim() |> nil_if_empty()
      _ -> nil
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  defp truncate_label(nil), do: nil
  defp truncate_label(s), do: String.slice(s, 0, 80)

  @doc """
  Looks up an API token. Returns `{:ok, query}` selecting `{user, token}`
  if the encoded token decodes; `:error` otherwise. The query enforces
  the @api_token_validity_in_days window against `authenticated_at`.
  """
  def verify_api_token_query(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, "api"),
            join: user in assoc(token, :user),
            where: token.authenticated_at > ago(@api_token_validity_in_days, "day"),
            select: {user, token}

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns true if the API token's `authenticated_at` is stale enough to
  warrant a refresh write. Lets the auth plug skip the DB write on the
  common path where the token was used recently.
  """
  def api_token_needs_refresh?(%UserToken{context: "api", authenticated_at: ts}) do
    DateTime.diff(DateTime.utc_now(:second), ts, :second) >= @api_token_refresh_after_seconds
  end
end
