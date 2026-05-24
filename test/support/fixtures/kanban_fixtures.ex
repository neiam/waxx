defmodule Waxx.KanbanFixtures do
  @moduledoc """
  Test helpers for building boards, templates, and cards. Mirrors the
  small inline helpers used in `Waxx.KanbanTest` so controller-level
  tests can reuse them.
  """

  alias Waxx.{Workflows, Kanban}
  alias Waxx.Accounts.User

  @doc """
  Builds a template with two stages (Todo → Done) and one transition.
  """
  def template_fixture(%User{} = user, attrs \\ %{}) do
    attrs = Map.new(attrs)
    name = Map.get(attrs, :name, "Simple")
    {:ok, template} = Workflows.create_template(user, %{"name" => name, "description" => "x"})
    {:ok, todo} = Workflows.add_stage(template, %{"name" => "Todo"})
    {:ok, done} = Workflows.add_stage(template, %{"name" => "Done"})
    {:ok, _} = Workflows.add_transition(template, todo.id, done.id, "ship it")
    Workflows.get_template!(template.id)
  end

  @doc "Creates a board owned by `user` cloned from a fresh template."
  def board_fixture(%User{} = user, attrs \\ %{}) do
    attrs = Map.new(attrs)
    name = Map.get(attrs, :name, "Board #{System.unique_integer([:positive])}")
    template = template_fixture(user)
    {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => name})
    board
  end

  @doc "Creates a card on a board, attributed to `user`."
  def card_fixture(board, %User{} = user, attrs \\ %{}) do
    attrs = Map.new(attrs)
    attrs = Map.put_new(attrs, "title", "Card #{System.unique_integer([:positive])}")
    {:ok, card} = Kanban.create_card(board, user, attrs)
    card
  end

  @doc "Adds a label directly to a board (bypasses template propagation)."
  def board_label_fixture(board, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, label} =
      %Waxx.Kanban.BoardLabel{}
      |> Waxx.Kanban.BoardLabel.changeset(%{
        board_id: board.id,
        name: Map.get(attrs, :name, "Label #{System.unique_integer([:positive])}"),
        color: Map.get(attrs, :color, "#888888")
      })
      |> Waxx.Repo.insert()

    label
  end

  @doc "Adds a field directly to a board (bypasses template propagation)."
  def board_field_fixture(board, attrs \\ %{}) do
    attrs = Map.new(attrs)

    {:ok, field} =
      %Waxx.Kanban.BoardField{}
      |> Waxx.Kanban.BoardField.changeset(%{
        board_id: board.id,
        name: Map.get(attrs, :name, "field_#{System.unique_integer([:positive])}"),
        kind: Map.get(attrs, :kind, "text"),
        options: Map.get(attrs, :options),
        position: Map.get(attrs, :position, 0)
      })
      |> Waxx.Repo.insert()

    field
  end
end
