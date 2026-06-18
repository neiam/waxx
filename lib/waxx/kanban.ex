defmodule Waxx.Kanban do
  @moduledoc """
  Boards, board membership, board-scoped invites, and cards moving through
  a branching workflow.

  A board is created by cloning a `Waxx.Workflows.Template` into per-board
  `BoardStage` + `BoardTransition` rows. After cloning, edits to either side
  are independent.

  Card moves are enforced against the board's transition graph — a card can
  only move from stage X to stage Y if a `BoardTransition` from X→Y exists.
  """

  import Ecto.Query, warn: false
  alias Waxx.Repo
  alias Waxx.Accounts.User
  alias Waxx.Workflows
  alias Waxx.Workflows.{Template, Stage, Transition, TemplateLabel, TemplateField}

  alias Waxx.Kanban.{
    Board,
    BoardStage,
    BoardTransition,
    BoardLabel,
    BoardField,
    BoardActivity,
    Subboard,
    Membership,
    BoardInvite,
    Card,
    CardAssignee,
    CardLabel,
    CardFieldValue,
    CardNote,
    CardTemplate
  }

  @pubsub Waxx.PubSub

  ## PubSub --------------------------------------------------------------

  @doc """
  Subscribe the calling process to a board's update stream. Receives
  `{:cards_changed, board_id}` messages whenever a card mutation lands.
  """
  def subscribe(board_id) when is_binary(board_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(board_id))
  end

  defp topic(board_id), do: "board:#{board_id}"

  defp broadcast_cards_changed(board_id) do
    Phoenix.PubSub.broadcast(@pubsub, topic(board_id), {:cards_changed, board_id})
  end

  defp broadcast_workflow_changed(board_id) do
    Phoenix.PubSub.broadcast(@pubsub, topic(board_id), {:workflow_changed, board_id})
  end

  ## Activity log -------------------------------------------------------

  @doc """
  Records a board activity entry. `actor` may be a `%User{}` or `nil` for
  system-attributed actions. `meta` is a free-form map stored as jsonb;
  prefer denormalised strings (names, emails) so the log keeps reading
  cleanly after the referenced rows are renamed or deleted.
  """
  def log(board_id, actor, action, opts \\ []) do
    %BoardActivity{}
    |> BoardActivity.changeset(%{
      board_id: board_id,
      actor_id: actor_id(actor),
      card_id: Keyword.get(opts, :card_id),
      action: action,
      meta: Keyword.get(opts, :meta, %{})
    })
    |> Repo.insert()
  end

  defp actor_id(nil), do: nil
  defp actor_id(%User{id: id}), do: id

  @doc "Lists activities for a board, newest first; preloads actor + card."
  def list_activities(%Board{id: board_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)

    from(a in BoardActivity,
      where: a.board_id == ^board_id,
      order_by: [desc: a.inserted_at, desc: a.id],
      limit: ^limit,
      preload: [:actor, :card]
    )
    |> Repo.all()
  end

  # Wraps an `{:ok, _}` / `{:error, _}` tuple, broadcasting only on success.
  defp broadcast_on_ok({:ok, _} = result, board_id) do
    broadcast_cards_changed(board_id)
    result
  end

  defp broadcast_on_ok(other, _board_id), do: other

  ## Template → board propagation ---------------------------------------
  ##
  ## Boards are created by cloning a template. We then propagate further
  ## template edits to existing boards on a best-effort, name-matched
  ## basis: a board's stage is identified by name. Renaming a stage on a
  ## board makes it "drift" from the template, and subsequent template
  ## changes touching that name will skip the drifted board.
  ##
  ## Stage removal only propagates when the matching board stage has no
  ## cards — otherwise the board keeps the extra column rather than lose
  ## data.

  @doc "All boards (raw rows) currently pointing at the given template."
  def boards_using_template(template_id) do
    Repo.all(from(b in Board, where: b.template_id == ^template_id))
  end

  def propagate_template_stage_added(template_id, name, position, color) do
    for board <- boards_using_template(template_id) do
      if is_nil(Repo.get_by(BoardStage, board_id: board.id, name: name)) do
        case %BoardStage{}
             |> BoardStage.changeset(%{
               board_id: board.id,
               name: name,
               position: position,
               color: color
             })
             |> Repo.insert() do
          {:ok, _} -> broadcast_workflow_changed(board.id)
          _ -> :ok
        end
      end
    end

    :ok
  end

  @doc """
  Renames the matching board stage on every board using this template.
  Skips boards where:
    * no stage by `old_name` exists (the board has drifted), or
    * a *different* stage already has `new_name` (would collide).
  """
  def propagate_template_stage_renamed(template_id, old_name, new_name) do
    for board <- boards_using_template(template_id) do
      with %BoardStage{} = bs <-
             Repo.get_by(BoardStage, board_id: board.id, name: old_name),
           collision <- Repo.get_by(BoardStage, board_id: board.id, name: new_name),
           true <- is_nil(collision) or collision.id == bs.id do
        case bs |> BoardStage.changeset(%{name: new_name}) |> Repo.update() do
          {:ok, _} -> broadcast_workflow_changed(board.id)
          _ -> :ok
        end
      end
    end

    :ok
  end

  def propagate_template_stage_removed(template_id, name) do
    for board <- boards_using_template(template_id) do
      case Repo.get_by(BoardStage, board_id: board.id, name: name) do
        nil ->
          :ok

        %BoardStage{} = bs ->
          has_cards? = Repo.exists?(from(c in Card, where: c.board_stage_id == ^bs.id))

          unless has_cards? do
            {:ok, _} = Repo.delete(bs)
            broadcast_workflow_changed(board.id)
          end
      end
    end

    :ok
  end

  def propagate_template_transition_added(template_id, from_name, to_name, label) do
    for board <- boards_using_template(template_id) do
      with %BoardStage{id: from_id} <-
             Repo.get_by(BoardStage, board_id: board.id, name: from_name),
           %BoardStage{id: to_id} <-
             Repo.get_by(BoardStage, board_id: board.id, name: to_name),
           false <-
             Repo.exists?(
               from(t in BoardTransition,
                 where: t.from_stage_id == ^from_id and t.to_stage_id == ^to_id
               )
             ) do
        case %BoardTransition{}
             |> BoardTransition.changeset(%{
               board_id: board.id,
               from_stage_id: from_id,
               to_stage_id: to_id,
               label: label
             })
             |> Repo.insert() do
          {:ok, _} -> broadcast_workflow_changed(board.id)
          _ -> :ok
        end
      end
    end

    :ok
  end

  def propagate_template_transition_removed(template_id, from_name, to_name) do
    for board <- boards_using_template(template_id) do
      with %BoardStage{id: from_id} <-
             Repo.get_by(BoardStage, board_id: board.id, name: from_name),
           %BoardStage{id: to_id} <-
             Repo.get_by(BoardStage, board_id: board.id, name: to_name),
           %BoardTransition{} = bt <-
             Repo.get_by(BoardTransition,
               board_id: board.id,
               from_stage_id: from_id,
               to_stage_id: to_id
             ) do
        {:ok, _} = Repo.delete(bt)
        broadcast_workflow_changed(board.id)
      end
    end

    :ok
  end

  def propagate_template_label_added(template_id, name, color) do
    for board <- boards_using_template(template_id) do
      if is_nil(Repo.get_by(BoardLabel, board_id: board.id, name: name)) do
        case %BoardLabel{}
             |> BoardLabel.changeset(%{board_id: board.id, name: name, color: color})
             |> Repo.insert() do
          {:ok, _} -> broadcast_workflow_changed(board.id)
          _ -> :ok
        end
      end
    end

    :ok
  end

  def propagate_template_label_removed(template_id, name) do
    for board <- boards_using_template(template_id) do
      case Repo.get_by(BoardLabel, board_id: board.id, name: name) do
        nil ->
          :ok

        %BoardLabel{} = bl ->
          in_use? =
            Repo.exists?(from(cl in CardLabel, where: cl.board_label_id == ^bl.id))

          unless in_use? do
            {:ok, _} = Repo.delete(bl)
            broadcast_workflow_changed(board.id)
          end
      end
    end

    :ok
  end

  def propagate_template_field_added(template_id, attrs) do
    for board <- boards_using_template(template_id) do
      if is_nil(Repo.get_by(BoardField, board_id: board.id, name: attrs.name)) do
        case %BoardField{}
             |> BoardField.changeset(%{
               board_id: board.id,
               name: attrs.name,
               kind: attrs.kind,
               options: attrs.options,
               show_on_card: attrs.show_on_card,
               position: attrs.position
             })
             |> Repo.insert() do
          {:ok, _} -> broadcast_workflow_changed(board.id)
          _ -> :ok
        end
      end
    end

    :ok
  end

  def propagate_template_field_updated(template_id, name, attrs) do
    for board <- boards_using_template(template_id) do
      case Repo.get_by(BoardField, board_id: board.id, name: name) do
        nil ->
          :ok

        %BoardField{} = bf ->
          case bf
               |> BoardField.changeset(%{
                 kind: attrs.kind,
                 options: attrs.options,
                 show_on_card: attrs.show_on_card,
                 position: attrs.position
               })
               |> Repo.update() do
            {:ok, _} -> broadcast_workflow_changed(board.id)
            _ -> :ok
          end
      end
    end

    :ok
  end

  def propagate_template_field_removed(template_id, name) do
    for board <- boards_using_template(template_id) do
      case Repo.get_by(BoardField, board_id: board.id, name: name) do
        nil ->
          :ok

        %BoardField{} = bf ->
          in_use? =
            Repo.exists?(from(v in CardFieldValue, where: v.board_field_id == ^bf.id))

          unless in_use? do
            {:ok, _} = Repo.delete(bf)
            broadcast_workflow_changed(board.id)
          end
      end
    end

    :ok
  end

  ## Boards --------------------------------------------------------------

  @doc "Lists boards visible to the given user (any membership role)."
  def list_boards_for(%User{id: user_id}) do
    from(b in Board,
      join: m in Membership,
      on: m.board_id == b.id,
      where: m.user_id == ^user_id,
      order_by: [desc: b.inserted_at],
      distinct: true
    )
    |> Repo.all()
  end

  @doc "Fetches a board if the user has any membership on it. Returns nil otherwise."
  def get_board_for_user(board_id, %User{id: user_id}) do
    from(b in Board,
      join: m in Membership,
      on: m.board_id == b.id and m.user_id == ^user_id,
      where: b.id == ^board_id,
      select: b
    )
    |> Repo.one()
  end

  @doc "Returns the user's role on the board, or nil if they're not a member."
  def role_for(board_id, %User{id: user_id}) do
    from(m in Membership,
      where: m.board_id == ^board_id and m.user_id == ^user_id,
      select: m.role
    )
    |> Repo.one()
  end

  def can_edit?(role) when role in ["owner", "editor"], do: true
  def can_edit?(_), do: false

  def can_manage?(role), do: role == "owner"

  def change_board(%Board{} = board, attrs \\ %{}), do: Board.changeset(board, attrs)

  @doc """
  Creates a board by cloning the given template. The creating user becomes
  the owner and gets an `owner` membership row.
  """
  def create_board_from_template(%User{id: user_id} = user, %Template{} = template, attrs) do
    template = Workflows.get_template!(template.id)

    Repo.transact(fn ->
      with {:ok, board} <-
             %Board{}
             |> Board.changeset(
               attrs
               |> stringify_keys()
               |> Map.put("owner_id", user_id)
               |> Map.put("template_id", template.id)
             )
             |> Repo.insert(),
           {:ok, _membership} <-
             %Membership{}
             |> Membership.changeset(%{
               board_id: board.id,
               user_id: user_id,
               role: "owner"
             })
             |> Repo.insert(),
           {:ok, _} <- clone_template_graph(template, board) do
        {:ok, get_board_with_workflow!(board.id, user)}
      end
    end)
  end

  defp clone_template_graph(
         %Template{
           stages: stages,
           transitions: transitions,
           labels: labels,
           fields: fields
         },
         %Board{id: board_id}
       ) do
    # Insert stages, building a map from template stage id → new board_stage id.
    stage_map =
      Enum.reduce(stages, %{}, fn %Stage{} = ts, acc ->
        {:ok, bs} =
          %BoardStage{}
          |> BoardStage.changeset(%{
            board_id: board_id,
            name: ts.name,
            position: ts.position,
            color: ts.color
          })
          |> Repo.insert()

        Map.put(acc, ts.id, bs.id)
      end)

    # Insert transitions using the remapped stage ids.
    Enum.each(transitions, fn %Transition{} = tt ->
      from_id = Map.fetch!(stage_map, tt.from_stage_id)
      to_id = Map.fetch!(stage_map, tt.to_stage_id)

      %BoardTransition{}
      |> BoardTransition.changeset(%{
        board_id: board_id,
        from_stage_id: from_id,
        to_stage_id: to_id,
        label: tt.label
      })
      |> Repo.insert!()
    end)

    # Clone labels by name — boards keep their own copy so they can drift.
    Enum.each(labels, fn %TemplateLabel{} = tl ->
      %BoardLabel{}
      |> BoardLabel.changeset(%{
        board_id: board_id,
        name: tl.name,
        color: tl.color
      })
      |> Repo.insert!()
    end)

    # Clone custom fields (name, kind, options, show_on_card, position).
    Enum.each(fields, fn %TemplateField{} = tf ->
      %BoardField{}
      |> BoardField.changeset(%{
        board_id: board_id,
        name: tf.name,
        kind: tf.kind,
        options: tf.options,
        show_on_card: tf.show_on_card,
        position: tf.position
      })
      |> Repo.insert!()
    end)

    {:ok, stage_map}
  end

  @doc """
  Updates a board's basic fields and broadcasts `:workflow_changed` so
  any open kanban LiveView re-fetches (the archive threshold change can
  hide cards from the column, and a rename changes the header text).
  Caller must verify role first.
  """
  def update_board(%Board{} = board, attrs) do
    case board |> Board.changeset(attrs) |> Repo.update() do
      {:ok, _} = result ->
        Phoenix.PubSub.broadcast(@pubsub, topic(board.id), {:workflow_changed, board.id})
        result

      other ->
        other
    end
  end

  def delete_board(%Board{} = board), do: Repo.delete(board)

  ## Subboards ----------------------------------------------------------

  @doc "Lists a board's subboards in display order (position, then created)."
  def list_subboards(%Board{id: board_id}) do
    Repo.all(
      from(sb in Subboard,
        where: sb.board_id == ^board_id,
        order_by: [asc: sb.position, asc: sb.inserted_at]
      )
    )
  end

  @doc """
  Creates a subboard at the next position. Auto-positions to the end of
  the existing list. Broadcasts `:workflow_changed` so open kanban views
  refresh the grid.
  """
  def create_subboard(%Board{} = board, attrs) do
    next_pos =
      (Repo.one(from(sb in Subboard, where: sb.board_id == ^board.id, select: max(sb.position))) ||
         -1) + 1

    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("board_id", board.id)
      |> Map.put_new("position", next_pos)

    case %Subboard{} |> Subboard.changeset(attrs) |> Repo.insert() do
      {:ok, _} = result ->
        broadcast_workflow_changed(board.id)
        result

      other ->
        other
    end
  end

  @doc """
  Moves a subboard to a new 0-based row position. Shifts the other
  subboards on the same board to fill / make room. Broadcasts
  `:workflow_changed` so open kanban views re-render the grid.

  No-op if the target index is the current position or out of range.
  """
  def reorder_subboard(%Subboard{board_id: board_id} = sb, new_index)
      when is_integer(new_index) and new_index >= 0 do
    rows =
      Repo.all(
        from(s in Subboard,
          where: s.board_id == ^board_id,
          order_by: [asc: s.position, asc: s.inserted_at]
        )
      )

    clamped = min(new_index, length(rows) - 1)
    current = Enum.find_index(rows, &(&1.id == sb.id))

    cond do
      current == nil ->
        {:error, :not_found}

      current == clamped ->
        {:ok, sb}

      true ->
        rest = List.delete_at(rows, current)
        reordered = List.insert_at(rest, clamped, sb)

        Repo.transact(fn ->
          Enum.with_index(reordered)
          |> Enum.each(fn {row, idx} ->
            Repo.update_all(
              from(s in Subboard, where: s.id == ^row.id),
              set: [position: idx]
            )
          end)

          {:ok, :reordered}
        end)

        broadcast_workflow_changed(board_id)
        {:ok, Repo.get!(Subboard, sb.id)}
    end
  end

  @doc """
  Deletes a subboard. Cards previously assigned to it fall back to the
  default row (FK is `on_delete: :nilify_all`). Broadcasts.
  """
  def delete_subboard(%Subboard{board_id: board_id} = sb) do
    case Repo.delete(sb) do
      {:ok, _} = result ->
        broadcast_workflow_changed(board_id)
        result

      other ->
        other
    end
  end

  @doc """
  Reassigns a card to a subboard (or to the default row when
  `subboard_id` is nil). Validates that the subboard, if any, belongs to
  the card's board so a crafted payload can't reference a row from
  another board.
  """
  def set_card_subboard(card, subboard_or_nil, opts \\ [])

  def set_card_subboard(%Card{} = card, nil, opts) do
    do_set_card_subboard(card, nil, opts)
  end

  def set_card_subboard(%Card{board_id: board_id} = card, %Subboard{} = sb, opts) do
    if sb.board_id != board_id do
      {:error, :invalid_subboard}
    else
      do_set_card_subboard(card, sb.id, opts)
    end
  end

  defp do_set_card_subboard(card, subboard_id, opts) do
    result =
      card
      |> Card.changeset(%{subboard_id: subboard_id})
      |> Repo.update()
      |> broadcast_on_ok(card.board_id)

    case result do
      {:ok, updated} ->
        # Denormalise the subboard name into the activity meta so the
        # history view renders cleanly even after the subboard is
        # renamed or deleted. The nil-row reads as "Default".
        log(card.board_id, opts[:actor], "card_subboard_changed",
          card_id: updated.id,
          meta: %{title: updated.title, subboard_name: subboard_name(subboard_id)}
        )

      _ ->
        :ok
    end

    result
  end

  defp subboard_name(nil), do: "Default"

  defp subboard_name(subboard_id) do
    Repo.one(from(sb in Subboard, where: sb.id == ^subboard_id, select: sb.name)) || "Default"
  end

  ## Board labels --------------------------------------------------------

  @doc "Lists a board's labels alphabetically, with their subboard scope preloaded."
  def list_board_labels(%Board{id: board_id}) do
    Repo.all(
      from(l in BoardLabel,
        where: l.board_id == ^board_id,
        order_by: [asc: l.name],
        preload: [:subboards]
      )
    )
  end

  @doc """
  Adds a label directly to a board, independent of the board's template
  (boards own their label list and may drift from the template they were
  cloned from). Broadcasts `:workflow_changed` so open kanban views
  refresh their chips.

  `attrs` may carry `subboard_ids` to restrict the label to one or more of
  the board's subboards (omit or pass an empty list for a board-wide label).

  Re-adding a label whose name already exists on the board is treated as an
  edit: its color and subboard scope are updated in place rather than
  failing the unique constraint. Returns `{:ok, :created | :updated, label}`
  on success, or `{:error, changeset}`.
  """
  def create_board_label(%Board{} = board, attrs) do
    attrs = stringify_keys(attrs)
    name = attrs["name"]

    case name && Repo.get_by(BoardLabel, board_id: board.id, name: name) do
      %BoardLabel{} = existing ->
        existing
        |> Repo.preload(:subboards)
        |> build_board_label_changeset(board, attrs)
        |> Repo.update()
        |> tag_board_label_result(board.id, :updated)

      _ ->
        %BoardLabel{}
        |> build_board_label_changeset(board, attrs)
        |> Repo.insert()
        |> tag_board_label_result(board.id, :created)
    end
  end

  @doc """
  Renames/recolors a board label and, when `subboard_ids` is present in
  `attrs`, replaces its subboard scope. Broadcasts on success.
  """
  def update_board_label(%BoardLabel{} = label, attrs) do
    attrs = attrs |> stringify_keys() |> Map.delete("board_id")
    board = %Board{id: label.board_id}

    case label
         |> Repo.preload(:subboards)
         |> build_board_label_changeset(board, attrs)
         |> Repo.update() do
      {:ok, _} = result ->
        broadcast_workflow_changed(label.board_id)
        result

      other ->
        other
    end
  end

  # Builds a BoardLabel changeset, pinning board_id and (only when
  # `subboard_ids` was supplied) replacing the subboard scope via put_assoc.
  defp build_board_label_changeset(label, %Board{} = board, attrs) do
    changeset =
      label
      |> BoardLabel.changeset(Map.put(attrs, "board_id", board.id))

    case Map.fetch(attrs, "subboard_ids") do
      {:ok, ids} -> Ecto.Changeset.put_assoc(changeset, :subboards, scoped_subboards(board, ids))
      :error -> changeset
    end
  end

  # Resolves submitted subboard ids to the board's own Subboard rows,
  # dropping blanks and anything that doesn't belong to this board.
  defp scoped_subboards(%Board{id: board_id}, ids) do
    ids = ids |> List.wrap() |> Enum.reject(&(&1 in [nil, ""]))

    if ids == [] do
      []
    else
      Repo.all(from(s in Subboard, where: s.board_id == ^board_id and s.id in ^ids))
    end
  end

  defp tag_board_label_result({:ok, label}, board_id, tag) do
    broadcast_workflow_changed(board_id)
    {:ok, tag, label}
  end

  defp tag_board_label_result(other, _board_id, _tag), do: other

  @doc """
  Deletes a board label. Refuses with `{:error, :in_use}` while any card
  still references it (same rule the template-removal propagation
  enforces). Broadcasts on success.
  """
  def delete_board_label(%BoardLabel{} = label) do
    in_use? = Repo.exists?(from(cl in CardLabel, where: cl.board_label_id == ^label.id))

    if in_use? do
      {:error, :in_use}
    else
      case Repo.delete(label) do
        {:ok, _} = result ->
          broadcast_workflow_changed(label.board_id)
          result

        other ->
          other
      end
    end
  end

  @doc "Board with workflow graph, labels, custom fields, and members preloaded."
  def get_board_with_workflow!(board_id, %User{} = user) do
    board = get_board_for_user(board_id, user) || raise Ecto.NoResultsError, queryable: Board

    Repo.preload(board,
      stages: from(s in BoardStage, order_by: [asc: s.position]),
      transitions: [:from_stage, :to_stage],
      labels: {from(l in BoardLabel, order_by: [asc: l.name]), [:subboards]},
      fields: from(f in BoardField, order_by: [asc: f.position, asc: f.id]),
      subboards: from(sb in Subboard, order_by: [asc: sb.position, asc: sb.inserted_at]),
      memberships: [:user]
    )
  end

  ## Members + invites ---------------------------------------------------

  def list_members(board_id) do
    from(m in Membership,
      where: m.board_id == ^board_id,
      preload: [:user],
      order_by: [asc: m.inserted_at]
    )
    |> Repo.all()
  end

  def add_member(%Board{id: board_id}, %User{id: user_id}, role) do
    %Membership{}
    |> Membership.changeset(%{board_id: board_id, user_id: user_id, role: role})
    |> Repo.insert()
  end

  def update_member_role(%Membership{} = membership, role) do
    membership
    |> Membership.changeset(%{role: role})
    |> Repo.update()
  end

  def remove_member(%Membership{} = membership), do: Repo.delete(membership)

  def list_board_invites(%Board{id: board_id}) do
    from(i in BoardInvite,
      where: i.board_id == ^board_id,
      order_by: [desc: i.inserted_at],
      preload: [:consumed_by]
    )
    |> Repo.all()
  end

  def create_board_invite(%Board{id: board_id}, %User{id: user_id}, attrs \\ %{}) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("board_id", board_id)
      |> Map.put("created_by_id", user_id)
      |> Map.put_new("role", "editor")

    %BoardInvite{}
    |> BoardInvite.create_changeset(attrs)
    |> Repo.insert()
  end

  def get_active_board_invite(token) when is_binary(token) do
    case Repo.get_by(BoardInvite, token: token) do
      nil -> nil
      invite -> if BoardInvite.active?(invite), do: Repo.preload(invite, :board), else: nil
    end
  end

  @doc """
  Redeems an invite for the given user: grants membership (no-op if they
  are already a member with at least the invite's role) and marks the
  invite consumed. Returns `{:ok, board}` or `{:error, reason}`.
  """
  def redeem_board_invite(%BoardInvite{} = invite, %User{id: user_id} = user) do
    cond do
      not BoardInvite.active?(invite) ->
        {:error, :inactive}

      true ->
        Repo.transact(fn ->
          existing =
            Repo.get_by(Membership, board_id: invite.board_id, user_id: user_id)

          with {:ok, _membership} <- ensure_membership(existing, invite, user_id),
               {:ok, _invite} <-
                 invite |> BoardInvite.consume_changeset(user) |> Repo.update() do
            {:ok, Repo.get!(Board, invite.board_id)}
          end
        end)
    end
  end

  def revoke_board_invite(%BoardInvite{} = invite) do
    invite
    |> Ecto.Changeset.change(
      consumed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      consumed_by_id: nil
    )
    |> Repo.update()
  end

  defp ensure_membership(nil, %BoardInvite{} = invite, user_id) do
    %Membership{}
    |> Membership.changeset(%{
      board_id: invite.board_id,
      user_id: user_id,
      role: invite.role
    })
    |> Repo.insert()
  end

  defp ensure_membership(%Membership{} = membership, _invite, _user_id) do
    {:ok, membership}
  end

  ## Cards ---------------------------------------------------------------

  @doc """
  Lists cards for a board, applying the board's `archive_terminal_after_days`
  filter: a card in a terminal stage (no outgoing transitions) that has sat
  there longer than the threshold is hidden from the kanban view. The
  board's `stages` and `transitions` must be preloaded — `get_board_with_workflow!/2`
  does this.
  """
  def list_cards(%Board{} = board) do
    cards =
      from(c in Card,
        where: c.board_id == ^board.id,
        order_by: [asc: c.board_stage_id, asc: c.position, asc: c.inserted_at],
        preload: [:assignees, :labels, :field_values, :notes, :created_by]
      )
      |> Repo.all()

    archive_terminal_cards(cards, board)
  end

  defp archive_terminal_cards(cards, %Board{archive_terminal_after_days: nil}), do: cards

  defp archive_terminal_cards(cards, %Board{
         archive_terminal_after_days: days,
         stages: stages,
         transitions: transitions
       })
       when is_list(stages) and is_list(transitions) do
    sources = MapSet.new(transitions, & &1.from_stage_id)
    terminal = MapSet.new(for s <- stages, not MapSet.member?(sources, s.id), do: s.id)
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)

    Enum.reject(cards, fn c ->
      MapSet.member?(terminal, c.board_stage_id) and
        c.stage_entered_at != nil and
        DateTime.compare(c.stage_entered_at, cutoff) == :lt
    end)
  end

  # Board fetched without preloads (e.g. through `boards_using_template/1`)
  # — fall back to "no filtering" rather than crash.
  defp archive_terminal_cards(cards, _board), do: cards

  def get_card(card_id) do
    Card
    |> Repo.get(card_id)
    |> case do
      nil ->
        nil

      card ->
        Repo.preload(card, [
          :assignees,
          :labels,
          :field_values,
          :notes,
          :created_by,
          :board_stage
        ])
    end
  end

  def change_card(%Card{} = card, attrs \\ %{}), do: Card.changeset(card, attrs)

  def create_card(%Board{} = board, %User{id: user_id} = user, attrs) do
    # Default to the first stage if none supplied. Reject stages that don't
    # belong to this board.
    attrs = stringify_keys(attrs)

    stage_id =
      attrs["board_stage_id"] ||
        Repo.one(
          from(s in BoardStage,
            where: s.board_id == ^board.id,
            order_by: [asc: s.position],
            limit: 1,
            select: s.id
          )
        )

    cond do
      is_nil(stage_id) ->
        {:error, :no_stages}

      not stage_belongs_to_board?(stage_id, board.id) ->
        {:error, :invalid_stage}

      true ->
        next_pos =
          Repo.one(
            from(c in Card,
              where: c.board_id == ^board.id and c.board_stage_id == ^stage_id,
              select: coalesce(max(c.position), -1)
            )
          ) + 1

        result =
          %Card{}
          |> Card.changeset(
            attrs
            |> Map.put("board_id", board.id)
            |> Map.put("board_stage_id", stage_id)
            |> Map.put("created_by_id", user_id)
            |> Map.put_new("position", next_pos)
            |> Map.put_new("stage_entered_at", utc_now())
          )
          |> Repo.insert()
          |> broadcast_on_ok(board.id)

        case result do
          {:ok, card} ->
            log(board.id, user, "card_created",
              card_id: card.id,
              meta: %{title: card.title}
            )

          _ ->
            :ok
        end

        result
    end
  end

  defp utc_now, do: DateTime.utc_now(:second)

  def update_card(%Card{} = card, attrs, opts \\ []) do
    result =
      card
      |> Card.changeset(attrs)
      |> Repo.update()
      |> broadcast_on_ok(card.board_id)

    case result do
      {:ok, updated} ->
        changed = Enum.map(attrs, fn {k, _} -> to_string(k) end)

        log(card.board_id, opts[:actor], "card_updated",
          card_id: updated.id,
          meta: %{changes: changed, title: updated.title}
        )

      _ ->
        :ok
    end

    result
  end

  def delete_card(%Card{} = card, opts \\ []) do
    title = card.title

    result =
      card
      |> Repo.delete()
      |> broadcast_on_ok(card.board_id)

    case result do
      {:ok, _} ->
        # No card_id — the row is gone and the FK would reject the insert.
        # `meta.title` keeps the entry readable in the history view.
        log(card.board_id, opts[:actor], "card_deleted", meta: %{title: title})

      _ ->
        :ok
    end

    result
  end

  @doc """
  Moves a card to a target stage, optionally inserting at a specific
  0-based index within the target column instead of appending.

  Enforces that a `BoardTransition` exists from the card's current stage
  to the target stage. A same-stage call is treated as a pure reorder
  (no transition check needed).

  Returns `{:ok, card}`, `{:error, :invalid_transition}`, or
  `{:error, :invalid_stage}`.
  """
  def move_card(%Card{} = card, target_stage_id, target_index \\ nil, opts \\ []) do
    cond do
      not stage_belongs_to_board?(target_stage_id, card.board_id) ->
        {:error, :invalid_stage}

      target_stage_id == card.board_stage_id ->
        if is_integer(target_index),
          do: reorder_card(card, target_index, opts),
          else: {:ok, card}

      not transition_exists?(card.board_id, card.board_stage_id, target_stage_id) ->
        {:error, :invalid_transition}

      true ->
        result =
          if is_integer(target_index),
            do: cross_stage_move_at(card, target_stage_id, target_index),
            else: cross_stage_move_append(card, target_stage_id)

        case result do
          {:ok, moved} ->
            log(card.board_id, opts[:actor], "card_moved",
              card_id: moved.id,
              meta: %{
                from_stage: stage_name(card.board_id, card.board_stage_id),
                to_stage: stage_name(card.board_id, target_stage_id),
                title: moved.title
              }
            )

          _ ->
            :ok
        end

        result
    end
  end

  defp stage_name(board_id, stage_id) do
    Repo.one(
      from(s in BoardStage,
        where: s.board_id == ^board_id and s.id == ^stage_id,
        select: s.name
      )
    )
  end

  defp cross_stage_move_append(card, target_stage_id) do
    next_pos = next_position_in(card.board_id, target_stage_id)

    card
    |> Card.changeset(%{
      board_stage_id: target_stage_id,
      position: next_pos,
      stage_entered_at: utc_now()
    })
    |> Repo.update()
    |> broadcast_on_ok(card.board_id)
  end

  defp cross_stage_move_at(card, target_stage_id, target_index) do
    now = utc_now()

    Repo.transact(fn ->
      siblings = stage_cards(card.board_id, target_stage_id)
      clamped = clamp_index(target_index, length(siblings))
      moved = %{card | board_stage_id: target_stage_id, stage_entered_at: now}
      new_list = List.insert_at(siblings, clamped, moved)

      :ok =
        renumber!(new_list,
          also_set_stage: target_stage_id,
          for_id: card.id,
          stage_entered_at: now
        )

      {:ok, %{moved | position: clamped}}
    end)
    |> broadcast_on_ok(card.board_id)
  end

  @doc """
  Repositions a card within its own stage. `new_index` is 0-based and
  clamped to the column length.
  """
  def reorder_card(%Card{} = card, new_index, _opts \\ []) when is_integer(new_index) do
    # Same-column shuffles aren't logged — too noisy for the history view.
    Repo.transact(fn ->
      siblings = stage_cards(card.board_id, card.board_stage_id)
      others = Enum.reject(siblings, &(&1.id == card.id))
      clamped = clamp_index(new_index, length(others))
      new_list = List.insert_at(others, clamped, card)

      :ok = renumber!(new_list)
      {:ok, %{card | position: clamped}}
    end)
    |> broadcast_on_ok(card.board_id)
  end

  ## Card notes + todos -------------------------------------------------

  @doc """
  Adds a freeform note or todo to a card. Auto-stamps the card's current
  `board_stage_id` so the entry renders in that stage's colour in the
  card detail view — useful as a "what was happening in this stage"
  journal even after the card has moved on.
  """
  def add_card_note(%Card{} = card, user, attrs) do
    next_pos =
      (Repo.one(
         from(n in CardNote,
           where: n.card_id == ^card.id,
           select: max(n.position)
         )
       ) || -1) + 1

    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("card_id", card.id)
      |> Map.put_new("board_stage_id", card.board_stage_id)
      |> Map.put_new("position", next_pos)
      |> Map.put_new("created_by_id", actor_id(user))

    case %CardNote{} |> CardNote.changeset(attrs) |> Repo.insert() do
      {:ok, _} = result ->
        broadcast_cards_changed(card.board_id)
        result

      other ->
        other
    end
  end

  def toggle_card_note_done(%CardNote{} = note) do
    case note
         |> CardNote.changeset(%{done: not note.done})
         |> Repo.update() do
      {:ok, updated} = result ->
        if card = Repo.get(Card, updated.card_id), do: broadcast_cards_changed(card.board_id)
        result

      other ->
        other
    end
  end

  def update_card_note(%CardNote{} = note, attrs) do
    case note |> CardNote.changeset(attrs) |> Repo.update() do
      {:ok, updated} = result ->
        if card = Repo.get(Card, updated.card_id), do: broadcast_cards_changed(card.board_id)
        result

      other ->
        other
    end
  end

  def delete_card_note(%CardNote{card_id: card_id} = note) do
    case Repo.delete(note) do
      {:ok, _} = result ->
        if card = Repo.get(Card, card_id), do: broadcast_cards_changed(card.board_id)
        result

      other ->
        other
    end
  end

  ## Card templates -----------------------------------------------------

  def list_card_templates(%Board{id: board_id}) do
    Repo.all(from(t in CardTemplate, where: t.board_id == ^board_id, order_by: [asc: t.name]))
  end

  def get_card_template(id) do
    Repo.get(CardTemplate, id)
  end

  @doc """
  Snapshots a card into a per-board template. The snapshot stores label
  *names* and field *names* (instead of ids) so the template stays
  valid after rename. Notes/todos are captured too. Assignees and
  stage/subboard are deliberately NOT snapshotted — they're context.
  """
  def save_card_as_template(%Card{} = card, user, name) do
    card =
      Repo.preload(card, [
        :labels,
        field_values: [:board_field],
        notes: [:board_stage]
      ])

    snapshot = %{
      "title" => card.title,
      "description" => card.description,
      "label_names" => Enum.map(card.labels, & &1.name),
      "field_values" => for(v <- card.field_values, into: %{}, do: {v.board_field.name, v.value}),
      "notes" =>
        for n <- card.notes do
          %{
            "kind" => n.kind,
            "body" => n.body,
            "done" => n.done,
            "stage_name" => n.board_stage && n.board_stage.name
          }
        end
    }

    %CardTemplate{}
    |> CardTemplate.changeset(%{
      board_id: card.board_id,
      name: name,
      snapshot: snapshot,
      created_by_id: actor_id(user)
    })
    |> Repo.insert()
  end

  @doc """
  Creates a new card on `board` seeded from the given template. Resolves
  label and field references by name against the destination board's
  current labels/fields; unknown ones are silently skipped. The new
  card lands at the given stage/subboard like a normal `create_card`
  call (the snapshot doesn't carry stage location).
  """
  def create_card_from_template(
        %Board{} = board,
        user,
        %CardTemplate{snapshot: snap},
        extra_attrs \\ %{}
      ) do
    base_attrs =
      %{
        "title" => snap["title"] || "Untitled",
        "description" => snap["description"]
      }
      |> Map.merge(stringify_keys(extra_attrs))

    Repo.transact(fn ->
      with {:ok, card} <- create_card(board, user, base_attrs) do
        board = Repo.preload(board, [:labels, :fields])
        apply_label_names(card, board, snap["label_names"] || [])
        apply_field_values(card, board, snap["field_values"] || %{})
        apply_template_notes(card, board, snap["notes"] || [], user)
        {:ok, get_card(card.id)}
      end
    end)
  end

  def delete_card_template(%CardTemplate{} = tpl), do: Repo.delete(tpl)

  defp apply_label_names(card, board, names) do
    labels_by_name = Map.new(board.labels, &{&1.name, &1})

    for n <- names, label = labels_by_name[n], not is_nil(label) do
      %CardLabel{}
      |> CardLabel.changeset(%{card_id: card.id, board_label_id: label.id})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:card_id, :board_label_id])
    end
  end

  defp apply_field_values(card, board, values) do
    fields_by_name = Map.new(board.fields, &{&1.name, &1})

    for {name, value} <- values, field = fields_by_name[name], not is_nil(field) do
      set_card_field_value(card, field, value)
    end
  end

  defp apply_template_notes(card, board, notes, user) do
    stages_by_name = Map.new(board.stages || [], &{&1.name, &1})

    # If the board snapshot didn't preload stages, get them.
    stages_by_name =
      if map_size(stages_by_name) > 0 do
        stages_by_name
      else
        board
        |> Repo.preload(:stages)
        |> Map.get(:stages)
        |> Map.new(&{&1.name, &1})
      end

    for n <- notes do
      stage_id =
        case n["stage_name"] && stages_by_name[n["stage_name"]] do
          %BoardStage{id: id} -> id
          _ -> card.board_stage_id
        end

      add_card_note(card, user, %{
        "body" => n["body"],
        "kind" => n["kind"] || "note",
        "done" => n["done"] == true,
        "board_stage_id" => stage_id
      })
    end
  end

  ## helpers (positioning) -----------------------------------------------

  defp next_position_in(board_id, stage_id) do
    Repo.one(
      from(c in Card,
        where: c.board_id == ^board_id and c.board_stage_id == ^stage_id,
        select: coalesce(max(c.position), -1)
      )
    ) + 1
  end

  defp stage_cards(board_id, stage_id) do
    Repo.all(
      from(c in Card,
        where: c.board_id == ^board_id and c.board_stage_id == ^stage_id,
        order_by: [asc: c.position, asc: c.inserted_at]
      )
    )
  end

  defp clamp_index(idx, _len) when idx < 0, do: 0
  defp clamp_index(idx, len) when idx > len, do: len
  defp clamp_index(idx, _len), do: idx

  # Writes contiguous 0..n-1 positions for a list of cards. When
  # `also_set_stage:` is given, the card with `for_id:` also gets its
  # board_stage_id updated in the same write — and, if `stage_entered_at:`
  # is also given, its stage-entered timestamp.
  defp renumber!(list, opts \\ []) do
    stage_id = Keyword.get(opts, :also_set_stage)
    moved_id = Keyword.get(opts, :for_id)
    entered_at = Keyword.get(opts, :stage_entered_at)

    list
    |> Enum.with_index()
    |> Enum.each(fn {c, idx} ->
      updates =
        cond do
          stage_id && c.id == moved_id ->
            base = [position: idx, board_stage_id: stage_id]
            if entered_at, do: base ++ [stage_entered_at: entered_at], else: base

          c.position == idx ->
            []

          true ->
            [position: idx]
        end

      if updates != [] do
        Repo.update_all(from(x in Card, where: x.id == ^c.id), set: updates)
      end
    end)

    :ok
  end

  defp stage_belongs_to_board?(stage_id, board_id) do
    Repo.exists?(from(s in BoardStage, where: s.id == ^stage_id and s.board_id == ^board_id))
  end

  defp transition_exists?(board_id, from_id, to_id) do
    Repo.exists?(
      from(t in BoardTransition,
        where:
          t.board_id == ^board_id and
            t.from_stage_id == ^from_id and
            t.to_stage_id == ^to_id
      )
    )
  end

  @doc "Lists allowed target stages for a card, given its current stage."
  def allowed_targets(%Card{board_id: board_id, board_stage_id: stage_id}) do
    from(t in BoardTransition,
      where: t.board_id == ^board_id and t.from_stage_id == ^stage_id,
      join: s in BoardStage,
      on: s.id == t.to_stage_id,
      order_by: [asc: s.position],
      select: %{stage_id: s.id, name: s.name, color: s.color, label: t.label}
    )
    |> Repo.all()
  end

  ## Assignees -----------------------------------------------------------

  def assign_user(%Card{id: card_id, board_id: board_id}, %User{id: user_id} = u, opts \\ []) do
    result =
      %CardAssignee{}
      |> CardAssignee.changeset(%{card_id: card_id, user_id: user_id})
      |> Repo.insert(
        on_conflict: :nothing,
        conflict_target: [:card_id, :user_id]
      )
      |> broadcast_on_ok(board_id)

    case result do
      {:ok, _} ->
        log(board_id, opts[:actor], "card_assigned",
          card_id: card_id,
          meta: %{user_email: u.email}
        )

      _ ->
        :ok
    end

    result
  end

  def unassign_user(%Card{id: card_id, board_id: board_id}, %User{id: user_id} = u, opts \\ []) do
    result =
      Repo.delete_all(
        from(a in CardAssignee, where: a.card_id == ^card_id and a.user_id == ^user_id)
      )

    broadcast_cards_changed(board_id)

    log(board_id, opts[:actor], "card_unassigned",
      card_id: card_id,
      meta: %{user_email: u.email}
    )

    result
  end

  @doc """
  Sets the value of a board field on a card. Blank or nil values delete
  the row rather than store `""`. For `select` fields the value must be
  one of the field's options; the function returns `{:error, :invalid_option}`
  otherwise. For `date` and `datetime` fields the value must parse via
  the relevant `Date`/`DateTime` ISO parsers, returning `{:error, :invalid_value}`
  on failure.

  Always validates that the field belongs to the card's board.
  """
  def set_card_field_value(
        %Card{id: card_id, board_id: board_id} = card,
        %BoardField{} = field,
        raw_value,
        opts \\ []
      ) do
    cond do
      field.board_id != board_id ->
        {:error, :invalid_field}

      true ->
        case normalize_field_value(field, raw_value) do
          {:ok, nil} ->
            Repo.delete_all(
              from(v in CardFieldValue,
                where: v.card_id == ^card_id and v.board_field_id == ^field.id
              )
            )

            broadcast_cards_changed(board_id)

            log(board_id, opts[:actor], "card_field_cleared",
              card_id: card_id,
              meta: %{field_name: field.name}
            )

            {:ok, card}

          {:ok, value} ->
            existing =
              Repo.get_by(CardFieldValue, card_id: card_id, board_field_id: field.id)

            cs =
              if existing,
                do: CardFieldValue.changeset(existing, %{value: value}),
                else:
                  CardFieldValue.changeset(%CardFieldValue{}, %{
                    card_id: card_id,
                    board_field_id: field.id,
                    value: value
                  })

            case if(existing, do: Repo.update(cs), else: Repo.insert(cs)) do
              {:ok, _} = result ->
                broadcast_cards_changed(board_id)

                log(board_id, opts[:actor], "card_field_set",
                  card_id: card_id,
                  meta: %{field_name: field.name, value: value}
                )

                result

              other ->
                other
            end

          {:error, _} = err ->
            err
        end
    end
  end

  defp normalize_field_value(_field, v) when v in [nil, ""], do: {:ok, nil}

  defp normalize_field_value(%BoardField{kind: "text"}, v) when is_binary(v),
    do: {:ok, v}

  defp normalize_field_value(%BoardField{kind: "date"}, v) when is_binary(v) do
    case Date.from_iso8601(v) do
      {:ok, d} -> {:ok, Date.to_iso8601(d)}
      _ -> {:error, :invalid_value}
    end
  end

  defp normalize_field_value(%BoardField{kind: "datetime"}, v) when is_binary(v) do
    # Accept either a full ISO datetime or "YYYY-MM-DDTHH:MM" from HTML
    # `datetime-local` inputs (which omit seconds and TZ).
    cases = [
      fn -> DateTime.from_iso8601(v) end,
      fn ->
        with {:ok, naive} <- NaiveDateTime.from_iso8601(v <> ":00") do
          {:ok, DateTime.from_naive!(naive, "Etc/UTC"), 0}
        end
      end,
      fn ->
        with {:ok, naive} <- NaiveDateTime.from_iso8601(v) do
          {:ok, DateTime.from_naive!(naive, "Etc/UTC"), 0}
        end
      end
    ]

    Enum.find_value(cases, {:error, :invalid_value}, fn f ->
      case f.() do
        {:ok, dt, _} -> {:ok, DateTime.to_iso8601(dt)}
        _ -> nil
      end
    end)
  end

  defp normalize_field_value(%BoardField{kind: "select", options: opts}, v)
       when is_binary(v) do
    if v in (opts || []), do: {:ok, v}, else: {:error, :invalid_option}
  end

  defp normalize_field_value(_field, _v), do: {:error, :invalid_value}

  @doc """
  Adds or removes a label from a card depending on whether it's currently
  attached. Validates the label belongs to the card's board so a crafted
  payload can't reference a label from some other board.
  """
  def toggle_card_label(
        %Card{id: card_id, board_id: board_id},
        %BoardLabel{} = label,
        opts \\ []
      ) do
    cond do
      label.board_id != board_id ->
        {:error, :invalid_label}

      true ->
        existing =
          Repo.get_by(CardLabel, card_id: card_id, board_label_id: label.id)

        result =
          if existing do
            Repo.delete(existing)
          else
            %CardLabel{}
            |> CardLabel.changeset(%{card_id: card_id, board_label_id: label.id})
            |> Repo.insert()
          end

        broadcast_cards_changed(board_id)

        action = if existing, do: "card_label_removed", else: "card_label_added"

        log(board_id, opts[:actor], action,
          card_id: card_id,
          meta: %{label_name: label.name}
        )

        result
    end
  end

  ## Helpers -------------------------------------------------------------

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
