defmodule WaxxWeb.BoardLive.Settings do
  use WaxxWeb, :live_view

  alias Waxx.Kanban

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

      board ->
        role = Kanban.role_for(board_id, user)

        socket =
          socket
          |> assign(:page_title, "#{board.name} · settings")
          |> assign(:board, board)
          |> assign(:role, role)
          |> assign(:members, Kanban.list_members(board_id))
          |> assign(:invites, Kanban.list_board_invites(board))
          |> assign(:invite_form, to_form(%{"role" => "editor", "note" => ""}, as: "invite"))
          |> assign(:board_form, to_form(Kanban.change_board(board)))
          |> assign(:subboards, Kanban.list_subboards(board))
          |> assign(:subboard_form, to_form(%{"name" => ""}, as: "subboard"))
          |> assign(:labels, Kanban.list_board_labels(board))
          |> assign(:label_form, blank_label_form())

        {:ok, socket}
    end
  end

  @impl true
  def handle_event("rename_board", %{"board" => params}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      case Kanban.update_board(socket.assigns.board, params) do
        {:ok, board} ->
          {:noreply,
           socket
           |> assign(:board, board)
           |> assign(:board_form, to_form(Kanban.change_board(board)))
           |> put_flash(:info, "Board updated.")}

        {:error, cs} ->
          {:noreply, assign(socket, :board_form, to_form(cs))}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can rename the board.")}
    end
  end

  def handle_event("create_invite", %{"invite" => params}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      case Kanban.create_board_invite(
             socket.assigns.board,
             socket.assigns.current_scope.user,
             params
           ) do
        {:ok, _invite} ->
          invites = Kanban.list_board_invites(socket.assigns.board)
          {:noreply, socket |> assign(:invites, invites) |> put_flash(:info, "Invite created.")}

        {:error, _cs} ->
          {:noreply, put_flash(socket, :error, "Could not create invite.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can mint invites.")}
    end
  end

  def handle_event("revoke_invite", %{"id" => id}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      invite = Enum.find(socket.assigns.invites, &(&1.id == id))

      if invite do
        {:ok, _} = Kanban.revoke_board_invite(invite)
        invites = Kanban.list_board_invites(socket.assigns.board)
        {:noreply, assign(socket, :invites, invites)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can revoke invites.")}
    end
  end

  def handle_event("update_member_role", %{"membership_id" => id, "role" => role}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      m = Enum.find(socket.assigns.members, &(&1.id == id))

      cond do
        is_nil(m) ->
          {:noreply, socket}

        m.role == "owner" ->
          {:noreply, put_flash(socket, :error, "Can't change the owner's role.")}

        true ->
          {:ok, _} = Kanban.update_member_role(m, role)
          members = Kanban.list_members(socket.assigns.board.id)
          {:noreply, assign(socket, :members, members)}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can change roles.")}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      m = Enum.find(socket.assigns.members, &(&1.id == id))

      cond do
        is_nil(m) ->
          {:noreply, socket}

        m.role == "owner" ->
          {:noreply, put_flash(socket, :error, "Can't remove the owner.")}

        true ->
          {:ok, _} = Kanban.remove_member(m)
          members = Kanban.list_members(socket.assigns.board.id)
          {:noreply, assign(socket, :members, members)}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can remove members.")}
    end
  end

  def handle_event("create_label", %{"label" => params}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      case Kanban.create_board_label(socket.assigns.board, params) do
        {:ok, tag, _} ->
          flash = if tag == :updated, do: "Label updated.", else: "Label added."

          {:noreply,
           socket
           |> assign(:labels, Kanban.list_board_labels(socket.assigns.board))
           |> assign(:label_form, blank_label_form())
           |> put_flash(:info, flash)}

        {:error, cs} ->
          {:noreply, put_flash(socket, :error, "Could not add label: #{format_errors(cs)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can add labels.")}
    end
  end

  def handle_event("delete_label", %{"id" => id}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      label = Enum.find(socket.assigns.labels, &(&1.id == id))

      case label && Kanban.delete_board_label(label) do
        nil ->
          {:noreply, socket}

        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:labels, Kanban.list_board_labels(socket.assigns.board))
           |> put_flash(:info, "Label deleted.")}

        {:error, :in_use} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "That label is still attached to cards — remove it there first."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete label.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can delete labels.")}
    end
  end

  def handle_event("create_subboard", %{"subboard" => params}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      case Kanban.create_subboard(socket.assigns.board, params) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:subboards, Kanban.list_subboards(socket.assigns.board))
           |> assign(:subboard_form, to_form(%{"name" => ""}, as: "subboard"))
           |> put_flash(:info, "Subboard added.")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add subboard.")}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can add subboards.")}
    end
  end

  def handle_event("delete_subboard", %{"id" => id}, socket) do
    if Kanban.can_manage?(socket.assigns.role) do
      sb = Enum.find(socket.assigns.subboards, &(&1.id == id))

      if sb do
        {:ok, _} = Kanban.delete_subboard(sb)

        {:noreply,
         socket
         |> assign(:subboards, Kanban.list_subboards(socket.assigns.board))
         |> put_flash(:info, "Subboard deleted.")}
      else
        {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Only the owner can delete subboards.")}
    end
  end

  defp blank_label_form do
    to_form(%{"name" => "", "color" => "", "subboard_ids" => []}, as: "label")
  end

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map_join(errors, ", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto py-6 space-y-8">
        <header>
          <.link navigate={~p"/boards/#{@board.id}"} class="text-xs opacity-60 hover:underline">
            ← Back to board
          </.link>
          <h1 class="text-2xl font-bold mt-1">
            {@board.name} <span class="text-base opacity-60">· settings</span>
          </h1>
          <p class="text-xs opacity-60 mt-1">
            Your role: <span class="badge badge-ghost">{@role}</span>
          </p>
        </header>

        <section>
          <h2 class="text-lg font-semibold mb-2">General</h2>
          <.form
            for={@board_form}
            id="board-form"
            phx-submit="rename_board"
            class="flex flex-col gap-2"
          >
            <.input field={@board_form[:name]} type="text" label="Name" required />
            <.input field={@board_form[:description]} type="text" label="Description" />
            <.input
              field={@board_form[:archive_terminal_after_days]}
              type="number"
              min="1"
              label="Archive after N days in terminal stage (leave blank to never archive)"
            />
            <.button class="btn btn-primary w-fit" disabled={not Kanban.can_manage?(@role)}>
              Save
            </.button>
          </.form>
        </section>

        <section>
          <h2 class="text-lg font-semibold mb-2">Members</h2>
          <ul class="flex flex-col gap-2">
            <li
              :for={m <- @members}
              id={"member-#{m.id}"}
              class="border border-base-300 rounded-box p-2 bg-base-200 flex items-center gap-3"
            >
              <span class="font-mono text-xs opacity-60 w-6 text-right">{m.user.id}</span>
              <span class="flex-1 truncate">
                {m.user.email || m.user.display_name || "anonymous"}
              </span>
              <%= if m.role == "owner" or not Kanban.can_manage?(@role) do %>
                <span class="badge badge-ghost">{m.role}</span>
              <% else %>
                <form phx-change="update_member_role" class="flex items-center gap-2">
                  <input type="hidden" name="membership_id" value={m.id} />
                  <select name="role" class="select select-xs select-bordered">
                    <option value="editor" selected={m.role == "editor"}>editor</option>
                    <option value="viewer" selected={m.role == "viewer"}>viewer</option>
                  </select>
                </form>
                <button
                  type="button"
                  phx-click="remove_member"
                  phx-value-id={m.id}
                  data-confirm="Remove this member from the board?"
                  class="btn btn-ghost btn-xs text-error"
                  title="Remove"
                >
                  <.icon name="hero-x-mark-micro" class="size-4" />
                </button>
              <% end %>
            </li>
          </ul>
        </section>

        <section>
          <h2 class="text-lg font-semibold mb-2">Board invites</h2>
          <p class="text-sm opacity-70 mb-3">
            Each link can be used once to join this board. Recipients must already have an
            account; the link grants membership, not registration.
          </p>

          <%= if Kanban.can_manage?(@role) do %>
            <.form
              for={@invite_form}
              id="invite-form"
              phx-submit="create_invite"
              class="grid grid-cols-1 sm:grid-cols-3 gap-2 items-end mb-4"
            >
              <.input
                field={@invite_form[:role]}
                type="select"
                label="Role"
                options={[{"editor", "editor"}, {"viewer", "viewer"}]}
              />
              <.input field={@invite_form[:note]} type="text" label="Note (optional)" />
              <.button class="btn btn-primary">Mint invite</.button>
            </.form>
          <% end %>

          <ul class="flex flex-col gap-2">
            <li :if={@invites == []} class="text-center text-sm opacity-60 py-4">
              No invites yet.
            </li>
            <li
              :for={i <- @invites}
              id={"binvite-#{i.id}"}
              class={[
                "border border-base-300 rounded-box p-3 flex items-center gap-3 bg-base-200",
                i.consumed_at && "opacity-60"
              ]}
            >
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 text-xs">
                  <span class="badge badge-ghost">{i.role}</span>
                  <%= cond do %>
                    <% i.consumed_at && i.consumed_by_id -> %>
                      <span class="badge badge-ghost">used</span>
                    <% i.consumed_at -> %>
                      <span class="badge badge-error">revoked</span>
                    <% true -> %>
                      <span class="badge badge-success">active</span>
                  <% end %>
                </div>
                <code class="block mt-1 text-xs font-mono truncate">
                  {url(~p"/b/#{i.token}")}
                </code>
                <p :if={i.consumed_by} class="text-xs opacity-70 mt-1">
                  Redeemed by <span class="font-mono">{i.consumed_by.email}</span>
                </p>
              </div>
              <button
                :if={is_nil(i.consumed_at) and Kanban.can_manage?(@role)}
                type="button"
                phx-click="revoke_invite"
                phx-value-id={i.id}
                class="btn btn-ghost btn-xs text-error"
              >
                <.icon name="hero-x-mark-micro" class="size-4" />
              </button>
            </li>
          </ul>
        </section>

        <section>
          <h2 class="text-lg font-semibold mb-2">Labels</h2>
          <p class="text-sm opacity-70 mb-3">
            Labels start as a copy of the board's template, but the board
            owns its list — add more here without touching the template.
            A label still attached to cards can't be deleted.
          </p>

          <ul class="flex flex-wrap gap-2 mb-3">
            <li :if={@labels == []} class="text-sm opacity-60">
              No labels yet.
            </li>
            <li
              :for={lab <- @labels}
              id={"board-label-#{lab.id}"}
              class="border border-base-300 rounded-box pl-2 pr-1 py-1 bg-base-200 flex items-center gap-2"
            >
              <span
                :if={lab.color && lab.color != ""}
                class="size-3 rounded-full border border-base-content/20"
                style={"background: #{lab.color}"}
              />
              <span class="text-sm">{lab.name}</span>
              <span
                :if={lab.subboards != []}
                class="text-[10px] opacity-60"
                title="Only applies to cards in these subboards"
              >
                {Enum.map_join(lab.subboards, ", ", & &1.name)}
              </span>
              <button
                :if={Kanban.can_manage?(@role)}
                type="button"
                phx-click="delete_label"
                phx-value-id={lab.id}
                data-confirm="Remove this label from the board?"
                class="btn btn-ghost btn-xs text-error"
                aria-label="Delete label"
              >
                <.icon name="hero-x-mark-micro" class="size-3" />
              </button>
            </li>
          </ul>

          <.form
            :if={Kanban.can_manage?(@role)}
            for={@label_form}
            id="board-label-form"
            phx-submit="create_label"
            class="flex flex-col gap-3"
          >
            <div class="flex items-end gap-2">
              <.input field={@label_form[:name]} type="text" label="New label name" required />
              <.button class="btn btn-primary">Add label</.button>
            </div>
            <.color_picker field={@label_form[:color]} label="Color (optional)" />

            <fieldset :if={@subboards != []} class="flex flex-col gap-1">
              <legend class="text-xs opacity-70 mb-1">
                Limit to subboards (optional — leave all unchecked for a board-wide label)
              </legend>
              <%!-- Hidden entry keeps the key present so unchecking all clears the scope. --%>
              <input type="hidden" name="label[subboard_ids][]" value="" />
              <label :for={sb <- @subboards} class="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  name="label[subboard_ids][]"
                  value={sb.id}
                  class="checkbox checkbox-sm"
                />
                {sb.name}
              </label>
            </fieldset>
          </.form>
        </section>

        <section>
          <h2 class="text-lg font-semibold mb-2">Subboards</h2>
          <p class="text-sm opacity-70 mb-3">
            Subboards split the board into rows. The kanban view becomes a
            grid: subboards down the side, stages across the top. New cards
            land in the default row until you assign them to a subboard.
          </p>

          <ul class="flex flex-col gap-2 mb-4">
            <li :if={@subboards == []} class="text-sm opacity-60 py-2">
              No subboards yet — everything sits in the default row.
            </li>
            <li
              :for={sb <- @subboards}
              id={"subboard-#{sb.id}"}
              class="border border-base-300 rounded-box p-2 bg-base-200 flex items-center gap-3"
            >
              <.icon name="hero-bars-3-bottom-left-micro" class="size-4 opacity-60 shrink-0" />
              <span class="flex-1 font-medium truncate">{sb.name}</span>
              <button
                :if={Kanban.can_manage?(@role)}
                type="button"
                phx-click="delete_subboard"
                phx-value-id={sb.id}
                data-confirm="Delete this subboard? Cards in it fall back to the default row."
                class="btn btn-ghost btn-xs text-error"
                title="Delete"
              >
                <.icon name="hero-trash-micro" class="size-4" />
              </button>
            </li>
          </ul>

          <.form
            :if={Kanban.can_manage?(@role)}
            for={@subboard_form}
            id="subboard-form"
            phx-submit="create_subboard"
            class="flex items-end gap-2"
          >
            <.input field={@subboard_form[:name]} type="text" label="New subboard name" required />
            <.button class="btn btn-primary">Add</.button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
