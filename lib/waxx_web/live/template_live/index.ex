defmodule WaxxWeb.TemplateLive.Index do
  use WaxxWeb, :live_view

  alias Waxx.Workflows
  alias Waxx.Workflows.Template

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Workflow templates")
     |> stream(:templates, Workflows.list_templates())
     |> assign(:form, to_form(Workflows.change_template(%Template{})))
     |> assign(:creating, false)}
  end

  @impl true
  def handle_event("toggle_create", _, socket) do
    {:noreply, assign(socket, :creating, !socket.assigns.creating)}
  end

  def handle_event("validate", %{"template" => params}, socket) do
    cs =
      %Template{}
      |> Workflows.change_template(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(cs))}
  end

  def handle_event("save", %{"template" => params}, socket) do
    case Workflows.create_template(socket.assigns.current_scope.user, params) do
      {:ok, template} ->
        template = Workflows.get_template!(template.id)

        {:noreply,
         socket
         |> put_flash(:info, "Template created.")
         |> assign(:creating, false)
         |> assign(:form, to_form(Workflows.change_template(%Template{})))
         |> stream_insert(:templates, template, at: 0)}

      {:error, cs} ->
        {:noreply, assign(socket, :form, to_form(cs))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    template = Workflows.get_template!(id)
    {:ok, _} = Workflows.delete_template(template)
    {:noreply, stream_delete(socket, :templates, template)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto py-6">
        <header class="flex items-center justify-between mb-6">
          <div>
            <h1 class="text-2xl font-bold">Workflow templates</h1>
            <p class="text-sm opacity-70">
              Reusable stage graphs. Apply one when creating a board, then
              tweak the board's copy independently.
            </p>
          </div>
          <button
            id="btn-toggle-create"
            type="button"
            phx-click="toggle_create"
            class="btn btn-primary btn-sm"
          >
            <.icon name="hero-plus-micro" class="size-4" />
            {if @creating, do: "Cancel", else: "New template"}
          </button>
        </header>

        <div :if={@creating} class="border border-base-300 rounded-box p-4 bg-base-200 mb-6">
          <.form for={@form} id="template-form" phx-submit="save" phx-change="validate">
            <.input field={@form[:name]} type="text" label="Name" required />
            <.input field={@form[:description]} type="text" label="Description (optional)" />
            <.button class="btn btn-primary mt-2">Create template</.button>
          </.form>
        </div>

        <ul id="templates" phx-update="stream" class="flex flex-col gap-2">
          <li id="templates-empty" class="hidden only:block text-center text-sm opacity-60 py-8">
            No templates yet. Create one to get started.
          </li>
          <li
            :for={{dom_id, template} <- @streams.templates}
            id={dom_id}
            class="border border-base-300 rounded-box p-3 bg-base-200 flex items-center gap-3"
          >
            <div class="flex-1 min-w-0">
              <.link
                navigate={~p"/workflow-templates/#{template.id}"}
                class="font-semibold hover:underline"
              >
                {template.name}
              </.link>
              <p :if={template.description} class="text-sm opacity-70 mt-0.5 truncate">
                {template.description}
              </p>
              <p class="text-xs opacity-60 mt-1">
                {length(template.stages)} stages, {length(template.transitions)} transitions
              </p>
            </div>
            <button
              type="button"
              phx-click="delete"
              phx-value-id={template.id}
              data-confirm="Delete this template?"
              class="btn btn-ghost btn-xs text-error"
              title="Delete"
            >
              <.icon name="hero-trash-micro" class="size-4" />
            </button>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
