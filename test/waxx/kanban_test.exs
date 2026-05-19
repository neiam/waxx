defmodule Waxx.KanbanTest do
  use Waxx.DataCase, async: true

  alias Waxx.{Workflows, Kanban}
  alias Waxx.AccountsFixtures

  describe "create_board_from_template/3" do
    test "clones template stages + transitions into per-board copies and grants owner membership" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      [from_t, to_t] = template.stages
      [transition] = template.transitions

      {:ok, board} =
        Kanban.create_board_from_template(user, template, %{"name" => "Sprint board"})

      assert board.name == "Sprint board"
      assert board.owner_id == user.id
      assert length(board.stages) == 2

      # Per-board stages are independent rows — editing one shouldn't touch
      # the other. We don't assert id-disjointness because separate tables
      # can share numeric ids; the structural check below covers what matters.
      _ = {from_t, to_t}

      assert length(board.transitions) == 1
      [bt] = board.transitions

      # Names match — graph topology is preserved.
      from_stage = Enum.find(board.stages, &(&1.id == bt.from_stage_id))
      to_stage = Enum.find(board.stages, &(&1.id == bt.to_stage_id))
      assert from_stage.name == "Todo"
      assert to_stage.name == "Done"
      assert bt.label == transition.label

      # Membership row created with `owner` role.
      assert Kanban.role_for(board.id, user) == "owner"
    end
  end

  describe "move_card/2" do
    setup do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})
      [from_stage, to_stage] = board.stages
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})

      %{user: user, board: board, from: from_stage, to: to_stage, card: card}
    end

    test "allows moves along a defined transition", %{card: card, to: to} do
      card = Kanban.get_card(card.id)
      assert {:ok, moved} = Kanban.move_card(card, to.id)
      assert moved.board_stage_id == to.id
    end

    test "rejects moves with no transition edge", %{card: card, to: to, board: board} do
      # First move card forward (legal), then attempt to move it back — there's
      # no Done → Todo transition.
      card = Kanban.get_card(card.id)
      {:ok, _} = Kanban.move_card(card, to.id)
      card = Kanban.get_card(card.id)
      [from_stage, _] = board.stages

      assert {:error, :invalid_transition} = Kanban.move_card(card, from_stage.id)
    end

    test "rejects moves to a stage on a different board", %{card: card} do
      user2 = AccountsFixtures.user_fixture()
      template2 = build_template_with_two_stages_and_transition(user2)

      {:ok, other_board} =
        Kanban.create_board_from_template(user2, template2, %{"name" => "Other"})

      [stage_on_other, _] = other_board.stages

      card = Kanban.get_card(card.id)
      assert {:error, :invalid_stage} = Kanban.move_card(card, stage_on_other.id)
    end
  end

  describe "terminal-stage archive" do
    test "hides cards in a terminal stage older than the threshold" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)

      {:ok, board} =
        Kanban.create_board_from_template(user, template, %{
          "name" => "B",
          "archive_terminal_after_days" => 1
        })

      [_todo, done] = board.stages
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      {:ok, _} = Kanban.move_card(Kanban.get_card(card.id), done.id)

      # Backdate stage_entered_at past the threshold.
      past = DateTime.add(DateTime.utc_now(:second), -2 * 86_400, :second)

      Waxx.Repo.update_all(
        Ecto.Query.from(c in Waxx.Kanban.Card, where: c.id == ^card.id),
        set: [stage_entered_at: past]
      )

      board = Kanban.get_board_with_workflow!(board.id, user)
      assert Kanban.list_cards(board) == []
    end

    test "keeps the card visible if it just entered the terminal stage" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)

      {:ok, board} =
        Kanban.create_board_from_template(user, template, %{
          "name" => "B",
          "archive_terminal_after_days" => 1
        })

      [_todo, done] = board.stages
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      {:ok, _} = Kanban.move_card(Kanban.get_card(card.id), done.id)

      board = Kanban.get_board_with_workflow!(board.id, user)
      cards = Kanban.list_cards(board)
      assert [%{id: id}] = cards
      assert id == card.id
    end

    test "nil threshold disables archiving" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)

      {:ok, board} =
        Kanban.create_board_from_template(user, template, %{
          "name" => "B",
          "archive_terminal_after_days" => nil
        })

      [_todo, done] = board.stages
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      {:ok, _} = Kanban.move_card(Kanban.get_card(card.id), done.id)

      past = DateTime.add(DateTime.utc_now(:second), -365 * 86_400, :second)

      Waxx.Repo.update_all(
        Ecto.Query.from(c in Waxx.Kanban.Card, where: c.id == ^card.id),
        set: [stage_entered_at: past]
      )

      board = Kanban.get_board_with_workflow!(board.id, user)
      cards = Kanban.list_cards(board)
      assert length(cards) == 1
    end
  end

  describe "custom fields" do
    test "create_board_from_template clones template fields onto the board" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)

      {:ok, _} =
        Waxx.Workflows.add_field(template, %{
          "name" => "due",
          "kind" => "date",
          "show_on_card" => true
        })

      {:ok, _} =
        Waxx.Workflows.add_field(template, %{
          "name" => "location",
          "kind" => "select",
          "options" => ["NYC", "SF"]
        })

      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      board = Kanban.get_board_with_workflow!(board.id, user)
      names = Enum.map(board.fields, & &1.name) |> Enum.sort()
      assert names == ["due", "location"]

      loc = Enum.find(board.fields, &(&1.name == "location"))
      assert loc.options == ["NYC", "SF"]
    end

    test "set_card_field_value normalizes by kind and validates select options" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)

      {:ok, _} = Waxx.Workflows.add_field(template, %{"name" => "due", "kind" => "date"})

      {:ok, _} =
        Waxx.Workflows.add_field(template, %{
          "name" => "location",
          "kind" => "select",
          "options" => ["NYC", "SF"]
        })

      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})
      board = Kanban.get_board_with_workflow!(board.id, user)
      due = Enum.find(board.fields, &(&1.name == "due"))
      loc = Enum.find(board.fields, &(&1.name == "location"))

      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})

      # Valid date
      assert {:ok, _} = Kanban.set_card_field_value(card, due, "2026-05-20")

      # Invalid date
      assert {:error, :invalid_value} =
               Kanban.set_card_field_value(card, due, "not-a-date")

      # Valid select option
      assert {:ok, _} = Kanban.set_card_field_value(card, loc, "NYC")

      # Invalid select option
      assert {:error, :invalid_option} =
               Kanban.set_card_field_value(card, loc, "Paris")

      # Clearing
      assert {:ok, _} = Kanban.set_card_field_value(card, due, "")

      reloaded = Kanban.get_card(card.id)
      values = Map.new(reloaded.field_values, &{&1.board_field_id, &1.value})
      refute Map.has_key?(values, due.id)
      assert values[loc.id] == "NYC"
    end

    test "set_card_field_value rejects a field from another board" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, _} = Waxx.Workflows.add_field(template, %{"name" => "due", "kind" => "date"})
      {:ok, board_a} = Kanban.create_board_from_template(user, template, %{"name" => "A"})
      {:ok, board_b} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      board_a = Kanban.get_board_with_workflow!(board_a.id, user)
      [field_a] = board_a.fields

      {:ok, card_b} = Kanban.create_card(board_b, user, %{"title" => "T"})

      assert {:error, :invalid_field} =
               Kanban.set_card_field_value(card_b, field_a, "2026-01-01")
    end

    test "adding a template field propagates to existing boards" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      :ok = Kanban.subscribe(board.id)

      {:ok, _} =
        Waxx.Workflows.add_field(template, %{
          "name" => "priority",
          "kind" => "select",
          "options" => ["low", "high"]
        })

      assert_receive {:workflow_changed, _}
      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      assert Enum.any?(refreshed.fields, &(&1.name == "priority"))
    end

    test "removing a template field keeps it on boards where a card still has a value" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)

      {:ok, tmpl_field} =
        Waxx.Workflows.add_field(template, %{"name" => "due", "kind" => "date"})

      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})
      board = Kanban.get_board_with_workflow!(board.id, user)
      [bf] = board.fields

      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      {:ok, _} = Kanban.set_card_field_value(card, bf, "2026-05-20")

      {:ok, _} = Waxx.Workflows.delete_field(tmpl_field)

      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      assert Enum.any?(refreshed.fields, &(&1.name == "due"))
    end
  end

  describe "subboards" do
    test "cards start in the default row and can be moved into a subboard" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      {:ok, sb} = Kanban.create_subboard(board, %{"name" => "Frontend"})
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})

      assert card.subboard_id == nil

      assert {:ok, moved} = Kanban.set_card_subboard(Kanban.get_card(card.id), sb)
      assert moved.subboard_id == sb.id
    end

    test "set_card_subboard rejects a subboard from another board" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board_a} = Kanban.create_board_from_template(user, template, %{"name" => "A"})
      {:ok, board_b} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      {:ok, sb_a} = Kanban.create_subboard(board_a, %{"name" => "X"})
      {:ok, card_b} = Kanban.create_card(board_b, user, %{"title" => "T"})

      assert {:error, :invalid_subboard} = Kanban.set_card_subboard(card_b, sb_a)
    end

    test "deleting a subboard falls cards back to the default row" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      {:ok, sb} = Kanban.create_subboard(board, %{"name" => "Frontend"})
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      {:ok, _} = Kanban.set_card_subboard(Kanban.get_card(card.id), sb)
      {:ok, _} = Kanban.delete_subboard(sb)

      reloaded = Kanban.get_card(card.id)
      assert reloaded.subboard_id == nil
    end
  end

  describe "labels" do
    test "create_board_from_template clones template labels onto the board" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, _l1} = Waxx.Workflows.add_label(template, %{"name" => "bug", "color" => "#ef4444"})
      {:ok, _l2} = Waxx.Workflows.add_label(template, %{"name" => "chore"})

      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      assert Enum.map(board.labels, & &1.name) |> Enum.sort() == ["bug", "chore"]
    end

    test "toggle_card_label adds and then removes the label" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, _} = Waxx.Workflows.add_label(template, %{"name" => "bug"})
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})
      [label] = board.labels

      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})

      {:ok, _} = Kanban.toggle_card_label(card, label)
      reloaded = Kanban.get_card(card.id)
      assert Enum.map(reloaded.labels, & &1.id) == [label.id]

      {:ok, _} = Kanban.toggle_card_label(reloaded, label)
      reloaded2 = Kanban.get_card(card.id)
      assert reloaded2.labels == []
    end

    test "toggle_card_label rejects a label from a different board" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, _} = Waxx.Workflows.add_label(template, %{"name" => "bug"})
      {:ok, board_a} = Kanban.create_board_from_template(user, template, %{"name" => "A"})
      {:ok, board_b} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      [label_a] = board_a.labels
      {:ok, card_b} = Kanban.create_card(board_b, user, %{"title" => "T"})

      assert {:error, :invalid_label} = Kanban.toggle_card_label(card_b, label_a)
    end

    test "adding a label to a template propagates to existing boards" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      :ok = Kanban.subscribe(board.id)
      {:ok, _} = Waxx.Workflows.add_label(template, %{"name" => "urgent", "color" => "#f00"})

      assert_receive {:workflow_changed, _}
      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      assert Enum.any?(refreshed.labels, &(&1.name == "urgent"))
    end

    test "removing a template label keeps the board label when a card still uses it" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)

      {:ok, tmpl_label} = Waxx.Workflows.add_label(template, %{"name" => "bug"})
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})
      [board_label] = board.labels

      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      {:ok, _} = Kanban.toggle_card_label(card, board_label)

      {:ok, _} = Waxx.Workflows.delete_label(tmpl_label)

      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      assert Enum.any?(refreshed.labels, &(&1.name == "bug"))
    end
  end

  describe "template → board propagation" do
    test "renaming a template stage renames the matching board stage" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      [todo, _done] = template.stages
      {:ok, _} = Waxx.Workflows.update_stage(todo, %{"name" => "Backlog"})

      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      assert Enum.any?(refreshed.stages, &(&1.name == "Backlog"))
      refute Enum.any?(refreshed.stages, &(&1.name == "Todo"))
    end

    test "renaming a template stage skips boards where another stage already has the new name" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      # Drift: the board adds its own "Backlog" stage.
      board_with_workflow = Kanban.get_board_with_workflow!(board.id, user)
      todo_board = Enum.find(board_with_workflow.stages, &(&1.name == "Todo"))

      {:ok, _} =
        Waxx.Repo.insert(
          Waxx.Kanban.BoardStage.changeset(%Waxx.Kanban.BoardStage{}, %{
            board_id: board.id,
            name: "Backlog",
            position: 99
          })
        )

      [todo_tmpl, _] = template.stages
      {:ok, _} = Waxx.Workflows.update_stage(todo_tmpl, %{"name" => "Backlog"})

      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      # The drifted board still has the original "Todo" stage; no collision.
      assert Enum.any?(refreshed.stages, &(&1.id == todo_board.id and &1.name == "Todo"))
    end

    test "adding a stage to a template inserts the stage into existing boards" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      :ok = Kanban.subscribe(board.id)
      {:ok, _new_stage} = Waxx.Workflows.add_stage(template, %{"name" => "QA"})

      assert_receive {:workflow_changed, board_id}
      assert board_id == board.id

      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      assert Enum.any?(refreshed.stages, &(&1.name == "QA"))
    end

    test "adding a transition propagates by stage names" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})
      {:ok, _qa} = Waxx.Workflows.add_stage(template, %{"name" => "QA"})

      # Drain the stage propagation broadcast.
      :ok = Kanban.subscribe(board.id)
      _ = drain_workflow_changed()

      [todo, _done, qa] = Waxx.Workflows.get_template!(template.id).stages
      {:ok, _} = Waxx.Workflows.add_transition(template, todo.id, qa.id, "to QA")

      assert_receive {:workflow_changed, _}

      refreshed = Kanban.get_board_with_workflow!(board.id, user)

      assert Enum.any?(refreshed.transitions, fn t ->
               t.from_stage.name == "Todo" and t.to_stage.name == "QA"
             end)
    end

    test "removing a stage skips boards where the stage still has cards" do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, qa_tmpl_stage} = Waxx.Workflows.add_stage(template, %{"name" => "QA"})
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})

      qa_board_stage = Enum.find(board.stages, &(&1.name == "QA"))

      {:ok, _card} =
        Kanban.create_card(board, user, %{"title" => "X", "board_stage_id" => qa_board_stage.id})

      :ok =
        Waxx.Workflows.delete_stage(qa_tmpl_stage)
        |> elem(0)
        |> case do
          :ok -> :ok
        end

      # Board still has the stage because it had a card.
      refreshed = Kanban.get_board_with_workflow!(board.id, user)
      assert Enum.any?(refreshed.stages, &(&1.name == "QA"))
    end
  end

  defp drain_workflow_changed do
    receive do
      {:workflow_changed, _} -> drain_workflow_changed()
    after
      20 -> :ok
    end
  end

  describe "PubSub broadcasts" do
    setup do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "B"})
      [_from_stage, to_stage] = board.stages

      :ok = Kanban.subscribe(board.id)
      %{user: user, board: board, to: to_stage}
    end

    test "create_card broadcasts :cards_changed", %{user: user, board: board} do
      {:ok, _} = Kanban.create_card(board, user, %{"title" => "T"})
      assert_receive {:cards_changed, board_id}
      assert board_id == board.id
    end

    test "move_card broadcasts on a legal move", %{user: user, board: board, to: to} do
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      # Drain the create broadcast first.
      assert_receive {:cards_changed, _}

      {:ok, _} = Kanban.move_card(Kanban.get_card(card.id), to.id)
      assert_receive {:cards_changed, board_id}
      assert board_id == board.id
    end

    test "move_card does NOT broadcast on a rejected move", %{user: user, board: board} do
      {:ok, card} = Kanban.create_card(board, user, %{"title" => "T"})
      assert_receive {:cards_changed, _}

      # No transition from the first stage back to itself, and the second
      # stage's only edge is incoming — no outgoing edge → invalid move.
      [from_stage, to_stage] = board.stages
      {:ok, _} = Kanban.move_card(Kanban.get_card(card.id), to_stage.id)
      assert_receive {:cards_changed, _}

      assert {:error, :invalid_transition} =
               Kanban.move_card(Kanban.get_card(card.id), from_stage.id)

      refute_receive {:cards_changed, _}, 50
    end
  end

  describe "reorder_card/2 + move_card/3 with index" do
    setup do
      user = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(user)
      {:ok, board} = Kanban.create_board_from_template(user, template, %{"name" => "R"})
      [from_stage, to_stage] = board.stages

      {:ok, a} = Kanban.create_card(board, user, %{"title" => "A"})
      {:ok, b} = Kanban.create_card(board, user, %{"title" => "B"})
      {:ok, c} = Kanban.create_card(board, user, %{"title" => "C"})

      %{user: user, board: board, from: from_stage, to: to_stage, a: a, b: b, c: c}
    end

    test "reorder_card moves card to a new 0-based index in its column",
         %{board: board, a: a, b: b, c: c} do
      assert {:ok, _} = Kanban.reorder_card(Kanban.get_card(c.id), 0)

      # Re-fetch and check order.
      cards = Kanban.list_cards(board) |> Enum.map(& &1.id)
      assert cards == [c.id, a.id, b.id]
    end

    test "move_card with index inserts at that slot in the target column",
         %{board: board, to: to, a: a} do
      # First seed two cards already in the target column so we have positions to insert between.
      {:ok, _b_in_to} = move_to_stage(board, %{title: "B-in-to"}, to)
      {:ok, _c_in_to} = move_to_stage(board, %{title: "C-in-to"}, to)

      # Move A from the source column to index 1 of the target column.
      assert {:ok, _} = Kanban.move_card(Kanban.get_card(a.id), to.id, 1)

      cards_in_to =
        Kanban.list_cards(board)
        |> Enum.filter(&(&1.board_stage_id == to.id))
        |> Enum.map(& &1.title)

      assert Enum.at(cards_in_to, 1) == "A"
    end
  end

  defp move_to_stage(board, %{title: title}, %{id: stage_id}) do
    # Helper: create on the first stage then move into target.
    {:ok, c} = Kanban.create_card(board, board_owner(board), %{"title" => title})
    # If target is the same as source, just return; otherwise move.
    if c.board_stage_id == stage_id do
      {:ok, c}
    else
      Kanban.move_card(c, stage_id)
    end
  end

  defp board_owner(board) do
    [%{user: u} | _] = Waxx.Kanban.list_members(board.id)
    u
  end

  describe "list_boards_for/1" do
    test "only returns boards the user has a membership on" do
      owner = AccountsFixtures.user_fixture()
      stranger = AccountsFixtures.user_fixture()

      template = build_template_with_two_stages_and_transition(owner)
      {:ok, board} = Kanban.create_board_from_template(owner, template, %{"name" => "Mine"})

      assert [%{id: id}] = Kanban.list_boards_for(owner)
      assert id == board.id
      assert [] = Kanban.list_boards_for(stranger)
    end
  end

  describe "redeem_board_invite/2" do
    test "joins a logged-in user, marks the invite consumed, and is idempotent" do
      owner = AccountsFixtures.user_fixture()
      guest = AccountsFixtures.user_fixture()
      template = build_template_with_two_stages_and_transition(owner)
      {:ok, board} = Kanban.create_board_from_template(owner, template, %{"name" => "Shared"})

      {:ok, invite} = Kanban.create_board_invite(board, owner, %{"role" => "editor"})
      assert {:ok, %{id: joined_id}} = redeem(invite, guest)
      assert joined_id == board.id
      assert Kanban.role_for(board.id, guest) == "editor"

      # Re-redeeming the (now consumed) invite fails — `active?` returns false.
      assert {:error, :inactive} =
               invite
               |> reload_invite()
               |> Kanban.redeem_board_invite(guest)
    end
  end

  ## -- helpers --------------------------------------------------------------

  defp build_template_with_two_stages_and_transition(user) do
    {:ok, template} =
      Workflows.create_template(user, %{"name" => "Simple", "description" => "x"})

    {:ok, todo} = Workflows.add_stage(template, %{"name" => "Todo"})
    {:ok, done} = Workflows.add_stage(template, %{"name" => "Done"})
    {:ok, _} = Workflows.add_transition(template, todo.id, done.id, "ship it")

    Workflows.get_template!(template.id)
  end

  defp redeem(invite, user) do
    invite = reload_invite(invite)
    Kanban.redeem_board_invite(invite, user)
  end

  defp reload_invite(%{id: id}), do: Waxx.Repo.get!(Waxx.Kanban.BoardInvite, id)
end
