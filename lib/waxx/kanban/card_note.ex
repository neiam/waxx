defmodule Waxx.Kanban.CardNote do
  @moduledoc """
  An ad-hoc note or todo item attached to a card. Each row remembers
  which stage it was created in — the kanban view renders it with that
  stage's color even after the card has moved on, so the journal stays
  legible. `kind` discriminates between freeform notes and checkable
  todos; `done` is only meaningful for `"todo"` rows.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Kanban.{Card, BoardStage}

  @kinds ~w(note todo)

  schema "card_notes" do
    field :body, :string
    field :kind, :string, default: "note"
    field :done, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :card, Card
    belongs_to :board_stage, BoardStage
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :card_id,
      :board_stage_id,
      :body,
      :kind,
      :done,
      :position,
      :created_by_id
    ])
    |> validate_required([:card_id, :body, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:body, max: 2000)
    |> check_constraint(:kind, name: :card_notes_kind_check)
  end
end
