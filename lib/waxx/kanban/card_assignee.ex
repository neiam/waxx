defmodule Waxx.Kanban.CardAssignee do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Kanban.Card

  schema "card_assignees" do
    belongs_to :card, Card
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(assignee, attrs) do
    assignee
    |> cast(attrs, [:card_id, :user_id])
    |> validate_required([:card_id, :user_id])
    |> unique_constraint([:card_id, :user_id])
  end
end
