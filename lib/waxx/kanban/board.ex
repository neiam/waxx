defmodule Waxx.Kanban.Board do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Workflows.Template

  alias Waxx.Kanban.{
    BoardStage,
    BoardTransition,
    BoardLabel,
    BoardField,
    BoardActivity,
    CardTemplate,
    Subboard,
    Membership,
    BoardInvite,
    Card
  }

  schema "boards" do
    field :name, :string
    field :description, :string
    # Number of days a card may sit in a terminal stage (one with no
    # outgoing transitions) before it stops appearing in the kanban view.
    # `nil` disables auto-archiving on this board.
    field :archive_terminal_after_days, :integer, default: 7

    belongs_to :owner, User
    belongs_to :template, Template

    has_many :stages, BoardStage, preload_order: [asc: :position]
    has_many :transitions, BoardTransition
    has_many :labels, BoardLabel, preload_order: [asc: :name]
    has_many :fields, BoardField, preload_order: [asc: :position, asc: :id]
    has_many :subboards, Subboard, preload_order: [asc: :position, asc: :inserted_at]
    has_many :memberships, Membership
    has_many :invites, BoardInvite
    has_many :cards, Card
    has_many :activities, BoardActivity
    has_many :card_templates, CardTemplate, preload_order: [asc: :name]

    timestamps(type: :utc_datetime)
  end

  def changeset(board, attrs) do
    board
    |> cast(attrs, [
      :name,
      :description,
      :owner_id,
      :template_id,
      :archive_terminal_after_days
    ])
    |> validate_required([:name, :owner_id])
    |> validate_length(:name, max: 120)
    |> validate_length(:description, max: 1000)
    |> validate_number(:archive_terminal_after_days, greater_than: 0)
  end
end
