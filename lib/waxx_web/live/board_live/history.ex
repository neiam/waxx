defmodule WaxxWeb.BoardLive.History do
  use WaxxWeb, :live_view

  alias Waxx.Kanban

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case Kanban.get_board_for_user(id, user) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Board not found.")
         |> push_navigate(to: ~p"/boards")}

      board ->
        if connected?(socket), do: Kanban.subscribe(board.id)

        {:ok,
         socket
         |> assign(:page_title, "#{board.name} · history")
         |> assign(:board, board)
         |> assign(:activities, Kanban.list_activities(board))}
    end
  end

  @impl true
  def handle_info({:cards_changed, _}, socket) do
    {:noreply, assign(socket, :activities, Kanban.list_activities(socket.assigns.board))}
  end

  def handle_info({:workflow_changed, _}, socket) do
    {:noreply, assign(socket, :activities, Kanban.list_activities(socket.assigns.board))}
  end

  ## ---- template ----------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto py-6 space-y-6">
        <header>
          <.link navigate={~p"/boards/#{@board.id}"} class="text-xs opacity-60 hover:underline">
            ← Back to board
          </.link>
          <h1 class="text-2xl font-bold mt-1">
            {@board.name} <span class="text-base opacity-60">· history</span>
          </h1>
          <p class="text-xs opacity-60 mt-1">
            Last {length(@activities)} events, newest first.
          </p>
        </header>

        <ol :if={@activities != []} class="flex flex-col gap-2">
          <li
            :for={a <- @activities}
            id={"activity-#{a.id}"}
            class="border border-base-300 rounded-box p-3 bg-base-200 flex items-start gap-3"
          >
            <.icon name={action_icon(a.action)} class="size-4 mt-1 text-accent shrink-0" />
            <div class="flex-1 min-w-0">
              <p class="text-sm">
                <span class="font-medium">{actor_label(a.actor)}</span>
                {action_text(a)}
              </p>
              <p class="text-xs opacity-60 mt-1">
                {Calendar.strftime(a.inserted_at, "%Y-%m-%d %H:%M")} UTC
                · {relative(a.inserted_at)}
              </p>
            </div>
          </li>
        </ol>

        <div :if={@activities == []} class="text-center text-sm opacity-60 py-12">
          No activity yet. Create or move some cards to populate the log.
        </div>
      </div>
    </Layouts.app>
    """
  end

  ## ---- presentation helpers ---------------------------------------------

  defp actor_label(nil), do: "system"

  defp actor_label(%{display_name: name}) when is_binary(name) and name != "", do: name

  defp actor_label(%{email: email}) when is_binary(email),
    do: hd(String.split(email, "@"))

  defp actor_label(_), do: "someone"

  defp action_icon("card_created"), do: "hero-plus-circle-micro"
  defp action_icon("card_moved"), do: "hero-arrow-right-circle-micro"
  defp action_icon("card_updated"), do: "hero-pencil-square-micro"
  defp action_icon("card_deleted"), do: "hero-trash-micro"
  defp action_icon("card_assigned"), do: "hero-user-plus-micro"
  defp action_icon("card_unassigned"), do: "hero-user-minus-micro"
  defp action_icon("card_label_added"), do: "hero-tag-micro"
  defp action_icon("card_label_removed"), do: "hero-tag-micro"
  defp action_icon("card_field_set"), do: "hero-document-text-micro"
  defp action_icon("card_field_cleared"), do: "hero-document-text-micro"
  defp action_icon("card_subboard_changed"), do: "hero-bars-3-bottom-left-micro"
  defp action_icon(_), do: "hero-clock-micro"

  # Renders a human-readable sentence from an activity row. Pulls strings
  # out of the captured `meta` rather than chasing the referenced rows
  # (which may have been deleted or renamed since).
  defp action_text(%{action: "card_created", meta: m}),
    do: "created card \"#{m["title"]}\""

  defp action_text(%{action: "card_moved", meta: m}),
    do: "moved \"#{m["title"]}\" from #{m["from_stage"]} → #{m["to_stage"]}"

  defp action_text(%{action: "card_updated", meta: m}) do
    fields = m["changes"] |> List.wrap() |> Enum.join(", ")
    "edited #{fields} on \"#{m["title"]}\""
  end

  defp action_text(%{action: "card_deleted", meta: m}),
    do: "deleted card \"#{m["title"]}\""

  defp action_text(%{action: "card_assigned", meta: m}),
    do: "assigned #{m["user_email"]}"

  defp action_text(%{action: "card_unassigned", meta: m}),
    do: "unassigned #{m["user_email"]}"

  defp action_text(%{action: "card_label_added", meta: m}),
    do: "added label \"#{m["label_name"]}\""

  defp action_text(%{action: "card_label_removed", meta: m}),
    do: "removed label \"#{m["label_name"]}\""

  defp action_text(%{action: "card_field_set", meta: m}),
    do: "set field \"#{m["field_name"]}\" to \"#{m["value"]}\""

  defp action_text(%{action: "card_field_cleared", meta: m}),
    do: "cleared field \"#{m["field_name"]}\""

  defp action_text(%{action: "card_subboard_changed", meta: m}) do
    name = m["subboard_name"] || "Default"
    "moved \"#{m["title"]}\" into the #{name} row"
  end

  defp action_text(%{action: action}), do: action

  defp relative(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 86_400 * 7 -> "#{div(diff, 86_400)}d ago"
      true -> "#{div(diff, 86_400 * 7)}w ago"
    end
  end
end
