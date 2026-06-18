defmodule Waxx.Kanban.BoardLabel do
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Kanban.{Board, Subboard}

  schema "board_labels" do
    field :name, :string
    field :color, :string

    belongs_to :board, Board

    # Subboards this label is restricted to. Empty = board-wide (the label
    # applies to every card regardless of subboard). Managed via put_assoc
    # in Waxx.Kanban; `on_replace: :delete` clears the old scope on update.
    many_to_many :subboards, Subboard,
      join_through: Waxx.Kanban.BoardLabelSubboard,
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(label, attrs) do
    label
    |> cast(attrs, [:board_id, :name, :color])
    |> validate_required([:board_id, :name])
    |> validate_length(:name, max: 60)
    |> validate_length(:color, max: 32)
    |> unique_constraint([:board_id, :name])
  end

  @doc """
  True when this label may be applied to a card sitting in `subboard_id`.
  A board-wide label (no subboard scope) applies everywhere; a scoped label
  only applies inside its subboards. Requires `:subboards` to be loaded.
  """
  def applies_to_subboard?(%__MODULE__{subboards: subboards}, subboard_id)
      when is_list(subboards) do
    subboards == [] or Enum.any?(subboards, &(&1.id == subboard_id))
  end
end
