defmodule Waxx.Kanban.Card do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User

  alias Waxx.Kanban.{
    Board,
    BoardStage,
    BoardLabel,
    CardAssignee,
    CardLabel,
    CardFieldValue,
    CardNote,
    Subboard
  }

  schema "cards" do
    field :title, :string
    field :description, :string
    field :position, :integer, default: 0
    # Set on creation and refreshed on every stage move; the board's
    # `archive_terminal_after_days` setting filters out cards whose
    # current stage is terminal and that have been there longer than
    # the threshold.
    field :stage_entered_at, :utc_datetime

    belongs_to :board, Board
    belongs_to :board_stage, BoardStage
    belongs_to :subboard, Subboard
    belongs_to :created_by, User

    has_many :card_assignees, CardAssignee
    many_to_many :assignees, User, join_through: CardAssignee, on_replace: :delete

    has_many :card_labels, CardLabel
    many_to_many :labels, BoardLabel, join_through: CardLabel, on_replace: :delete

    has_many :field_values, CardFieldValue
    has_many :notes, CardNote, preload_order: [asc: :position, asc: :inserted_at]

    timestamps(type: :utc_datetime)
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [
      :board_id,
      :board_stage_id,
      :subboard_id,
      :title,
      :description,
      :position,
      :created_by_id,
      :stage_entered_at
    ])
    |> validate_required([:board_id, :board_stage_id, :title])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 10_000)
  end
end
