defmodule Waxx.Kanban.BoardActivity do
  @moduledoc """
  A single entry in a board's history log. One row per card mutation
  (created / moved / updated / deleted / assigned / labeled / field set).

  `meta` is a free-form jsonb map; the renderer in
  `WaxxWeb.BoardLive.History` formats it per-action. Storing the
  human-relevant strings (names, emails) in `meta` at write-time means
  the log keeps working even when the referenced row is later renamed
  or deleted.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Kanban.{Board, Card}

  schema "board_activities" do
    field :action, :string
    field :meta, :map, default: %{}

    belongs_to :board, Board
    belongs_to :actor, User
    belongs_to :card, Card

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(activity, attrs) do
    activity
    |> cast(attrs, [:board_id, :actor_id, :card_id, :action, :meta])
    |> validate_required([:board_id, :action])
    |> validate_length(:action, max: 64)
  end
end
