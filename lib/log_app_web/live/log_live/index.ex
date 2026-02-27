defmodule LogAppWeb.LogLive.Index do
  use LogAppWeb, :live_view

  alias LogApp.Logs

  # ---------------------------------------------------------------------------
  # Lifecycle
  # ---------------------------------------------------------------------------

  def mount(_params, _session, socket) do
    connected = connected?(socket)

    if connected do
      LogAppWeb.Endpoint.subscribe("logs:updates")
    end

    logs = Logs.list_logs()
    stats = Logs.count_logs_by_level()
    workflow_ids = Logs.list_workflow_ids()
    all_levels = MapSet.new(["error", "warning", "info", "debug"])

    socket =
      socket
      |> assign(:logs, logs)
      |> assign(:stats, stats)
      |> assign(:workflow_ids, workflow_ids)
      |> assign(:level_filters, all_levels)
      |> assign(:workflow_filter, nil)
      |> assign(:selected_log, nil)
      |> assign(:paused, false)
      |> assign(:connected, connected)
      |> stream(:filtered_logs, logs, dom_id: &"log-#{&1.id}")

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # PubSub handler
  # ---------------------------------------------------------------------------

  def handle_info(%{"event" => "log_created", "payload" => payload}, socket) do
    new_log = %{
      id: payload["id"],
      level: payload["level"],
      workflow_id: payload["workflow_id"],
      message: payload["message"],
      inserted_at: payload["inserted_at"]
    }

    # Always update the full log list (capped at 1000) and stats
    logs = Enum.take([new_log | socket.assigns.logs], 1000)
    stats = Map.update!(socket.assigns.stats, new_log.level, &(&1 + 1))

    # Track new workflow_ids
    workflow_ids =
      if new_log.workflow_id in socket.assigns.workflow_ids do
        socket.assigns.workflow_ids
      else
        [new_log.workflow_id | socket.assigns.workflow_ids]
      end

    socket =
      socket
      |> assign(:logs, logs)
      |> assign(:stats, stats)
      |> assign(:workflow_ids, workflow_ids)

    # Conditionally stream if not paused and matches filters
    socket =
      if not socket.assigns.paused and matches_filters?(new_log, socket.assigns) do
        stream_insert(socket, :filtered_logs, new_log, at: 0)
      else
        socket
      end

    {:noreply, socket}
  end

  # Catch-all for other PubSub messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Event handlers
  # ---------------------------------------------------------------------------

  def handle_event("toggle_level", %{"level" => level}, socket) do
    filters = socket.assigns.level_filters

    new_filters =
      if MapSet.member?(filters, level) do
        MapSet.delete(filters, level)
      else
        MapSet.put(filters, level)
      end

    socket =
      socket
      |> assign(:level_filters, new_filters)
      |> reset_filtered_stream()

    {:noreply, socket}
  end

  def handle_event("filter_workflow", %{"workflow_id" => ""}, socket) do
    socket =
      socket
      |> assign(:workflow_filter, nil)
      |> reset_filtered_stream()

    {:noreply, socket}
  end

  def handle_event("filter_workflow", %{"workflow_id" => wf_id}, socket) do
    socket =
      socket
      |> assign(:workflow_filter, wf_id)
      |> reset_filtered_stream()

    {:noreply, socket}
  end

  def handle_event("select_log", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    log = Enum.find(socket.assigns.logs, &(&1.id == id))
    {:noreply, assign(socket, :selected_log, log)}
  end

  def handle_event("close_detail", _, socket) do
    {:noreply, assign(socket, :selected_log, nil)}
  end

  def handle_event("toggle_pause", _, socket) do
    new_paused = not socket.assigns.paused

    socket =
      if not new_paused do
        # Resuming: reset stream to show current filtered state
        socket
        |> assign(:paused, false)
        |> reset_filtered_stream()
      else
        assign(socket, :paused, true)
      end

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <%!-- Page Header --%>
      <.header>
        <span class="flex items-center gap-3">
          Log Dashboard <.connection_indicator connected={@connected} />
        </span>
        <:subtitle>
          Real-time log stream from ingress
        </:subtitle>
        <:actions>
          <.button phx-click="toggle_pause">
            <.icon name={if @paused, do: "hero-play", else: "hero-pause"} class="size-4 mr-1" />
            {if @paused, do: "Resume", else: "Pause"}
          </.button>
        </:actions>
      </.header>

      <%!-- Stats Bar --%>
      <.stats_bar stats={@stats} />

      <%!-- Filters Toolbar --%>
      <.filters_toolbar
        level_filters={@level_filters}
        workflow_ids={@workflow_ids}
        workflow_filter={@workflow_filter}
        paused={@paused}
      />

      <%!-- Log Table --%>
      <div class="overflow-x-auto rounded-box border border-base-300">
        <table class="table table-zebra table-sm">
          <thead>
            <tr>
              <th class="w-20">Level</th>
              <th class="w-32">Workflow</th>
              <th>Message</th>
              <th class="w-24">Time</th>
            </tr>
          </thead>
          <tbody id="log-stream" phx-update="stream">
            <tr
              :for={{dom_id, log} <- @streams.filtered_logs}
              id={dom_id}
              phx-click="select_log"
              phx-value-id={log.id}
              class="cursor-pointer hover:bg-base-200 transition-colors"
            >
              <td>
                <span class={level_badge_class(log.level)}>{log.level}</span>
              </td>
              <td>
                <span class="font-mono text-xs text-base-content/70">
                  {String.slice(to_string(log.workflow_id), 0, 8)}<span class="opacity-40">...</span>
                </span>
              </td>
              <td>
                <code class="text-xs text-base-content/80">
                  {format_message_preview(log.message)}
                </code>
              </td>
              <td>
                <span class="text-xs text-base-content/60 whitespace-nowrap">
                  {relative_time(log.inserted_at)}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Detail Modal --%>
      <.log_detail_modal :if={@selected_log} log={@selected_log} />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Function components
  # ---------------------------------------------------------------------------

  attr :stats, :map, required: true

  defp stats_bar(assigns) do
    ~H"""
    <div class="stats stats-horizontal shadow w-full bg-base-100">
      <div :for={level <- ["error", "warning", "info", "debug"]} class="stat">
        <div class="stat-title capitalize">{level}</div>
        <div class={"stat-value text-2xl #{level_stat_class(level)}"}>
          {Map.get(@stats, level, 0)}
        </div>
      </div>
    </div>
    """
  end

  attr :level_filters, :any, required: true
  attr :workflow_ids, :list, required: true
  attr :workflow_filter, :string, default: nil
  attr :paused, :boolean, required: true

  defp filters_toolbar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-4">
      <%!-- Level toggles --%>
      <div class="join">
        <button
          :for={level <- ["error", "warning", "info", "debug"]}
          phx-click="toggle_level"
          phx-value-level={level}
          class={[
            "join-item btn btn-sm capitalize",
            if(MapSet.member?(@level_filters, level),
              do: level_filter_active_class(level),
              else: "btn-ghost opacity-50"
            )
          ]}
        >
          {level}
        </button>
      </div>

      <%!-- Workflow filter --%>
      <form phx-change="filter_workflow" class="inline">
        <select
          class="select select-sm select-bordered w-64"
          name="workflow_id"
        >
          <option value="">All Workflows</option>
          <option
            :for={wf_id <- @workflow_ids}
            value={wf_id}
            selected={@workflow_filter == to_string(wf_id)}
          >
            {String.slice(to_string(wf_id), 0, 8)}...
          </option>
        </select>
      </form>

      <%!-- Paused indicator --%>
      <div :if={@paused} class="badge badge-warning gap-1">
        <.icon name="hero-pause" class="size-3" /> Paused
      </div>
    </div>
    """
  end

  attr :connected, :boolean, required: true

  defp connection_indicator(assigns) do
    ~H"""
    <span class="relative flex size-3" title={if @connected, do: "Connected", else: "Disconnected"}>
      <span
        :if={@connected}
        class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75"
      />
      <span class={[
        "relative inline-flex rounded-full size-3",
        if(@connected, do: "bg-success", else: "bg-error")
      ]} />
    </span>
    """
  end

  attr :log, :map, required: true

  defp log_detail_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-3xl">
        <button
          class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
          phx-click="close_detail"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
        <h3 class="font-bold text-lg flex items-center gap-2">
          <span class={level_badge_class(@log.level)}>{@log.level}</span> Log #{@log.id}
        </h3>
        <div class="py-4 space-y-3">
          <div>
            <span class="font-semibold text-sm text-base-content/70">Workflow ID</span>
            <p class="font-mono text-sm">{@log.workflow_id}</p>
          </div>
          <div>
            <span class="font-semibold text-sm text-base-content/70">Timestamp</span>
            <p class="text-sm">{@log.inserted_at} ({relative_time(@log.inserted_at)})</p>
          </div>
          <div>
            <span class="font-semibold text-sm text-base-content/70">Message</span>
            <pre class="mt-1 p-3 bg-base-200 rounded-box text-xs overflow-x-auto"><code>{format_message(@log.message)}</code></pre>
          </div>
        </div>
        <div class="modal-action">
          <button class="btn" phx-click="close_detail">Close</button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click="close_detail" />
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp matches_filters?(log, assigns) do
    level_match = MapSet.member?(assigns.level_filters, log.level)

    workflow_match =
      case assigns.workflow_filter do
        nil -> true
        wf_id -> to_string(log.workflow_id) == wf_id
      end

    level_match and workflow_match
  end

  defp reset_filtered_stream(socket) do
    filtered =
      socket.assigns.logs
      |> Enum.filter(&matches_filters?(&1, socket.assigns))

    stream(socket, :filtered_logs, filtered, dom_id: &"log-#{&1.id}", reset: true)
  end

  # Level badge classes (DaisyUI theme-aware)
  defp level_badge_class("error"), do: "badge badge-error badge-sm"
  defp level_badge_class("warning"), do: "badge badge-warning badge-sm"
  defp level_badge_class("info"), do: "badge badge-info badge-sm"
  defp level_badge_class("debug"), do: "badge badge-ghost badge-sm"
  defp level_badge_class(_), do: "badge badge-ghost badge-sm"

  # Level stat value colors
  defp level_stat_class("error"), do: "text-error"
  defp level_stat_class("warning"), do: "text-warning"
  defp level_stat_class("info"), do: "text-info"
  defp level_stat_class("debug"), do: "text-base-content/60"

  # Level filter button active colors
  defp level_filter_active_class("error"), do: "btn-error"
  defp level_filter_active_class("warning"), do: "btn-warning"
  defp level_filter_active_class("info"), do: "btn-info"
  defp level_filter_active_class("debug"), do: "btn-ghost btn-active"

  # Message formatting
  defp format_message(map) when is_map(map) do
    Jason.encode!(map, pretty: true)
  end

  defp format_message(other), do: inspect(other)

  defp format_message_preview(map) when is_map(map) do
    str = Jason.encode!(map)

    if byte_size(str) > 80 do
      String.slice(str, 0, 80) <> "..."
    else
      str
    end
  end

  defp format_message_preview(other), do: inspect(other)

  # Relative timestamps
  defp relative_time(nil), do: ""

  defp relative_time(timestamp) when is_binary(timestamp) do
    # Handle ISO 8601 strings from PubSub serialization
    timestamp_with_z =
      if String.ends_with?(timestamp, "Z"), do: timestamp, else: timestamp <> "Z"

    # Try ISO 8601 first, then naive format
    case DateTime.from_iso8601(timestamp_with_z) do
      {:ok, dt, _} ->
        relative_time(dt)

      _ ->
        case NaiveDateTime.from_iso8601(timestamp) do
          {:ok, ndt} -> ndt |> DateTime.from_naive!("Etc/UTC") |> relative_time()
          _ -> timestamp
        end
    end
  end

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp relative_time(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> relative_time()
  end

  defp relative_time(_), do: ""
end
