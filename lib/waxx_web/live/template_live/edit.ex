defmodule WaxxWeb.TemplateLive.Edit do
  use WaxxWeb, :live_view

  alias Waxx.Workflows

  # Layout constants used by both the HEEx template and the SVG arrow paths.
  # The graph flows top-to-bottom: stages stack vertically, forward arrows
  # run down the centerline, backward arrows loop out to the right.
  @node_w 220
  @node_h 64
  @node_gap 56
  @node_left 20
  @node_top 20
  # Extra horizontal room to the right of the node column so backward-loop
  # arrows have somewhere to bulge into.
  @loop_pad 140

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    template = Workflows.get_template!(id)

    {:ok,
     socket
     |> assign(:page_title, template.name)
     |> assign(:template, template)
     |> assign(:active_tab, :workflow)
     |> assign(:stage_form, to_form(%{"name" => "", "color" => ""}, as: "stage"))
     |> assign(:label_form, to_form(%{"name" => "", "color" => ""}, as: "label"))
     |> assign(:field_form, blank_field_form())
     |> assign(:selected_source_id, nil)
     |> assign(:editing_stage_id, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :active_tab, parse_tab(params["tab"]))}
  end

  defp parse_tab("labels"), do: :labels
  defp parse_tab("fields"), do: :fields
  defp parse_tab(_), do: :workflow

  defp blank_field_form do
    to_form(
      %{
        "name" => "",
        "kind" => "text",
        "options" => "",
        "show_on_card" => "false"
      },
      as: "field"
    )
  end

  ## --- stage events --------------------------------------------------------

  @impl true
  def handle_event("add_stage", %{"stage" => params}, socket) do
    case Workflows.add_stage(socket.assigns.template, params) do
      {:ok, _stage} ->
        {:noreply,
         socket
         |> refresh_template()
         |> assign(:stage_form, to_form(%{"name" => "", "color" => ""}, as: "stage"))
         |> put_flash(:info, "Stage added.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add stage.")}
    end
  end

  def handle_event("edit_stage", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_stage_id, id)}
  end

  def handle_event("cancel_stage_edit", _, socket) do
    {:noreply, assign(socket, :editing_stage_id, nil)}
  end

  def handle_event("rename_stage", %{"id" => id, "name" => new_name}, socket) do
    stage = Enum.find(socket.assigns.template.stages, &(&1.id == id))
    new_name = (new_name || "") |> String.trim()

    cond do
      is_nil(stage) ->
        {:noreply, assign(socket, :editing_stage_id, nil)}

      new_name == "" ->
        {:noreply, put_flash(socket, :error, "Stage name can't be blank.")}

      new_name == stage.name ->
        # No-op: avoid an extra propagation pass.
        {:noreply, assign(socket, :editing_stage_id, nil)}

      true ->
        case Workflows.update_stage(stage, %{"name" => new_name}) do
          {:ok, _} ->
            {:noreply,
             socket
             |> refresh_template()
             |> assign(:editing_stage_id, nil)
             |> put_flash(:info, "Renamed.")}

          {:error, cs} ->
            {:noreply, put_flash(socket, :error, "Could not rename: #{format_errors(cs)}")}
        end
    end
  end

  def handle_event("delete_stage", %{"id" => id}, socket) do
    stage = Enum.find(socket.assigns.template.stages, &(&1.id == id))

    if stage do
      {:ok, _} = Workflows.delete_stage(stage)

      # If the deleted stage was the selected source, clear the selection.
      selected =
        if socket.assigns.selected_source_id == stage.id,
          do: nil,
          else: socket.assigns.selected_source_id

      {:noreply, socket |> refresh_template() |> assign(:selected_source_id, selected)}
    else
      {:noreply, socket}
    end
  end

  ## --- transition / graph events ------------------------------------------

  # Single click on a stage node:
  #   * with no source selected → select it
  #   * with the same source selected → deselect
  #   * with another source selected → create source→this transition
  def handle_event("select_source", %{"id" => raw_id}, socket) do
    id = raw_id
    template = socket.assigns.template

    case socket.assigns.selected_source_id do
      nil ->
        {:noreply, assign(socket, :selected_source_id, id)}

      ^id ->
        {:noreply, assign(socket, :selected_source_id, nil)}

      from_id ->
        case Workflows.add_transition(template, from_id, id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> refresh_template()
             |> assign(:selected_source_id, nil)
             |> put_flash(:info, "Transition added.")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply,
             socket
             |> assign(:selected_source_id, nil)
             |> put_flash(:error, "Could not add transition: #{format_errors(cs)}")}
        end
    end
  end

  def handle_event("clear_selection", _, socket) do
    {:noreply, assign(socket, :selected_source_id, nil)}
  end

  def handle_event("delete_transition", %{"id" => id}, socket) do
    transition =
      Enum.find(socket.assigns.template.transitions, &(&1.id == id))

    if transition do
      {:ok, _} = Workflows.delete_transition(transition)
      {:noreply, refresh_template(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_label", %{"label" => params}, socket) do
    case Workflows.add_label(socket.assigns.template, params) do
      {:ok, _label} ->
        {:noreply,
         socket
         |> refresh_template()
         |> assign(:label_form, to_form(%{"name" => "", "color" => ""}, as: "label"))
         |> put_flash(:info, "Label added.")}

      {:error, cs} ->
        {:noreply, put_flash(socket, :error, "Could not add label: #{format_errors(cs)}")}
    end
  end

  def handle_event("delete_label", %{"id" => id}, socket) do
    label = Enum.find(socket.assigns.template.labels, &(&1.id == id))

    if label do
      {:ok, _} = Workflows.delete_label(label)
      {:noreply, refresh_template(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_field", %{"field" => params}, socket) do
    attrs = %{
      "name" => params["name"],
      "kind" => params["kind"],
      "show_on_card" => params["show_on_card"] == "true",
      "options" => parse_options(params["options"])
    }

    case Workflows.add_field(socket.assigns.template, attrs) do
      {:ok, _f} ->
        {:noreply,
         socket
         |> refresh_template()
         |> assign(:field_form, blank_field_form())
         |> put_flash(:info, "Field added.")}

      {:error, cs} ->
        {:noreply, put_flash(socket, :error, "Could not add field: #{format_errors(cs)}")}
    end
  end

  def handle_event("delete_field", %{"id" => id}, socket) do
    field = Enum.find(socket.assigns.template.fields, &(&1.id == id))

    if field do
      {:ok, _} = Workflows.delete_field(field)
      {:noreply, refresh_template(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("toggle_field_show", %{"id" => id}, socket) do
    field = Enum.find(socket.assigns.template.fields, &(&1.id == id))

    if field do
      case Workflows.update_field(field, %{"show_on_card" => not field.show_on_card}) do
        {:ok, _} -> {:noreply, refresh_template(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update field.")}
      end
    else
      {:noreply, socket}
    end
  end

  defp parse_options(nil), do: []
  defp parse_options(""), do: []

  defp parse_options(s) when is_binary(s) do
    s
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp refresh_template(socket) do
    assign(socket, :template, Workflows.get_template!(socket.assigns.template.id))
  end

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map_join(", ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  ## --- graph layout helpers (used in HEEx) --------------------------------

  defp stage_index(stages, stage_id), do: Enum.find_index(stages, &(&1.id == stage_id))

  defp node_top(idx), do: idx * (@node_h + @node_gap) + @node_top
  defp node_bottom(idx), do: node_top(idx) + @node_h
  defp node_center_x, do: @node_left + div(@node_w, 2)
  defp node_right, do: @node_left + @node_w
  defp node_middle_y(idx), do: node_top(idx) + div(@node_h, 2)

  defp canvas_width, do: @node_left + @node_w + @loop_pad

  defp canvas_height(stages),
    do: max(length(stages) * (@node_h + @node_gap) + 2 * @node_top, 200)

  # Returns SVG path string for a curved arrow between two stage indexes.
  # Forward arrows run down the column centerline; skip-ahead arrows bow
  # right so they're visibly distinct from adjacent ones. Backward arrows
  # loop out to the right of the column.
  defp arrow_path(sidx, tidx) when sidx < tidx do
    sx = node_center_x()
    sy = node_bottom(sidx)
    tx = node_center_x()
    ty = node_top(tidx)

    skip = tidx - sidx
    bow = if skip == 1, do: 0, else: min(@loop_pad - 20, skip * 22)
    cx1 = sx + bow
    cx2 = tx + bow

    "M #{sx} #{sy} C #{cx1} #{sy + 20}, #{cx2} #{ty - 20}, #{tx} #{ty}"
  end

  defp arrow_path(sidx, tidx) when sidx > tidx do
    sx = node_right()
    sy = node_middle_y(sidx)
    tx = node_right()
    ty = node_middle_y(tidx)
    loop_x = sx + @loop_pad - 40

    "M #{sx} #{sy} C #{loop_x} #{sy}, #{loop_x} #{ty}, #{tx} #{ty}"
  end

  ## --- template ------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:node_w, @node_w)
      |> assign(:node_h, @node_h)
      |> assign(:node_left, @node_left)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto py-6 space-y-6">
        <header class="flex items-center justify-between">
          <div>
            <.link navigate={~p"/workflow-templates"} class="text-xs opacity-60 hover:underline">
              ← All templates
            </.link>
            <h1 class="text-2xl font-bold mt-1">{@template.name}</h1>
            <p :if={@template.description} class="text-sm opacity-70">
              {@template.description}
            </p>
          </div>
        </header>

        <div role="tablist" class="tabs tabs-bordered">
          <.link
            patch={~p"/workflow-templates/#{@template.id}"}
            role="tab"
            class={["tab", @active_tab == :workflow && "tab-active"]}
          >
            <.icon name="hero-arrows-right-left-micro" class="size-4 mr-1" /> Workflow
            <span class="badge badge-ghost badge-xs ml-2">
              {length(@template.stages)}
            </span>
          </.link>
          <.link
            patch={~p"/workflow-templates/#{@template.id}?tab=labels"}
            role="tab"
            class={["tab", @active_tab == :labels && "tab-active"]}
          >
            <.icon name="hero-tag-micro" class="size-4 mr-1" /> Labels
            <span class="badge badge-ghost badge-xs ml-2">
              {length(@template.labels)}
            </span>
          </.link>
          <.link
            patch={~p"/workflow-templates/#{@template.id}?tab=fields"}
            role="tab"
            class={["tab", @active_tab == :fields && "tab-active"]}
          >
            <.icon name="hero-document-text-micro" class="size-4 mr-1" /> Fields
            <span class="badge badge-ghost badge-xs ml-2">
              {length(@template.fields)}
            </span>
          </.link>
        </div>

        <section :if={@active_tab == :workflow}>
          <div class="flex items-baseline justify-between mb-2">
            <h2 class="text-lg font-semibold">Workflow graph</h2>
            <p class="text-xs opacity-70">
              Click a stage to pick the source, then click another stage to draw a transition.
              Click an arrow to remove it.
            </p>
          </div>

          <%= if @template.stages == [] do %>
            <div class="border border-base-300 border-dashed rounded-box p-8 bg-base-200 text-center text-sm opacity-60">
              Add a stage below to start building the graph.
            </div>
          <% else %>
            <div class="border border-base-300 rounded-box bg-base-200 p-4">
              <div
                class="relative mx-auto"
                style={"width: #{canvas_width()}px; height: #{canvas_height(@template.stages)}px;"}
              >
                <svg
                  class="absolute inset-0 pointer-events-none text-base-content/60"
                  width={canvas_width()}
                  height={canvas_height(@template.stages)}
                >
                  <defs>
                    <marker
                      id="arrowhead"
                      markerWidth="10"
                      markerHeight="10"
                      refX="9"
                      refY="3"
                      orient="auto"
                      markerUnits="strokeWidth"
                    >
                      <path d="M0,0 L0,6 L9,3 z" fill="currentColor" />
                    </marker>
                  </defs>

                  <g>
                    <%= for t <- @template.transitions do %>
                      <% sidx = stage_index(@template.stages, t.from_stage_id) %>
                      <% tidx = stage_index(@template.stages, t.to_stage_id) %>
                      <%= if sidx && tidx do %>
                        <path
                          id={"arrow-#{t.id}"}
                          d={arrow_path(sidx, tidx)}
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          marker-end="url(#arrowhead)"
                          style="pointer-events: stroke; cursor: pointer;"
                          phx-click="delete_transition"
                          phx-value-id={t.id}
                          data-confirm="Remove this transition?"
                          class="hover:text-error transition-colors"
                        >
                          <title>
                            {transition_label(t)} — click to remove
                          </title>
                        </path>
                      <% end %>
                    <% end %>
                  </g>
                </svg>

                <%= for {stage, idx} <- Enum.with_index(@template.stages) do %>
                  <button
                    type="button"
                    id={"stage-node-#{stage.id}"}
                    phx-click="select_source"
                    phx-value-id={stage.id}
                    class={[
                      "absolute z-20 flex items-center justify-center gap-2 rounded-box bg-base-100 shadow-sm",
                      "border-2 transition-colors",
                      if(@selected_source_id == stage.id,
                        do: "border-primary ring-2 ring-primary",
                        else: "border-base-300 hover:border-primary"
                      )
                    ]}
                    style={"left: #{@node_left}px; top: #{node_top(idx)}px; width: #{@node_w}px; height: #{@node_h}px;"}
                  >
                    <span
                      :if={stage.color && stage.color != ""}
                      class="size-3 rounded-full border border-base-content/20 shrink-0"
                      style={"background: #{stage.color}"}
                    />
                    <span class="font-semibold text-sm text-center px-2 truncate">
                      {stage.name}
                    </span>
                  </button>
                <% end %>
              </div>
            </div>

            <div class="flex items-center justify-between mt-2 min-h-[1.5rem]">
              <p :if={@selected_source_id} class="text-xs text-primary">
                <.icon name="hero-cursor-arrow-rays-micro" class="size-3" />
                Source selected. Click another stage to connect, or <button
                  type="button"
                  phx-click="clear_selection"
                  class="underline hover:text-error"
                >cancel</button>.
              </p>
              <p class="text-xs opacity-60 ml-auto">
                {length(@template.stages)} stages · {length(@template.transitions)} transitions
              </p>
            </div>
          <% end %>
        </section>

        <section :if={@active_tab == :workflow}>
          <h2 class="text-lg font-semibold mb-2">Stages</h2>
          <p class="text-sm opacity-70 mb-3">
            Stages render as nodes in the graph above, in this order.
          </p>

          <ul class="flex flex-col gap-2 mb-3">
            <li
              :for={stage <- @template.stages}
              id={"stage-#{stage.id}"}
              class="border border-base-300 rounded-box p-2 bg-base-200 flex items-center gap-3"
            >
              <span class="font-mono text-xs opacity-60 w-6 text-right">{stage.position}</span>
              <span
                :if={stage.color && stage.color != ""}
                class="size-3 rounded-full border border-base-content/20"
                style={"background: #{stage.color}"}
              />
              <%= if @editing_stage_id == stage.id do %>
                <.form
                  for={%{}}
                  as={:stage}
                  phx-submit="rename_stage"
                  phx-value-id={stage.id}
                  class="flex-1 flex items-center gap-1"
                >
                  <input
                    type="text"
                    name="name"
                    value={stage.name}
                    required
                    phx-mounted={JS.focus()}
                    phx-key="escape"
                    phx-keydown="cancel_stage_edit"
                    class="input input-xs input-bordered flex-1"
                  />
                  <button type="submit" class="btn btn-ghost btn-xs" title="Save">
                    <.icon name="hero-check-micro" class="size-4" />
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_stage_edit"
                    class="btn btn-ghost btn-xs"
                    title="Cancel"
                  >
                    <.icon name="hero-x-mark-micro" class="size-4" />
                  </button>
                </.form>
              <% else %>
                <span class="flex-1">{stage.name}</span>
                <button
                  type="button"
                  phx-click="edit_stage"
                  phx-value-id={stage.id}
                  class="btn btn-ghost btn-xs"
                  title="Rename"
                >
                  <.icon name="hero-pencil-square-micro" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="delete_stage"
                  phx-value-id={stage.id}
                  data-confirm="Delete this stage? All transitions touching it will be removed too."
                  class="btn btn-ghost btn-xs text-error"
                >
                  <.icon name="hero-trash-micro" class="size-4" />
                </button>
              <% end %>
            </li>
          </ul>

          <.form
            for={@stage_form}
            id="stage-form"
            phx-submit="add_stage"
            class="flex flex-col gap-3"
          >
            <div class="flex items-end gap-2">
              <.input field={@stage_form[:name]} type="text" label="Stage name" required />
              <.button class="btn btn-primary">Add stage</.button>
            </div>
            <.color_picker field={@stage_form[:color]} label="Color (optional)" />
          </.form>
        </section>

        <section :if={@active_tab == :labels}>
          <h2 class="text-lg font-semibold mb-2">Labels</h2>
          <p class="text-sm opacity-70 mb-3">
            Labels are cloned to every board created from this template. Adding
            or removing a label here propagates to existing boards — a board
            won't lose a label that's still attached to a card.
          </p>

          <ul class="flex flex-wrap gap-2 mb-3">
            <li
              :for={lab <- @template.labels}
              id={"label-#{lab.id}"}
              class="border border-base-300 rounded-box pl-2 pr-1 py-1 bg-base-200 flex items-center gap-2"
            >
              <span
                :if={lab.color && lab.color != ""}
                class="size-3 rounded-full border border-base-content/20"
                style={"background: #{lab.color}"}
              />
              <span class="text-sm">{lab.name}</span>
              <button
                type="button"
                phx-click="delete_label"
                phx-value-id={lab.id}
                data-confirm="Remove this label?"
                class="btn btn-ghost btn-xs text-error"
                aria-label="Delete label"
              >
                <.icon name="hero-x-mark-micro" class="size-3" />
              </button>
            </li>
            <li
              :if={@template.labels == []}
              class="text-sm opacity-60"
            >
              No labels yet.
            </li>
          </ul>

          <.form
            for={@label_form}
            id="label-form"
            phx-submit="add_label"
            class="flex flex-col gap-3"
          >
            <div class="flex items-end gap-2">
              <.input field={@label_form[:name]} type="text" label="Label name" required />
              <.button class="btn btn-primary">Add label</.button>
            </div>
            <.color_picker field={@label_form[:color]} label="Color (optional)" />
          </.form>
        </section>

        <section :if={@active_tab == :fields}>
          <h2 class="text-lg font-semibold mb-2">Custom fields</h2>
          <p class="text-sm opacity-70 mb-3">
            Custom info attached to each card — due dates, locations, anything
            you want. Toggle "show on card" to surface a field as a small chip
            on the kanban tile.
          </p>

          <ul class="flex flex-col gap-2 mb-3">
            <li
              :for={f <- @template.fields}
              id={"field-#{f.id}"}
              class="border border-base-300 rounded-box p-2 bg-base-200 flex items-center gap-3"
            >
              <span class="badge badge-ghost badge-sm font-mono">{f.kind}</span>
              <span class="font-medium">{f.name}</span>
              <span
                :if={f.kind == "select" and f.options not in [nil, []]}
                class="text-xs opacity-70 truncate"
              >
                {Enum.join(f.options, ", ")}
              </span>
              <span class="flex-1" />
              <label class="label cursor-pointer gap-2">
                <span class="label-text text-xs">Show on card</span>
                <input
                  type="checkbox"
                  class="checkbox checkbox-sm"
                  checked={f.show_on_card}
                  phx-click="toggle_field_show"
                  phx-value-id={f.id}
                />
              </label>
              <button
                type="button"
                phx-click="delete_field"
                phx-value-id={f.id}
                data-confirm="Delete this field? Existing values on cards will be kept on boards that still use it."
                class="btn btn-ghost btn-xs text-error"
                aria-label="Delete field"
              >
                <.icon name="hero-trash-micro" class="size-4" />
              </button>
            </li>
            <li :if={@template.fields == []} class="text-sm opacity-60">
              No custom fields yet.
            </li>
          </ul>

          <.form
            for={@field_form}
            id="field-form"
            phx-submit="add_field"
            class="grid grid-cols-1 sm:grid-cols-4 gap-2 items-end"
          >
            <.input field={@field_form[:name]} type="text" label="Field name" required />
            <.input
              field={@field_form[:kind]}
              type="select"
              label="Type"
              options={[
                {"Text", "text"},
                {"Date", "date"},
                {"Date + time", "datetime"},
                {"Select (pick one)", "select"}
              ]}
            />
            <.input
              field={@field_form[:options]}
              type="text"
              label="Options (select only, comma-separated)"
            />
            <.button class="btn btn-primary">Add field</.button>
            <label class="label cursor-pointer gap-2 sm:col-span-4">
              <input
                type="checkbox"
                name="field[show_on_card]"
                value="true"
                class="checkbox checkbox-sm"
              />
              <span class="label-text">Show on card</span>
            </label>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp transition_label(%{label: nil, from_stage: f, to_stage: t}), do: "#{f.name} → #{t.name}"

  defp transition_label(%{label: label, from_stage: f, to_stage: t}),
    do: "#{f.name} → #{t.name} (#{label})"
end
