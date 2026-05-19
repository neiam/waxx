defmodule Waxx.Kanban.BoardInvite do
  @moduledoc """
  Board-scoped invite token. Redeemed at `/b/:token` to grant membership
  on a specific board. Separate from the app-level `Waxx.Accounts.Invite`,
  which grants account creation rights.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Kanban.Board

  @roles ~w(editor viewer)

  schema "board_invites" do
    field :token, :string
    field :role, :string, default: "editor"
    field :note, :string
    field :expires_at, :utc_datetime
    field :consumed_at, :utc_datetime

    belongs_to :board, Board
    belongs_to :created_by, User
    belongs_to :consumed_by, User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def create_changeset(invite, attrs) do
    invite
    |> cast(attrs, [:board_id, :role, :note, :created_by_id, :expires_at])
    |> put_token_if_missing()
    |> validate_required([:board_id, :token, :role])
    |> validate_inclusion(:role, @roles)
    |> validate_length(:note, max: 200)
    |> unique_constraint(:token)
  end

  def consume_changeset(invite, %User{id: user_id}) do
    if invite.consumed_at do
      change(invite)
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      change(invite, consumed_at: now, consumed_by_id: user_id)
    end
  end

  @spec active?(%__MODULE__{}) :: boolean()
  def active?(%__MODULE__{consumed_at: nil, expires_at: nil}), do: true

  def active?(%__MODULE__{consumed_at: nil, expires_at: %DateTime{} = exp}) do
    DateTime.compare(exp, DateTime.utc_now()) == :gt
  end

  def active?(_), do: false

  defp put_token_if_missing(changeset) do
    case get_field(changeset, :token) do
      nil -> put_change(changeset, :token, generate_token())
      _ -> changeset
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end
end
