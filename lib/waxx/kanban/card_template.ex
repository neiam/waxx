defmodule Waxx.Kanban.CardTemplate do
  @moduledoc """
  Per-board snapshot of a card that can be used to seed new cards.

  The `snapshot` map captures everything portable about a card:

      %{
        "title" => "...",
        "description" => "...",
        "label_names" => ["bug", "urgent"],
        "field_values" => %{"due" => "...", "location" => "..."},
        "notes" => [%{"kind" => "todo", "body" => "...", "done" => false}, ...]
      }

  Label and field references are stored by *name* so the snapshot
  survives renames on the board side — they resolve at creation time.
  Card-template rows live on a single board; copying a template to
  another board is a future feature.
  """
  use Waxx.Schema
  import Ecto.Changeset

  alias Waxx.Accounts.User
  alias Waxx.Kanban.Board

  schema "card_templates" do
    field :name, :string
    field :snapshot, :map, default: %{}

    belongs_to :board, Board
    belongs_to :created_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(template, attrs) do
    template
    |> cast(attrs, [:board_id, :name, :snapshot, :created_by_id])
    |> validate_required([:board_id, :name])
    |> validate_length(:name, max: 120)
    |> unique_constraint([:board_id, :name])
  end
end
