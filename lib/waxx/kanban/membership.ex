defmodule Waxx.Kanban.Membership do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Kanban.Board

  @roles ~w(owner editor viewer)

  schema "board_memberships" do
    field :role, :string, default: "editor"

    belongs_to :board, Board
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def roles, do: @roles

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:board_id, :user_id, :role])
    |> validate_required([:board_id, :user_id, :role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:board_id, :user_id])
  end
end
