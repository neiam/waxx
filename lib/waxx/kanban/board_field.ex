defmodule Waxx.Kanban.BoardField do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.{Board, CardFieldValue}

  @kinds ~w(text date datetime select)

  schema "board_fields" do
    field :name, :string
    field :kind, :string
    field :options, {:array, :string}
    field :show_on_card, :boolean, default: false
    field :position, :integer, default: 0

    belongs_to :board, Board
    has_many :card_field_values, CardFieldValue

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(field, attrs) do
    field
    |> cast(attrs, [:board_id, :name, :kind, :options, :show_on_card, :position])
    |> validate_required([:board_id, :name, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_length(:name, max: 60)
    |> unique_constraint([:board_id, :name])
    |> check_constraint(:kind, name: :bf_kind_check)
  end
end
