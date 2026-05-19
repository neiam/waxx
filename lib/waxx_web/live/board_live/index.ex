defmodule WaxxWeb.BoardLive.Index do
  use WaxxWeb, :live_view

  alias Waxx.Kanban
  alias Waxx.Workflows

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Boards")
     |> assign(:boards, Kanban.list_boards_for(user))
     |> assign(:templates, Workflows.list_templates())
     |> assign(:form, to_form(%{"name" => "", "template_id" => ""}, as: "board"))
     |> assign(:creating, false)}
  end

  @impl true
  def handle_event("toggle_create", _, socket) do
    {:noreply, assign(socket, :creating, !socket.assigns.creating)}
  end

  def handle_event("create", %{"board" => params}, socket) do
    user = socket.assigns.current_scope.user
    template_id = params["template_id"]

    with template_id when is_binary(template_id) and template_id != "" <- template_id,
         template when not is_nil(template) <-
           Workflows.get_template(template_id),
         {:ok, board} <-
           Kanban.create_board_from_template(user, template, %{
             "name" => params["name"],
             "description" => params["description"]
           }) do
      {:noreply,
       socket
       |> put_flash(:info, "Board created.")
       |> push_navigate(to: ~p"/boards/#{board.id}")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Pick a template and give the board a name.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto py-6">
        <header class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold">Boards</h1>
            <p class="text-sm opacity-70">Kanban boards you can see.</p>
          </div>
          <button
            id="btn-toggle-create-board"
            type="button"
            phx-click="toggle_create"
            class="btn btn-primary btn-sm"
            disabled={@templates == []}
          >
            <.icon name="hero-plus-micro" class="size-4" />
            {if @creating, do: "Cancel", else: "New board"}
          </button>
        </header>

        <div :if={@templates == []} class="alert alert-warning mb-4">
          You need a
          <.link navigate={~p"/workflow-templates"} class="underline">workflow template</.link>
          before you can create a board.
        </div>

        <div :if={@creating} class="border border-base-300 rounded-box p-4 bg-base-200 mb-6">
          <.form for={@form} id="board-form" phx-submit="create">
            <.input field={@form[:name]} type="text" label="Board name" required />
            <.input
              field={@form[:description]}
              type="text"
              label="Description (optional)"
            />
            <.input
              field={@form[:template_id]}
              type="select"
              label="Workflow template"
              options={template_options(@templates)}
              required
            />
            <.button class="btn btn-primary mt-2">Create board</.button>
          </.form>
        </div>

        <ul class="flex flex-col gap-2">
          <li :if={@boards == []} class="text-center text-sm opacity-60 py-8">
            You're not a member of any boards yet.
          </li>
          <li
            :for={board <- @boards}
            id={"board-#{board.id}"}
            class="border border-base-300 rounded-box p-3 bg-base-200"
          >
            <.link navigate={~p"/boards/#{board.id}"} class="font-semibold hover:underline">
              {board.name}
            </.link>
            <p :if={board.description} class="text-sm opacity-70 mt-0.5">
              {board.description}
            </p>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  defp template_options(templates) do
    [{"Choose a template…", ""}] ++
      Enum.map(templates, fn t -> {t.name, t.id} end)
  end
end
