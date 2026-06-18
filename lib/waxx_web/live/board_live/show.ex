defmodule WaxxWeb.BoardLive.Show do
  use WaxxWeb, :live_view

  alias Waxx.{Accounts, Kanban}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user
    board_id = id

    case Kanban.get_board_for_user(board_id, user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Board not found.")
         |> push_navigate(to: ~p"/boards")}

      _board ->
        role = Kanban.role_for(board_id, user)
        board = Kanban.get_board_with_workflow!(board_id, user)
        cards = Kanban.list_cards(board)

        if connected?(socket), do: Kanban.subscribe(board_id)

        {:ok,
         socket
         |> assign(:page_title, board.name)
         |> assign(:board, board)
         |> assign(:role, role)
         |> assign(:cards, cards)
         |> assign(:transitions_json, transitions_json(board))
         |> assign(:show_new_card_for, nil)
         |> assign(:expanded_card, nil)
         |> assign(:editing_card, false)
         |> assign(:card_edit_form, nil)
         |> assign(:hide_label_text, Accounts.hide_label_text?(user, board_id))
         |> assign(:card_templates, Kanban.list_card_templates(board))
         |> assign(:new_card_form, to_form(%{"title" => "", "description" => ""}, as: "card"))
         |> assign(:note_stage_picker_open_for, nil)}
    end
  end

  @impl true
  def handle_info({:cards_changed, _board_id}, socket) do
    cards = Kanban.list_cards(socket.assigns.board)
    expanded = refresh_expanded(socket)
    {:noreply, socket |> assign(:cards, cards) |> assign(:expanded_card, expanded)}
  end

  # Stage/transition graph changed — typically from a template edit
  # propagating to this board. Re-fetch the full workflow snapshot, the
  # transitions JSON the drag-and-drop hook consumes, and the cards (a
  # stage might have been removed; its cards would have gone with it).
  def handle_info({:workflow_changed, _board_id}, socket) do
    user = socket.assigns.current_scope.user
    board = Kanban.get_board_with_workflow!(socket.assigns.board.id, user)
    cards = Kanban.list_cards(board)
    expanded = refresh_expanded(socket)

    {:noreply,
     socket
     |> assign(:board, board)
     |> assign(:transitions_json, transitions_json(board))
     |> assign(:cards, cards)
     |> assign(:expanded_card, expanded)}
  end

  # Pulls a fresh copy of the open card from the DB — but only when the
  # local user isn't actively editing it. Preserving the stale copy keeps
  # an in-flight title/description edit from being clobbered by a remote
  # broadcast.
  defp refresh_expanded(socket) do
    case socket.assigns.expanded_card do
      nil -> nil
      %{id: _} when socket.assigns.editing_card -> socket.assigns.expanded_card
      %{id: id} -> Kanban.get_card(id)
    end
  end

  # Encodes the board's transition graph as `{"from_stage_id": [to_id, ...]}`
  # so the drag-and-drop hook can compute valid drop targets client-side
  # without an extra round-trip on dragenter.
  defp transitions_json(board) do
    board.transitions
    |> Enum.group_by(& &1.from_stage_id, & &1.to_stage_id)
    |> Jason.encode!()
  end

  ## --- helpers exposed to the template -------------------------------------

  defp cards_in_stage(cards, stage_id), do: Enum.filter(cards, &(&1.board_stage_id == stage_id))

  # Cards in a given (stage, subboard) cell. `subboard_id` is `nil` for
  # the default row.
  defp cards_for(cards, stage_id, subboard_id) do
    Enum.filter(cards, &(&1.board_stage_id == stage_id and &1.subboard_id == subboard_id))
  end

  defp stage_color(nil), do: nil
  defp stage_color(""), do: nil
  defp stage_color(c), do: c

  defp assignable_users(board), do: Enum.map(board.memberships, & &1.user)

  ## --- events -------------------------------------------------------------

  @impl true
  def handle_event("show_new_card", %{"stage-id" => stage_id} = params, socket) do
    guard_edit(socket, fn ->
      subboard_id = blank_to_nil(params["subboard-id"])

      {:noreply,
       socket
       |> assign(:show_new_card_for, {stage_id, subboard_id})
       |> assign(:new_card_form, to_form(%{"title" => "", "description" => ""}, as: "card"))}
    end)
  end

  def handle_event("cancel_new_card", _, socket) do
    {:noreply, assign(socket, :show_new_card_for, nil)}
  end

  def handle_event("create_card", %{"card" => params}, socket) do
    guard_edit(socket, fn ->
      {stage_id, subboard_id} = socket.assigns.show_new_card_for
      user = socket.assigns.current_scope.user
      board = socket.assigns.board

      base_attrs =
        params
        |> Map.put("board_stage_id", stage_id)
        |> Map.put("subboard_id", subboard_id)
        # The template_id select is hand-rolled (not a form field) so
        # it lives in the card params; pull it out before passing to
        # the schema, which doesn't have that field.
        |> Map.delete("template_id")

      result =
        case blank_to_nil(params["template_id"]) do
          nil ->
            Kanban.create_card(board, user, base_attrs)

          tpl_id ->
            case Kanban.get_card_template(tpl_id) do
              nil ->
                Kanban.create_card(board, user, base_attrs)

              tpl ->
                Kanban.create_card_from_template(board, user, tpl, base_attrs)
            end
        end

      case result do
        {:ok, _card} ->
          {:noreply,
           socket
           |> assign(:show_new_card_for, nil)
           |> put_flash(:info, "Card created.")}

        {:error, cs} ->
          {:noreply, assign(socket, :new_card_form, to_form(cs))}
      end
    end)
  end

  def handle_event("expand_card", %{"id" => id}, socket) do
    case Kanban.get_card(id) do
      nil ->
        {:noreply, socket}

      card ->
        {:noreply,
         socket
         |> assign(:expanded_card, card)
         |> assign(:editing_card, false)
         |> assign(:card_edit_form, nil)}
    end
  end

  def handle_event("collapse_card", _, socket) do
    {:noreply,
     socket
     |> assign(:expanded_card, nil)
     |> assign(:editing_card, false)
     |> assign(:card_edit_form, nil)}
  end

  # Flips the per-(user, board) "hide label text" preference. We drive
  # off the LiveView's `:hide_label_text` assign (the live truth) rather
  # than the socket's cached `current_scope.user.preferences`, which is
  # frozen at mount and never re-loads — that's why the first version
  # of this handler appeared to only work once.
  def handle_event("toggle_label_text", _, socket) do
    new_value = not socket.assigns.hide_label_text
    user = socket.assigns.current_scope.user

    case Accounts.set_hide_label_text(user, socket.assigns.board.id, new_value) do
      {:ok, _} -> {:noreply, assign(socket, :hide_label_text, new_value)}
      _ -> {:noreply, put_flash(socket, :error, "Couldn't update preference.")}
    end
  end

  def handle_event("start_card_edit", _, socket) do
    guard_edit(socket, fn ->
      case socket.assigns.expanded_card do
        nil ->
          {:noreply, socket}

        card ->
          form =
            to_form(
              Kanban.change_card(card, %{
                "title" => card.title,
                "description" => card.description
              })
            )

          {:noreply,
           socket
           |> assign(:editing_card, true)
           |> assign(:card_edit_form, form)}
      end
    end)
  end

  def handle_event("cancel_card_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_card, false)
     |> assign(:card_edit_form, nil)}
  end

  def handle_event("validate_card_edit", %{"card" => params}, socket) do
    case socket.assigns.expanded_card do
      nil ->
        {:noreply, socket}

      card ->
        form =
          card
          |> Kanban.change_card(params)
          |> Map.put(:action, :validate)
          |> to_form()

        {:noreply, assign(socket, :card_edit_form, form)}
    end
  end

  def handle_event("save_card_edit", %{"card" => params}, socket) do
    guard_edit(socket, fn ->
      case socket.assigns.expanded_card do
        nil ->
          {:noreply, socket}

        card ->
          # Restrict to the editable fields — never let a payload smuggle
          # board_stage_id, position, or board_id past this handler.
          attrs = Map.take(params, ["title", "description"])

          case Kanban.update_card(card, attrs, actor: socket.assigns.current_scope.user) do
            {:ok, updated} ->
              # Broadcast will also refresh, but expanded_card is preserved
              # while :editing_card is true — so set it explicitly here too.
              {:noreply,
               socket
               |> assign(:editing_card, false)
               |> assign(:card_edit_form, nil)
               |> assign(:expanded_card, Kanban.get_card(updated.id))
               |> put_flash(:info, "Card updated.")}

            {:error, cs} ->
              {:noreply, assign(socket, :card_edit_form, to_form(cs))}
          end
      end
    end)
  end

  # `place_card` is the unified drag-and-drop landing point: target
  # stage + subboard come from the cell the user dropped into. Handles
  # both moves in one event so a stage + subboard change in a single
  # drag doesn't need two round-trips.
  def handle_event("place_card", %{"id" => id} = params, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(id)
      actor = socket.assigns.current_scope.user
      target_stage_id = params["stage-id"]
      target_subboard_id = blank_to_nil(params["subboard-id"])
      target_index = parse_index(params["index"])

      cond do
        is_nil(card) or card.board_id != socket.assigns.board.id ->
          {:noreply, put_flash(socket, :error, "Card not found.")}

        true ->
          # Always run the stage move first (it enforces transitions). If
          # the stage isn't changing, this falls through to reorder. Then
          # set the subboard if it changed; the second write is a no-op
          # when source/target match.
          case Kanban.move_card(card, target_stage_id, target_index, actor: actor) do
            {:ok, moved} ->
              if moved.subboard_id != target_subboard_id do
                target_sb =
                  Enum.find(socket.assigns.board.subboards, &(&1.id == target_subboard_id))

                Kanban.set_card_subboard(moved, target_sb, actor: actor)
              end

              {:noreply, socket}

            {:error, :invalid_transition} ->
              {:noreply, put_flash(socket, :error, "That move isn't allowed by the workflow.")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Couldn't move the card.")}
          end
      end
    end)
  end

  def handle_event("move_card", %{"id" => id, "stage-id" => stage_id} = params, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(id)
      target_index = parse_index(params["index"])

      cond do
        is_nil(card) or card.board_id != socket.assigns.board.id ->
          {:noreply, put_flash(socket, :error, "Card not found.")}

        true ->
          case Kanban.move_card(card, stage_id, target_index,
                 actor: socket.assigns.current_scope.user
               ) do
            {:ok, _} ->
              # Broadcast refreshes both :cards and :expanded_card.
              {:noreply, socket}

            {:error, :invalid_transition} ->
              {:noreply, put_flash(socket, :error, "That move isn't allowed by the workflow.")}

            {:error, :invalid_stage} ->
              {:noreply, put_flash(socket, :error, "Unknown stage.")}
          end
      end
    end)
  end

  def handle_event("reorder_card", %{"id" => id, "index" => idx}, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(id)

      cond do
        is_nil(card) or card.board_id != socket.assigns.board.id ->
          {:noreply, put_flash(socket, :error, "Card not found.")}

        true ->
          case Kanban.reorder_card(card, parse_index(idx) || 0,
                 actor: socket.assigns.current_scope.user
               ) do
            {:ok, _} -> {:noreply, socket}
            _ -> {:noreply, put_flash(socket, :error, "Couldn't reorder card.")}
          end
      end
    end)
  end

  def handle_event("delete_card", %{"id" => id}, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(id)

      if card && card.board_id == socket.assigns.board.id do
        {:ok, _} = Kanban.delete_card(card, actor: socket.assigns.current_scope.user)
        # Broadcast refreshes :cards; handle_info closes the modal when the
        # card's gone (Kanban.get_card returns nil).
        {:noreply, socket}
      else
        {:noreply, socket}
      end
    end)
  end

  # All four input kinds (text/date/datetime/select) use phx-change with
  # `name="value"`, so the new value always arrives at params["value"].
  def handle_event("save_field", %{"card-id" => card_id, "field-id" => field_id} = params, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(card_id)
      field_id_int = field_id
      field = Enum.find(socket.assigns.board.fields, &(&1.id == field_id_int))
      value = params["value"] || ""

      cond do
        is_nil(card) or card.board_id != socket.assigns.board.id ->
          {:noreply, put_flash(socket, :error, "Card not found.")}

        is_nil(field) ->
          {:noreply, put_flash(socket, :error, "Unknown field.")}

        true ->
          case Kanban.set_card_field_value(card, field, value,
                 actor: socket.assigns.current_scope.user
               ) do
            {:ok, _} ->
              {:noreply, socket}

            {:error, :invalid_option} ->
              {:noreply, put_flash(socket, :error, "Pick one of the listed options.")}

            {:error, :invalid_value} ->
              {:noreply, put_flash(socket, :error, "That value isn't valid for this field.")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Couldn't save field.")}
          end
      end
    end)
  end

  def handle_event("add_note", %{"id" => card_id} = params, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(card_id)
      user = socket.assigns.current_scope.user

      cond do
        is_nil(card) or card.board_id != socket.assigns.board.id ->
          {:noreply, put_flash(socket, :error, "Card not found.")}

        true ->
          attrs = %{
            "body" => params["body"],
            "kind" => params["kind"]
          }

          # Optional stage override. Must belong to this card's board —
          # the LiveView form only ever offers stages from `@board.stages`,
          # but defence-in-depth.
          attrs =
            case params["board_stage_id"] do
              s when is_binary(s) and s != "" ->
                if Enum.any?(socket.assigns.board.stages, &(&1.id == s)),
                  do: Map.put(attrs, "board_stage_id", s),
                  else: attrs

              _ ->
                attrs
            end

          case Kanban.add_card_note(card, user, attrs) do
            {:ok, _} -> {:noreply, socket}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't add the note.")}
          end
      end
    end)
  end

  def handle_event("toggle_note", %{"id" => id}, socket) do
    guard_edit(socket, fn ->
      case find_note_on_open_card(socket, id) do
        nil ->
          {:noreply, socket}

        note ->
          {:ok, _} = Kanban.toggle_card_note_done(note)
          {:noreply, socket}
      end
    end)
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    guard_edit(socket, fn ->
      case find_note_on_open_card(socket, id) do
        nil ->
          {:noreply, socket}

        note ->
          {:ok, _} = Kanban.delete_card_note(note)
          {:noreply, socket}
      end
    end)
  end

  # Click on a note's stage label toggles a per-note inline picker.
  # Re-clicking the same note (or another) closes / re-opens accordingly.
  def handle_event("toggle_note_stage_picker", %{"id" => id}, socket) do
    current = socket.assigns.note_stage_picker_open_for
    next = if current == id, do: nil, else: id
    {:noreply, assign(socket, :note_stage_picker_open_for, next)}
  end

  def handle_event("set_note_stage", %{"id" => id, "stage-id" => stage_id}, socket) do
    guard_edit(socket, fn ->
      with %{} = note <- find_note_on_open_card(socket, id),
           true <- Enum.any?(socket.assigns.board.stages, &(&1.id == stage_id)),
           {:ok, _} <- Kanban.update_card_note(note, %{board_stage_id: stage_id}) do
        {:noreply, assign(socket, :note_stage_picker_open_for, nil)}
      else
        _ ->
          {:noreply,
           socket
           |> assign(:note_stage_picker_open_for, nil)
           |> put_flash(:error, "Couldn't reassign the note.")}
      end
    end)
  end

  def handle_event("save_card_as_template", %{"id" => card_id, "name" => name}, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(card_id)
      user = socket.assigns.current_scope.user
      name = (name || "") |> String.trim()

      cond do
        is_nil(card) or card.board_id != socket.assigns.board.id ->
          {:noreply, put_flash(socket, :error, "Card not found.")}

        name == "" ->
          {:noreply, put_flash(socket, :error, "Template needs a name.")}

        true ->
          case Kanban.save_card_as_template(card, user, name) do
            {:ok, _} ->
              {:noreply,
               socket
               |> assign(:card_templates, Kanban.list_card_templates(socket.assigns.board))
               |> put_flash(:info, "Saved as template “#{name}”.")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Couldn't save template — name taken?")}
          end
      end
    end)
  end

  def handle_event("toggle_label", %{"card-id" => card_id, "label-id" => label_id}, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(card_id)
      label_id_int = label_id

      label =
        Enum.find(socket.assigns.board.labels, &(&1.id == label_id_int))

      # Only allow applying a label that's in scope for the card's subboard;
      # a label already on the card stays toggleable so it can be removed.
      in_scope? =
        card && label &&
          (Kanban.BoardLabel.applies_to_subboard?(label, card.subboard_id) or
             Enum.any?(card.labels, &(&1.id == label.id)))

      if card && card.board_id == socket.assigns.board.id && in_scope? do
        case Kanban.toggle_card_label(card, label, actor: socket.assigns.current_scope.user) do
          {:ok, _} ->
            {:noreply, socket}

          {n, _} when is_integer(n) ->
            {:noreply, socket}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Couldn't change label.")}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("toggle_assignee", %{"card-id" => card_id, "user-id" => user_id}, socket) do
    guard_edit(socket, fn ->
      card = Kanban.get_card(card_id)
      user_id_int = user_id

      if card && card.board_id == socket.assigns.board.id do
        already? = Enum.any?(card.assignees, &(&1.id == user_id_int))

        target_user =
          Enum.find(assignable_users(socket.assigns.board), &(&1.id == user_id_int))

        if target_user do
          if already? do
            {_, _} =
              Kanban.unassign_user(card, target_user, actor: socket.assigns.current_scope.user)
          else
            {:ok, _} =
              Kanban.assign_user(card, target_user, actor: socket.assigns.current_scope.user)
          end

          # Broadcast refreshes :cards and :expanded_card.
          {:noreply, socket}
        else
          {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  defp guard_edit(socket, fun) do
    if Kanban.can_edit?(socket.assigns.role) do
      fun.()
    else
      {:noreply, put_flash(socket, :error, "Viewers can't change this board.")}
    end
  end

  defp parse_index(nil), do: nil
  defp parse_index(""), do: nil
  defp parse_index(i) when is_integer(i), do: i
  defp parse_index(s) when is_binary(s), do: String.to_integer(s)

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s), do: s

  ## --- template -----------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="px-4 sm:px-6 lg:px-8 py-4">
        <header class="flex items-center justify-between mb-4">
          <div>
            <.link navigate={~p"/boards"} class="text-xs opacity-60 hover:underline">
              ← All boards
            </.link>
            <h1 class="text-2xl font-bold mt-1">{@board.name}</h1>
            <p :if={@board.description} class="text-sm opacity-70">{@board.description}</p>
          </div>
          <div class="flex items-center gap-2">
            <span class="badge badge-ghost">your role: {@role}</span>
            <button
              type="button"
              phx-click="toggle_label_text"
              class="btn btn-ghost btn-sm"
              title={if @hide_label_text, do: "Show label text", else: "Hide label text"}
            >
              <.icon
                name={if @hide_label_text, do: "hero-eye-slash-micro", else: "hero-eye-micro"}
                class="size-4"
              />
              <span class="hidden sm:inline">Labels</span>
            </button>
            <.link navigate={~p"/boards/#{@board.id}/history"} class="btn btn-ghost btn-sm">
              <.icon name="hero-clock-micro" class="size-4" /> History
            </.link>
            <.link
              navigate={~p"/boards/#{@board.id}/settings"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-cog-6-tooth-micro" class="size-4" /> Settings
            </.link>
          </div>
        </header>

        <div :if={@board.stages == []} class="alert alert-warning">
          This board has no stages. Add some to the underlying template, then create a new board.
        </div>

        <div class="overflow-x-auto pb-4">
          <div
            id="kanban-board"
            phx-hook=".KanbanDnD"
            data-transitions={@transitions_json}
            data-can-edit={if Kanban.can_edit?(@role), do: "1", else: "0"}
            class="grid gap-3 min-w-fit"
            style={"grid-template-columns: 10rem repeat(#{length(@board.stages)}, 18rem);"}
          >
            <%!-- Header row: empty top-left + stage column headers --%>
            <div />
            <div
              :for={stage <- @board.stages}
              class="px-2 py-1 flex items-center gap-2"
            >
              <span
                :if={stage_color(stage.color)}
                class="size-3 rounded-full"
                style={"background: #{stage.color}"}
              />
              <h2 class="font-semibold text-sm">{stage.name}</h2>
              <span class="badge badge-ghost badge-sm">
                {length(cards_in_stage(@cards, stage.id))}
              </span>
            </div>

            <%!-- Default row + one row per subboard --%>
            <.row_label name="Default" />
            <.stage_cell
              :for={stage <- @board.stages}
              stage={stage}
              subboard_id=""
              cards={cards_for(@cards, stage.id, nil)}
              new_card_open?={@show_new_card_for == {stage.id, nil}}
              role={@role}
              new_card_form={@new_card_form}
              board={@board}
              card_templates={@card_templates}
              hide_label_text={@hide_label_text}
            />

            <%= for sb <- @board.subboards do %>
              <.row_label name={sb.name} subboard_id={sb.id} role={@role} />
              <.stage_cell
                :for={stage <- @board.stages}
                stage={stage}
                subboard_id={sb.id}
                cards={cards_for(@cards, stage.id, sb.id)}
                new_card_open?={@show_new_card_for == {stage.id, sb.id}}
                role={@role}
                new_card_form={@new_card_form}
                board={@board}
                card_templates={@card_templates}
                hide_label_text={@hide_label_text}
              />
            <% end %>
          </div>
        </div>
      </div>

      <%= if @expanded_card do %>
        <.card_detail
          card={@expanded_card}
          board={@board}
          role={@role}
          targets={Kanban.allowed_targets(@expanded_card)}
          editing={@editing_card}
          edit_form={@card_edit_form}
          note_stage_picker_open_for={@note_stage_picker_open_for}
        />
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".KanbanDnD" phx-no-curly-interpolation>
        export default {
          mounted() {
            const board = this.el;
            if (board.dataset.canEdit !== "1") return;

            const transitions = JSON.parse(board.dataset.transitions || "{}");
            let dragCardId = null;
            let dragSourceStage = null;
            let dragSourceSubboard = null;
            let dropIndex = null;

            const cols = () => Array.from(board.querySelectorAll("[data-stage-id]"));

            const allowedFor = (fromStage) =>
              (transitions[fromStage] || []).map(String);

            // Same column is always a legal drop (it's a reorder); cross-column
            // is only legal if the workflow allows it.
            const isLegalDrop = (sid) =>
              sid === dragSourceStage || allowedFor(dragSourceStage).includes(sid);

            const clearColumnMarks = () => {
              cols().forEach(c => {
                c.classList.remove(
                  "border-success", "border-error", "border-dashed",
                  "bg-success/10", "bg-error/10"
                );
              });
            };

            const clearDropMarkers = () => {
              board.querySelectorAll(".drop-marker").forEach(m => m.remove());
            };

            // Cards inside `col`, excluding the one being dragged (it's still
            // in the DOM during HTML5 drag).
            const liveCards = (col) =>
              Array.from(col.querySelectorAll("[data-card-id]"))
                .filter(c => c.dataset.cardId !== dragCardId);

            const computeDropIndex = (col, clientY) => {
              const cards = liveCards(col);
              for (let i = 0; i < cards.length; i++) {
                const r = cards[i].getBoundingClientRect();
                if (clientY < r.top + r.height / 2) return i;
              }
              return cards.length;
            };

            const showDropMarker = (col, index) => {
              clearDropMarkers();
              const marker = document.createElement("div");
              marker.className = "drop-marker h-1 bg-primary rounded -my-0.5";
              const list = col.querySelector("[data-cards-list]");
              if (!list) return;
              const cards = liveCards(col);
              if (index >= cards.length) {
                list.appendChild(marker);
              } else {
                list.insertBefore(marker, cards[index]);
              }
            };

            board.addEventListener("dragstart", (e) => {
              const card = e.target.closest("[data-card-id]");
              if (!card) return;
              dragCardId = card.dataset.cardId;
              dragSourceStage = card.dataset.sourceStageId;
              dragSourceSubboard = card.dataset.sourceSubboardId || "";
              e.dataTransfer.effectAllowed = "move";
              e.dataTransfer.setData("text/plain", dragCardId);
              card.classList.add("opacity-40");

              const allowed = new Set(allowedFor(dragSourceStage));
              cols().forEach(c => {
                const sid = c.dataset.stageId;
                if (sid === dragSourceStage) return;
                if (allowed.has(sid)) {
                  c.classList.add("border-success", "border-dashed", "bg-success/10");
                } else {
                  c.classList.add("border-error", "border-dashed", "bg-error/10");
                }
              });
            });

            board.addEventListener("dragend", (e) => {
              const card = e.target.closest("[data-card-id]");
              if (card) card.classList.remove("opacity-40");
              clearColumnMarks();
              clearDropMarkers();
              dragCardId = null;
              dragSourceStage = null;
              dragSourceSubboard = null;
              dropIndex = null;
            });

            board.addEventListener("dragover", (e) => {
              if (!dragCardId) return;
              const col = e.target.closest("[data-stage-id]");
              if (!col) return;
              if (!isLegalDrop(col.dataset.stageId)) return;

              e.preventDefault();
              dropIndex = computeDropIndex(col, e.clientY);
              showDropMarker(col, dropIndex);
            });

            board.addEventListener("dragleave", (e) => {
              const col = e.target.closest("[data-stage-id]");
              if (!col) return;
              // Only clear when leaving the column entirely, not when crossing
              // child element boundaries inside it.
              if (!col.contains(e.relatedTarget)) clearDropMarkers();
            });

            board.addEventListener("drop", (e) => {
              if (!dragCardId) return;
              const col = e.target.closest("[data-stage-id]");
              if (!col) return;
              e.preventDefault();

              const sid = col.dataset.stageId;
              const subId = col.dataset.subboardId || "";
              const idx = dropIndex != null ? dropIndex : computeDropIndex(col, e.clientY);

              clearDropMarkers();

              // Unified landing point: server orchestrates stage move
              // (enforces transition) and subboard reassignment in one
              // event. Same-stage drops fall through to reorder server-side.
              if (sid === dragSourceStage || allowedFor(dragSourceStage).includes(sid)) {
                this.pushEvent("place_card", {
                  id: dragCardId,
                  "stage-id": sid,
                  "subboard-id": subId,
                  index: idx
                });
              }
            });
          }
        }
      </script>
    </Layouts.app>
    """
  end

  ## --- card detail modal --------------------------------------------------

  ## --- grid cell components -----------------------------------------------

  attr :name, :string, required: true
  attr :subboard_id, :string, default: nil
  attr :role, :string, default: nil

  defp row_label(assigns) do
    ~H"""
    <div class="px-2 py-2 flex items-start gap-1 text-sm font-medium border-r border-base-300/40">
      <span class="flex-1 truncate" title={@name}>{@name}</span>
    </div>
    """
  end

  attr :stage, :map, required: true
  attr :subboard_id, :string, default: nil
  attr :cards, :list, required: true
  attr :new_card_open?, :boolean, default: false
  attr :role, :string, required: true
  attr :new_card_form, :any, required: true
  attr :board, :map, required: true
  attr :card_templates, :list, default: []
  attr :hide_label_text, :boolean, default: false

  defp stage_cell(assigns) do
    ~H"""
    <div
      data-stage-id={@stage.id}
      data-subboard-id={@subboard_id}
      class="bg-base-200 border-2 border-base-300 rounded-box flex flex-col min-h-[6rem] transition-colors"
    >
      <header class="px-2 pt-1 pb-1 flex items-center justify-end">
        <button
          :if={Kanban.can_edit?(@role)}
          type="button"
          phx-click="show_new_card"
          phx-value-stage-id={@stage.id}
          phx-value-subboard-id={@subboard_id}
          class="btn btn-ghost btn-xs"
          title="New card here"
        >
          <.icon name="hero-plus-micro" class="size-3" />
        </button>
      </header>

      <div class="p-2 pt-0 flex flex-col gap-2" data-cards-list>
        <div :if={@new_card_open?} class="border border-base-300 rounded-box p-2 bg-base-100">
          <.form
            for={@new_card_form}
            id={"new-card-form-#{@stage.id}-#{@subboard_id || "default"}"}
            phx-submit="create_card"
          >
            <.input
              field={@new_card_form[:title]}
              type="text"
              label="Title"
              required
              phx-mounted={JS.focus()}
            />
            <.input field={@new_card_form[:description]} type="text" label="Description" />
            <%= if @card_templates != [] do %>
              <label class="label-text text-xs mt-2">From template (optional)</label>
              <select
                name="card[template_id]"
                class="select select-sm select-bordered w-full"
              >
                <option value="">— blank —</option>
                <option :for={t <- @card_templates} value={t.id}>{t.name}</option>
              </select>
            <% end %>
            <div class="flex gap-2 mt-2">
              <.button class="btn btn-primary btn-sm">Create</.button>
              <button type="button" phx-click="cancel_new_card" class="btn btn-ghost btn-sm">
                Cancel
              </button>
            </div>
          </.form>
        </div>

        <article
          :for={card <- @cards}
          id={"card-#{card.id}"}
          draggable={Kanban.can_edit?(@role) && "true"}
          data-card-id={card.id}
          data-source-stage-id={@stage.id}
          data-source-subboard-id={@subboard_id}
          class="border border-base-300 rounded-box p-2 bg-base-100 cursor-pointer hover:bg-base-200"
          phx-click="expand_card"
          phx-value-id={card.id}
        >
          <div :if={card.labels != []} class="flex flex-wrap gap-1 mb-1">
            <%= if @hide_label_text do %>
              <span
                :for={lab <- card.labels}
                class="inline-block size-2.5 rounded-full border border-base-content/20"
                style={"background: #{lab.color || "#888"}"}
                title={lab.name}
              />
            <% else %>
              <span
                :for={lab <- card.labels}
                class="badge badge-xs"
                style={label_style(lab)}
                title={lab.name}
              >
                {lab.name}
              </span>
            <% end %>
          </div>
          <p class="font-medium text-sm">{card.title}</p>
          <p :if={card.description} class="text-xs opacity-70 mt-1 line-clamp-2">
            {card.description}
          </p>
          <% inline_fields = visible_field_values(card, @board) %>
          <div :if={inline_fields != []} class="flex flex-wrap gap-1 mt-2">
            <span
              :for={{field, value} <- inline_fields}
              class="badge badge-ghost badge-xs"
              title={"#{field.name}: #{value}"}
            >
              <.icon name={field_icon(field)} class="size-3" />
              {format_field_value(field, value)}
            </span>
          </div>
          <div :if={card.assignees != []} class="flex flex-wrap gap-1 mt-2">
            <span :for={a <- card.assignees} class="badge badge-ghost badge-xs font-mono">
              {assignee_label(a)}
            </span>
          </div>
          <% note_counts = count_notes(card) %>
          <div
            :if={note_counts.notes > 0 or note_counts.todo_total > 0}
            class="flex gap-2 mt-2 text-[10px] opacity-60"
          >
            <span :if={note_counts.notes > 0} title="Notes" class="inline-flex items-center gap-0.5">
              <.icon name="hero-document-text-micro" class="size-3" /> {note_counts.notes}
            </span>
            <span
              :if={note_counts.todo_total > 0}
              title="Todos done/total"
              class="inline-flex items-center gap-0.5"
            >
              <.icon name="hero-check-circle-micro" class="size-3" />
              {note_counts.todo_done}/{note_counts.todo_total}
            </span>
          </div>
        </article>
      </div>
    </div>
    """
  end

  ## --- card detail modal --------------------------------------------------

  attr :card, :map, required: true
  attr :board, :map, required: true
  attr :role, :string, required: true
  attr :targets, :list, required: true
  attr :editing, :boolean, default: false
  attr :edit_form, :any, default: nil
  attr :note_stage_picker_open_for, :any, default: nil

  defp card_detail(assigns) do
    ~H"""
    <div
      id="card-modal-backdrop"
      class="fixed inset-0 bg-black/40 z-40"
      phx-click="collapse_card"
    />
    <div
      id="card-modal"
      class="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-base-100 border border-base-300 rounded-box w-[90vw] max-w-xl max-h-[85vh] overflow-y-auto z-50 shadow-xl"
    >
      <div class="p-4 border-b border-base-300 flex items-start gap-3">
        <div class="flex-1 min-w-0">
          <p class="text-xs opacity-60 mb-1">In stage: {@card.board_stage.name}</p>

          <%= if @editing do %>
            <.form
              for={@edit_form}
              id="card-edit-form"
              phx-submit="save_card_edit"
              phx-change="validate_card_edit"
              class="space-y-2"
            >
              <.input
                field={@edit_form[:title]}
                type="text"
                label="Title"
                required
                phx-mounted={JS.focus()}
              />
              <.input
                field={@edit_form[:description]}
                type="textarea"
                label="Description"
                rows="5"
              />
              <div class="flex gap-2 pt-1">
                <.button class="btn btn-primary btn-sm">Save</.button>
                <button
                  type="button"
                  phx-click="cancel_card_edit"
                  class="btn btn-ghost btn-sm"
                >
                  Cancel
                </button>
              </div>
            </.form>
          <% else %>
            <h2 class="text-lg font-bold">{@card.title}</h2>
            <p :if={@card.description} class="text-sm opacity-80 mt-2 whitespace-pre-wrap">
              {@card.description}
            </p>
          <% end %>
        </div>
        <div class="flex flex-col gap-1 shrink-0">
          <button
            :if={Kanban.can_edit?(@role) and not @editing}
            type="button"
            phx-click="start_card_edit"
            class="btn btn-ghost btn-sm"
            aria-label="Edit"
            title="Edit title and description"
          >
            <.icon name="hero-pencil-square-micro" class="size-4" />
          </button>
          <button
            type="button"
            phx-click="collapse_card"
            class="btn btn-ghost btn-sm"
            aria-label="Close"
          >
            <.icon name="hero-x-mark-micro" class="size-4" />
          </button>
        </div>
      </div>

      <div :if={labels_for_card(@board.labels, @card) != []} class="p-4 border-b border-base-300">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60 mb-2">Labels</h3>
        <div class="flex flex-wrap gap-1">
          <button
            :for={lab <- labels_for_card(@board.labels, @card)}
            type="button"
            phx-click="toggle_label"
            phx-value-card-id={@card.id}
            phx-value-label-id={lab.id}
            disabled={not Kanban.can_edit?(@role)}
            class={[
              "badge badge-sm",
              if(Enum.any?(@card.labels, &(&1.id == lab.id)),
                do: "",
                else: "opacity-40 hover:opacity-100"
              )
            ]}
            style={label_style(lab)}
          >
            {lab.name}
          </button>
        </div>
      </div>

      <div :if={@board.fields != []} class="p-4 border-b border-base-300">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60 mb-2">
          Fields
        </h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div :for={f <- @board.fields} class="flex flex-col gap-1">
            <label class="text-xs opacity-70">{f.name}</label>
            <.form
              for={%{}}
              as={:field}
              id={"field-form-#{@card.id}-#{f.id}"}
              phx-change="save_field"
              phx-value-field-id={f.id}
              phx-value-card-id={@card.id}
            >
              <%= case f.kind do %>
                <% "text" -> %>
                  <input
                    type="text"
                    name="value"
                    value={card_field_value(@card, f)}
                    phx-debounce="blur"
                    disabled={not Kanban.can_edit?(@role)}
                    class="input input-sm input-bordered w-full"
                  />
                <% "date" -> %>
                  <input
                    type="date"
                    name="value"
                    value={card_field_date(@card, f)}
                    disabled={not Kanban.can_edit?(@role)}
                    class="input input-sm input-bordered w-full"
                  />
                <% "datetime" -> %>
                  <input
                    type="datetime-local"
                    name="value"
                    value={card_field_datetime(@card, f)}
                    disabled={not Kanban.can_edit?(@role)}
                    class="input input-sm input-bordered w-full"
                  />
                <% "select" -> %>
                  <select
                    name="value"
                    disabled={not Kanban.can_edit?(@role)}
                    class="select select-sm select-bordered w-full"
                  >
                    <option value="">— none —</option>
                    <option
                      :for={opt <- f.options || []}
                      value={opt}
                      selected={card_field_value(@card, f) == opt}
                    >
                      {opt}
                    </option>
                  </select>
              <% end %>
            </.form>
          </div>
        </div>
      </div>

      <div class="p-4 border-b border-base-300">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60 mb-2">Assignees</h3>
        <div class="flex flex-wrap gap-1">
          <button
            :for={u <- assignable_users(@board)}
            type="button"
            phx-click="toggle_assignee"
            phx-value-card-id={@card.id}
            phx-value-user-id={u.id}
            disabled={not Kanban.can_edit?(@role)}
            class={[
              "badge badge-sm",
              if(Enum.any?(@card.assignees, &(&1.id == u.id)),
                do: "badge-primary",
                else: "badge-ghost"
              )
            ]}
          >
            {assignee_label(u)}
          </button>
        </div>
      </div>

      <div class="p-4 border-b border-base-300">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60 mb-2">
          Notes &amp; todos
        </h3>

        <ul class="flex flex-col gap-1 mb-2">
          <li :if={@card.notes == []} class="text-xs opacity-60 italic">
            Nothing yet. Add a note or a todo below.
          </li>
          <li
            :for={n <- @card.notes}
            id={"note-#{n.id}"}
            class="flex items-start gap-2 rounded px-2 py-1"
            style={"background-color: #{note_stage_color_bg(n, @board)}"}
          >
            <%= if n.kind == "todo" do %>
              <input
                type="checkbox"
                checked={n.done}
                disabled={not Kanban.can_edit?(@role)}
                phx-click="toggle_note"
                phx-value-id={n.id}
                class="checkbox checkbox-xs mt-1"
              />
            <% else %>
              <.icon name="hero-document-text-micro" class="size-4 mt-1 opacity-60 shrink-0" />
            <% end %>
            <div class="flex-1 min-w-0">
              <p class={[
                "text-sm whitespace-pre-wrap break-words",
                n.kind == "todo" and n.done and "line-through opacity-60"
              ]}>
                {n.body}
              </p>
              <%= if Kanban.can_edit?(@role) do %>
                <button
                  type="button"
                  phx-click="toggle_note_stage_picker"
                  phx-value-id={n.id}
                  class="text-[10px] opacity-60 mt-0.5 hover:opacity-100 hover:underline cursor-pointer"
                  title="Click to reassign stage"
                >
                  {note_stage_name(n, @board)}
                </button>
                <div
                  :if={@note_stage_picker_open_for == n.id}
                  class="flex flex-wrap gap-1 mt-1"
                >
                  <button
                    :for={s <- @board.stages}
                    type="button"
                    phx-click="set_note_stage"
                    phx-value-id={n.id}
                    phx-value-stage-id={s.id}
                    class={[
                      "btn btn-xs btn-outline",
                      s.id == n.board_stage_id and "btn-active"
                    ]}
                  >
                    {s.name}
                  </button>
                </div>
              <% else %>
                <p class="text-[10px] opacity-60 mt-0.5">
                  {note_stage_name(n, @board)}
                </p>
              <% end %>
            </div>
            <button
              :if={Kanban.can_edit?(@role)}
              type="button"
              phx-click="delete_note"
              phx-value-id={n.id}
              class="btn btn-ghost btn-xs text-error"
              title="Delete"
            >
              <.icon name="hero-x-mark-micro" class="size-3" />
            </button>
          </li>
        </ul>

        <.form
          :if={Kanban.can_edit?(@role)}
          for={%{}}
          as={:note}
          phx-submit="add_note"
          phx-value-id={@card.id}
          class="flex flex-col gap-2"
        >
          <div class="flex items-end gap-2">
            <input
              type="text"
              name="body"
              placeholder="Write a note or todo…"
              required
              class="input input-sm input-bordered flex-1"
            />
            <select name="kind" class="select select-sm select-bordered">
              <option value="note">Note</option>
              <option value="todo">Todo</option>
            </select>
            <.button class="btn btn-primary btn-sm">Add</.button>
          </div>
          <label class="text-xs opacity-70 flex items-center gap-2">
            Log against
            <select name="board_stage_id" class="select select-xs select-bordered">
              <option :for={s <- @board.stages} value={s.id} selected={s.id == @card.board_stage_id}>
                {s.name}
              </option>
            </select>
          </label>
        </.form>
      </div>

      <div class="p-4 border-b border-base-300">
        <h3 class="text-xs font-semibold uppercase tracking-wider opacity-60 mb-2">
          Move to (allowed transitions)
        </h3>
        <%= if @targets == [] do %>
          <p class="text-sm opacity-60">
            No outgoing transitions from this stage. This card is at a terminal state.
          </p>
        <% else %>
          <div class="flex flex-wrap gap-2">
            <button
              :for={t <- @targets}
              type="button"
              phx-click="move_card"
              phx-value-id={@card.id}
              phx-value-stage-id={t.stage_id}
              disabled={not Kanban.can_edit?(@role)}
              class="btn btn-sm btn-outline"
            >
              {t.name}
              <span :if={t.label} class="opacity-60 text-xs">({t.label})</span>
            </button>
          </div>
        <% end %>
      </div>

      <div class="p-4 flex justify-between items-center gap-2">
        <.form
          :if={Kanban.can_edit?(@role)}
          for={%{}}
          as={:template}
          phx-submit="save_card_as_template"
          phx-value-id={@card.id}
          class="flex items-center gap-2"
        >
          <input
            type="text"
            name="name"
            placeholder="Template name"
            required
            class="input input-xs input-bordered w-36"
          />
          <.button class="btn btn-ghost btn-xs">
            <.icon name="hero-bookmark-square-micro" class="size-4" /> Save as template
          </.button>
        </.form>
        <button
          :if={Kanban.can_edit?(@role)}
          type="button"
          phx-click="delete_card"
          phx-value-id={@card.id}
          data-confirm="Delete this card?"
          class="btn btn-ghost btn-sm text-error"
        >
          <.icon name="hero-trash-micro" class="size-4" /> Delete card
        </button>
      </div>
    </div>
    """
  end

  defp assignee_label(%{display_name: name}) when is_binary(name) and name != "", do: name

  defp assignee_label(%{email: email}) when is_binary(email),
    do: hd(String.split(email, "@"))

  defp assignee_label(_), do: "anon"

  # Inline style for a label chip. Uses the label's color as background
  # with a derived dark foreground for legibility. Falls back to a neutral
  # ghost style when no color is set.
  defp label_style(%{color: c}) when is_binary(c) and c != "",
    do: "background-color: #{c}; color: #111; border-color: transparent;"

  defp label_style(_), do: ""

  # Labels offered in a card's label picker: board-wide labels plus any
  # scoped to the card's subboard, unioned with labels already on the card
  # (so a label that was later scoped away can still be removed).
  defp labels_for_card(labels, card) do
    on_card = MapSet.new(card.labels, & &1.id)

    Enum.filter(labels, fn lab ->
      Kanban.BoardLabel.applies_to_subboard?(lab, card.subboard_id) or
        MapSet.member?(on_card, lab.id)
    end)
  end

  # Looks up a note id against the currently-expanded card. Keeps the
  # match scoped to the card the user is actually viewing — a stray
  # phx-value-id from a previous render can't reach a note on someone
  # else's card.
  defp find_note_on_open_card(socket, note_id) do
    case socket.assigns.expanded_card do
      %{notes: notes} -> Enum.find(notes, &(&1.id == note_id))
      _ -> nil
    end
  end

  defp note_stage_color(%{board_stage_id: nil}, _board), do: nil

  defp note_stage_color(%{board_stage_id: stage_id}, board) do
    case Enum.find(board.stages, &(&1.id == stage_id)) do
      %{color: c} when is_binary(c) and c != "" -> c
      _ -> nil
    end
  end

  # Background tint for a note row. Returns "transparent" when there's no
  # stage color; otherwise an rgba(...) with the stage hue at low alpha
  # so body text stays readable. Matches the Android card sheet's
  # whole-row tint (see ui/CardSheet.kt's `NoteRow`).
  defp note_stage_color_bg(note, board) do
    case note_stage_color(note, board) do
      nil -> "transparent"
      hex -> hex_to_rgba(hex, 0.18) || "transparent"
    end
  end

  defp hex_to_rgba("#" <> rest, alpha), do: hex_to_rgba(rest, alpha)

  defp hex_to_rgba(<<r1, r2, g1, g2, b1, b2>>, alpha) do
    with {r, ""} <- Integer.parse(<<r1, r2>>, 16),
         {g, ""} <- Integer.parse(<<g1, g2>>, 16),
         {b, ""} <- Integer.parse(<<b1, b2>>, 16) do
      "rgba(#{r}, #{g}, #{b}, #{alpha})"
    else
      _ -> nil
    end
  end

  defp hex_to_rgba(<<r, g, b>>, alpha) do
    hex_to_rgba(<<r, r, g, g, b, b>>, alpha)
  end

  defp hex_to_rgba(_, _), do: nil

  defp note_stage_name(%{board_stage_id: nil}, _board), do: "(no stage)"

  defp note_stage_name(%{board_stage_id: stage_id}, board) do
    case Enum.find(board.stages, &(&1.id == stage_id)) do
      %{name: name} -> name
      _ -> "(stage gone)"
    end
  end

  # Tally for the kanban tile chip row: how many freeform notes vs how
  # many todos (done / total).
  defp count_notes(card) do
    Enum.reduce(card.notes || [], %{notes: 0, todo_total: 0, todo_done: 0}, fn n, acc ->
      case n.kind do
        "todo" ->
          %{
            acc
            | todo_total: acc.todo_total + 1,
              todo_done: acc.todo_done + if(n.done, do: 1, else: 0)
          }

        _ ->
          %{acc | notes: acc.notes + 1}
      end
    end)
  end

  # Fields whose values should be surfaced on the kanban tile.
  defp visible_field_values(card, board) do
    by_id = Map.new(card.field_values, &{&1.board_field_id, &1.value})

    for f <- board.fields,
        f.show_on_card,
        value = Map.get(by_id, f.id),
        is_binary(value) and value != "" do
      {f, value}
    end
  end

  defp field_icon(%{kind: "date"}), do: "hero-calendar-days-micro"
  defp field_icon(%{kind: "datetime"}), do: "hero-clock-micro"
  defp field_icon(%{kind: "select"}), do: "hero-list-bullet-micro"
  defp field_icon(_), do: "hero-document-text-micro"

  # Renders a stored value as something humans want to look at on a card.
  defp format_field_value(%{kind: "date"}, iso) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, d} -> Calendar.strftime(d, "%b %-d")
      _ -> iso
    end
  end

  defp format_field_value(%{kind: "datetime"}, iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%b %-d %H:%M")
      _ -> iso
    end
  end

  defp format_field_value(_field, value), do: value

  # Helpers for rendering input values in the modal.
  defp card_field_value(card, %{id: field_id}) do
    case Enum.find(card.field_values, &(&1.board_field_id == field_id)) do
      %{value: v} -> v
      _ -> ""
    end
  end

  defp card_field_date(card, field) do
    case card_field_value(card, field) do
      v when is_binary(v) and v != "" ->
        case Date.from_iso8601(v) do
          {:ok, d} -> Date.to_iso8601(d)
          _ -> ""
        end

      _ ->
        ""
    end
  end

  defp card_field_datetime(card, field) do
    case card_field_value(card, field) do
      v when is_binary(v) and v != "" ->
        case DateTime.from_iso8601(v) do
          {:ok, dt, _} ->
            # `datetime-local` wants "YYYY-MM-DDTHH:MM" (no seconds, no TZ).
            dt
            |> DateTime.truncate(:second)
            |> DateTime.to_naive()
            |> NaiveDateTime.to_iso8601()
            |> String.slice(0, 16)

          _ ->
            ""
        end

      _ ->
        ""
    end
  end
end
