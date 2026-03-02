defmodule LogAppWeb.LogLive.Index do
  use LogAppWeb, :live_view

  alias LogApp.Logs

  def mount(_params, _session, socket) do
    connected = connected?(socket)

    if connected do
      LogAppWeb.Endpoint.subscribe("logs:updates")
    end

    logs = Logs.list_logs()
    stats = Logs.count_logs_by_level()
    workflow_ids = Logs.list_workflow_ids()
    level_filters = MapSet.new(["error", "warning", "info", "debug"])
    time_range = "all"

    filtered_logs =
      logs
      |> Enum.filter(fn log ->
        MapSet.member?(level_filters, log.level) and
          within_time_range?(log.inserted_at, time_range)
      end)

    socket =
      socket
      |> assign(:logs, logs)
      |> assign(:stats, stats)
      |> assign(:workflow_ids, workflow_ids)
      |> assign(:level_filters, level_filters)
      |> assign(:workflow_filter, nil)
      |> assign(:search_query, "")
      |> assign(:time_range, time_range)
      |> assign(:filtered_logs_count, length(filtered_logs))
      |> assign(:selected_log, nil)
      |> assign(:paused, false)
      |> assign(:connected, connected)
      |> stream(:filtered_logs, filtered_logs, dom_id: &"log-#{&1.id}")

    {:ok, socket}
  end

  def handle_info(%{"event" => "log_created", "payload" => payload}, socket) do
    new_log = %{
      id: payload["id"],
      level: payload["level"],
      workflow_id: payload["workflow_id"],
      message: payload["message"],
      inserted_at: payload["inserted_at"]
    }

    logs = Enum.take([new_log | socket.assigns.logs], 1000)
    stats = Map.update!(socket.assigns.stats, new_log.level, &(&1 + 1))

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

    socket =
      if not socket.assigns.paused and matches_filters?(new_log, socket.assigns) do
        socket
        |> stream_insert(:filtered_logs, new_log, at: 0)
        |> update(:filtered_logs_count, &(&1 + 1))
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  def handle_event("set_levels", %{"levels" => selected_levels}, socket) do
    allowed_levels = MapSet.new(["error", "warning", "info", "debug"])

    level_filters =
      selected_levels
      |> MapSet.new()
      |> MapSet.intersection(allowed_levels)

    socket =
      socket
      |> assign(:level_filters, level_filters)
      |> reset_filtered_stream()

    {:noreply, socket}
  end

  def handle_event("set_levels", _params, socket) do
    socket =
      socket
      |> assign(:level_filters, MapSet.new())
      |> reset_filtered_stream()

    {:noreply, socket}
  end

  def handle_event("filter_search", %{"query" => query}, socket) do
    socket =
      socket
      |> assign(:search_query, query)
      |> reset_filtered_stream()

    {:noreply, socket}
  end

  def handle_event("set_time_range", %{"range" => range}, socket) do
    time_range = if range in ["5m", "15m", "1h", "all"], do: range, else: "all"

    socket =
      socket
      |> assign(:time_range, time_range)
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

  def handle_event("filter_workflow", %{"workflow_id" => workflow_id}, socket) do
    socket =
      socket
      |> assign(:workflow_filter, workflow_id)
      |> reset_filtered_stream()

    {:noreply, socket}
  end

  def handle_event("select_log", %{"id" => id_str}, socket) do
    id = String.to_integer(id_str)
    selected_log = Enum.find(socket.assigns.logs, &(&1.id == id))
    {:noreply, assign(socket, :selected_log, selected_log)}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :selected_log, nil)}
  end

  def handle_event("toggle_pause", _params, socket) do
    paused = not socket.assigns.paused

    socket =
      if paused do
        assign(socket, :paused, true)
      else
        socket
        |> assign(:paused, false)
        |> reset_filtered_stream()
      end

    {:noreply, socket}
  end

  def handle_event("clear_display", _params, socket) do
    socket =
      socket
      |> assign(:logs, [])
      |> assign(:stats, %{"error" => 0, "warning" => 0, "info" => 0, "debug" => 0})
      |> assign(:workflow_ids, [])
      |> assign(:selected_log, nil)
      |> assign(:filtered_logs_count, 0)
      |> stream(:filtered_logs, [], dom_id: &"log-#{&1.id}", reset: true)

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="h-full overflow-hidden rounded-box border border-[#6d28d9]/40 bg-[#2e1065] text-gray-100">
      <.summary_bar
        stats={@stats}
        logs={@logs}
        workflow_ids={@workflow_ids}
        connected={@connected}
        paused={@paused}
      />

      <div class="flex min-h-[36rem] overflow-hidden">
        <.sidebar_filters
          level_filters={@level_filters}
          workflow_ids={@workflow_ids}
          workflow_filter={@workflow_filter}
          search_query={@search_query}
          time_range={@time_range}
        />

        <div class="flex min-w-0 flex-1 flex-col overflow-hidden">
          <div class="grid grid-cols-12 gap-6 border-y border-[#5b21b6]/40 bg-[#4c1d95]/50 px-4 py-3 text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
            <div class="col-span-2">Level</div>
            <div class="col-span-2">Timestamp</div>
            <div class="col-span-2">Workflow ID</div>
            <div class="col-span-6">Message</div>
          </div>

          <div class="flex-1 overflow-y-auto">
            <table class="table table-sm">
              <thead class="hidden">
                <tr>
                  <th>Level</th>
                  <th>Timestamp</th>
                  <th>Workflow ID</th>
                  <th>Message</th>
                </tr>
              </thead>
              <tbody id="log-stream" phx-update="stream">
                <tr
                  :for={{dom_id, log} <- @streams.filtered_logs}
                  id={dom_id}
                  phx-click="select_log"
                  phx-value-id={log.id}
                  class="cursor-pointer border-b border-[#5b21b6]/30 transition-colors hover:bg-[#5b21b6]/20"
                >
                  <td class="w-44">
                    <span class={level_badge_class(log.level)}>{level_label(log.level)}</span>
                  </td>
                  <td class="w-44 font-mono text-sm text-[#c4b5fd]">
                    {format_time(log.inserted_at)}
                  </td>
                  <td class="w-52">
                    <code class="rounded bg-[#4c1d95]/60 px-2 py-1 font-mono text-sm text-[#a78bfa]">
                      {workflow_label(log.workflow_id)}
                    </code>
                  </td>
                  <td class="font-mono text-sm text-gray-300">
                    {format_message_preview(log.message)}
                  </td>
                </tr>

                <tr :if={@filtered_logs_count == 0}>
                  <td colspan="4" class="py-16 text-center">
                    <div class="mx-auto w-fit rounded-full bg-[#4c1d95]/50 p-4">
                      <.icon name="hero-document-text" class="size-8 text-[#8b5cf6]" />
                    </div>
                    <h3 class="mt-4 text-lg font-medium text-white">No logs yet</h3>
                    <p class="mt-2 text-sm text-[#a78bfa]">
                      Logs will appear here in real-time as they are ingested.
                    </p>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <.detail_panel :if={@selected_log} log={@selected_log} />
      </div>
    </div>
    """
  end

  attr :stats, :map, required: true
  attr :logs, :list, required: true
  attr :workflow_ids, :list, required: true
  attr :connected, :boolean, required: true
  attr :paused, :boolean, required: true

  defp summary_bar(assigns) do
    total_logs = Enum.sum(Map.values(assigns.stats))

    assigns =
      assigns
      |> assign(:total_logs, total_logs)
      |> assign(:rate_per_second, logs_rate(assigns.logs))
      |> assign(:workflow_count, length(assigns.workflow_ids))
      |> assign(:last_update, last_update_label(assigns.logs))

    ~H"""
    <header class="border-b border-[#6d28d9]/50 bg-gradient-to-r from-[#4c1d95] via-[#5b21b6] to-[#4c1d95] px-6 py-4">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-4">
          <div class="flex size-10 items-center justify-center rounded-xl bg-gradient-to-br from-[#8b5cf6] to-[#6d28d9] shadow-[0_0_20px_rgba(139,92,246,0.45)]">
            <.icon name="hero-bolt" class="size-6 text-white" />
          </div>
          <div>
            <h1 class="text-xl font-bold text-white">Log Dashboard</h1>
            <p class="text-sm text-[#c4b5fd]">Real-time log aggregation & monitoring</p>
          </div>
        </div>

        <div class="flex items-center gap-6">
          <div class="flex items-center gap-2 rounded-lg border border-[#6d28d9]/40 bg-[#4c1d95]/60 px-4 py-2">
            <span class={[
              "size-2.5 rounded-full",
              if(@connected, do: "bg-green-400", else: "bg-red-400")
            ]} />
            <span class={[
              "text-sm font-medium",
              if(@connected, do: "text-green-400", else: "text-red-400")
            ]}>
              {if @connected, do: "Live", else: "Offline"}
            </span>
            <span class="ml-2 text-xs text-[#a78bfa]">{@last_update}</span>
          </div>

          <div class="flex items-center gap-2 text-sm">
            <span class="text-[#a78bfa]">Phoenix PubSub</span>
            <span class={[
              "rounded px-2 py-0.5 text-xs font-medium",
              if(@connected, do: "bg-green-500/20 text-green-400", else: "bg-red-500/20 text-red-400")
            ]}>
              {if @connected, do: "Connected", else: "Disconnected"}
            </span>
          </div>

          <button
            class="btn btn-sm border-[#6d28d9]/40 bg-[#4c1d95]/70 text-[#e9d5ff] hover:bg-[#5b21b6]"
            phx-click="toggle_pause"
          >
            <.icon name={if @paused, do: "hero-play", else: "hero-pause"} class="size-4" />
            {if @paused, do: "Resume", else: "Pause"}
          </button>
        </div>
      </div>
    </header>

    <div class="border-b border-[#5b21b6]/50 bg-[#4c1d95]/50 px-6 py-3">
      <div class="flex items-center gap-6">
        <div class="flex items-center gap-4">
          <.metric_chip
            label="Error"
            value={Map.get(@stats, "error", 0)}
            dot_class="bg-red-500"
            value_class="text-red-400"
          />
          <.metric_chip
            label="Warn"
            value={Map.get(@stats, "warning", 0)}
            dot_class="bg-yellow-500"
            value_class="text-yellow-400"
          />
          <.metric_chip
            label="Info"
            value={Map.get(@stats, "info", 0)}
            dot_class="bg-blue-500"
            value_class="text-blue-400"
          />
          <.metric_chip
            label="Debug"
            value={Map.get(@stats, "debug", 0)}
            dot_class="bg-gray-500"
            value_class="text-gray-400"
          />
        </div>
        <span class="h-6 w-px bg-[#6d28d9]" />
        <div class="flex items-center gap-4 text-sm">
          <span class="text-[#a78bfa]">
            Total: <span class="ml-1 font-mono font-semibold text-white">{@total_logs}</span>
          </span>
          <span class="text-[#a78bfa]">
            Rate:
            <span class="ml-1 font-mono font-semibold text-[#c4b5fd]">{@rate_per_second}/s</span>
          </span>
          <span class="text-[#a78bfa]">
            Workflows:
            <span class="ml-1 font-mono font-semibold text-[#c4b5fd]">{@workflow_count}</span>
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :dot_class, :string, required: true
  attr :value_class, :string, required: true

  defp metric_chip(assigns) do
    ~H"""
    <div class="flex items-center gap-2 text-sm">
      <span class={["size-3 rounded-full", @dot_class]} />
      <span class="text-gray-300">{@label}</span>
      <span class={["font-mono font-semibold", @value_class]}>{@value}</span>
    </div>
    """
  end

  attr :level_filters, :any, required: true
  attr :workflow_ids, :list, required: true
  attr :workflow_filter, :string, default: nil
  attr :search_query, :string, required: true
  attr :time_range, :string, required: true

  defp sidebar_filters(assigns) do
    ~H"""
    <aside class="w-72 shrink-0 space-y-4 overflow-y-auto border-r border-[#5b21b6]/50 bg-[#4c1d95]/30 p-4">
      <section>
        <label class="mb-2 block text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
          Search
        </label>
        <form phx-change="filter_search" class="relative">
          <input
            type="text"
            name="query"
            value={@search_query}
            placeholder="Search messages..."
            class="input w-full border-[#6d28d9]/50 bg-[#4c1d95]/50 pr-10 text-white placeholder:text-[#8b5cf6] focus:border-transparent focus:outline-none focus:ring-2 focus:ring-[#8b5cf6]"
          />
          <.icon
            name="hero-magnifying-glass"
            class="pointer-events-none absolute right-3 top-1/2 size-5 -translate-y-1/2 text-[#8b5cf6]"
          />
        </form>
      </section>

      <section>
        <label class="mb-2 block text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
          Log Level
        </label>
        <form phx-change="set_levels" class="space-y-2">
          <label
            :for={level <- ["error", "warning", "info", "debug"]}
            class="group flex cursor-pointer items-center gap-3"
          >
            <input
              type="checkbox"
              name="levels[]"
              value={level}
              checked={MapSet.member?(@level_filters, level)}
              class="checkbox checkbox-sm border-[#6d28d9] bg-[#2e1065] text-[#8b5cf6]"
            />
            <span class="flex items-center gap-2">
              <span class={["size-2 rounded-full", level_dot_color_class(level)]} />
              <span class="text-sm text-gray-300 group-hover:text-white">{level_label(level)}</span>
            </span>
          </label>
        </form>
      </section>

      <section>
        <label class="mb-2 block text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
          Workflow ID
        </label>
        <form phx-change="filter_workflow">
          <select
            name="workflow_id"
            class="select w-full border-[#6d28d9]/50 bg-[#4c1d95]/50 text-sm text-white focus:border-transparent focus:outline-none focus:ring-2 focus:ring-[#8b5cf6]"
          >
            <option value="" selected={is_nil(@workflow_filter)}>All Workflows</option>
            <option
              :for={workflow_id <- @workflow_ids}
              value={workflow_id}
              selected={@workflow_filter == to_string(workflow_id)}
            >
              {workflow_label(workflow_id)}
            </option>
          </select>
        </form>
      </section>

      <section>
        <label class="mb-2 block text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
          Time Range
        </label>
        <div class="grid grid-cols-2 gap-2">
          <button
            :for={
              {label, value} <- [{"5 min", "5m"}, {"15 min", "15m"}, {"1 hour", "1h"}, {"All", "all"}]
            }
            type="button"
            phx-click="set_time_range"
            phx-value-range={value}
            class={[
              "rounded-lg px-3 py-2 text-sm transition-colors",
              if(@time_range == value,
                do: "bg-[#6d28d9] text-white",
                else: "bg-[#4c1d95]/50 text-[#c4b5fd] hover:bg-[#5b21b6]/50"
              )
            ]}
          >
            {label}
          </button>
        </div>
      </section>

      <section class="mt-4 border-t border-[#5b21b6]/50 pt-4">
        <button
          type="button"
          phx-click="clear_display"
          class="flex w-full items-center justify-center gap-2 rounded-lg bg-red-500/10 px-4 py-2.5 text-sm text-red-400 transition-colors hover:bg-red-500/20"
        >
          <.icon name="hero-trash" class="size-4" /> Clear Display
        </button>
      </section>
    </aside>
    """
  end

  attr :log, :map, required: true

  defp detail_panel(assigns) do
    ~H"""
    <aside class="flex w-96 shrink-0 flex-col border-l border-[#5b21b6]/50 bg-[#4c1d95]/30">
      <div class="flex items-center justify-between border-b border-[#5b21b6]/50 px-4 py-3">
        <h3 class="font-medium text-white">Log Details</h3>
        <button type="button" phx-click="close_detail" class="rounded p-1 hover:bg-[#5b21b6]/50">
          <.icon name="hero-x-mark" class="size-5 text-[#a78bfa]" />
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-4">
        <div class="space-y-4">
          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-[#a78bfa]">Level</label>
            <div class="mt-1">
              <span class={level_badge_class(@log.level)}>{level_label(@log.level)}</span>
            </div>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
              Timestamp
            </label>
            <div class="mt-1 font-mono text-sm text-white">{@log.inserted_at}</div>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
              Workflow ID
            </label>
            <div class="mt-1">
              <code class="break-all rounded bg-[#2e1065]/60 px-2 py-1 font-mono text-sm text-[#c4b5fd]">
                {@log.workflow_id}
              </code>
            </div>
          </div>

          <div>
            <label class="text-xs font-medium uppercase tracking-wider text-[#a78bfa]">
              Message (JSONB)
            </label>
            <pre class="mt-1 overflow-x-auto rounded-lg bg-[#2e1065] p-4 font-mono text-xs leading-relaxed text-gray-200"><code>{format_message(@log.message)}</code></pre>
          </div>
        </div>
      </div>
    </aside>
    """
  end

  defp matches_filters?(log, assigns) do
    level_match = MapSet.member?(assigns.level_filters, log.level)

    workflow_match =
      case assigns.workflow_filter do
        nil ->
          true

        workflow_filter ->
          log.workflow_id
          |> to_string()
          |> String.downcase()
          |> String.contains?(String.downcase(workflow_filter))
      end

    search_match =
      case String.trim(assigns.search_query || "") do
        "" ->
          true

        search_query ->
          log.message
          |> format_message()
          |> String.downcase()
          |> String.contains?(String.downcase(search_query))
      end

    time_match = within_time_range?(log.inserted_at, assigns.time_range)

    level_match and workflow_match and search_match and time_match
  end

  defp reset_filtered_stream(socket) do
    filtered_logs =
      socket.assigns.logs
      |> Enum.filter(&matches_filters?(&1, socket.assigns))

    socket
    |> assign(:filtered_logs_count, length(filtered_logs))
    |> stream(:filtered_logs, filtered_logs, dom_id: &"log-#{&1.id}", reset: true)
  end

  defp level_badge_class("error"), do: "badge border-red-500/30 bg-red-500/20 text-red-400"

  defp level_badge_class("warning"),
    do: "badge border-yellow-500/30 bg-yellow-500/20 text-yellow-400"

  defp level_badge_class("info"), do: "badge border-blue-500/30 bg-blue-500/20 text-blue-400"
  defp level_badge_class("debug"), do: "badge border-gray-500/30 bg-gray-500/20 text-gray-400"
  defp level_badge_class(_), do: "badge border-blue-500/30 bg-blue-500/20 text-blue-400"

  defp level_dot_color_class("error"), do: "bg-red-500"
  defp level_dot_color_class("warning"), do: "bg-yellow-500"
  defp level_dot_color_class("info"), do: "bg-blue-500"
  defp level_dot_color_class("debug"), do: "bg-gray-500"
  defp level_dot_color_class(_), do: "bg-gray-500"

  defp level_label("warning"), do: "Warning"
  defp level_label("error"), do: "Error"
  defp level_label("info"), do: "Info"
  defp level_label("debug"), do: "Debug"
  defp level_label(level), do: String.capitalize(to_string(level))

  defp format_message(map) when is_map(map), do: Jason.encode!(map, pretty: true)
  defp format_message(other), do: inspect(other)

  defp format_message_preview(map) when is_map(map) do
    message = Jason.encode!(map)

    if byte_size(message) > 120 do
      String.slice(message, 0, 120) <> "..."
    else
      message
    end
  end

  defp format_message_preview(other), do: inspect(other)

  defp format_time(timestamp) do
    case to_utc_datetime(timestamp) do
      %DateTime{} = datetime -> Calendar.strftime(datetime, "%H:%M:%S")
      _ -> "--:--:--"
    end
  end

  defp last_update_label([]), do: "Waiting for updates"

  defp last_update_label([%{inserted_at: inserted_at} | _]) do
    "Updated #{relative_time(inserted_at)}"
  end

  defp last_update_label(_), do: "Waiting for updates"

  defp workflow_label(workflow_id) do
    workflow_id
    |> to_string()
    |> String.slice(0, 8)
    |> Kernel.<>("...")
  end

  defp relative_time(nil), do: ""

  defp relative_time(timestamp) when is_binary(timestamp) do
    timestamp_with_z = if String.ends_with?(timestamp, "Z"), do: timestamp, else: timestamp <> "Z"

    case DateTime.from_iso8601(timestamp_with_z) do
      {:ok, datetime, _offset} -> relative_time(datetime)
      _ -> timestamp
    end
  end

  defp relative_time(%DateTime{} = datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp relative_time(%NaiveDateTime{} = naive_datetime) do
    naive_datetime
    |> DateTime.from_naive!("Etc/UTC")
    |> relative_time()
  end

  defp relative_time(_), do: ""

  defp within_time_range?(_timestamp, "all"), do: true

  defp within_time_range?(timestamp, time_range) do
    case to_utc_datetime(timestamp) do
      %DateTime{} = datetime ->
        elapsed = DateTime.diff(DateTime.utc_now(), datetime, :second)
        elapsed >= 0 and elapsed <= range_seconds(time_range)

      _ ->
        false
    end
  end

  defp range_seconds("5m"), do: 300
  defp range_seconds("15m"), do: 900
  defp range_seconds("1h"), do: 3600
  defp range_seconds(_), do: 31_536_000

  defp logs_rate(logs) do
    cutoff = DateTime.add(DateTime.utc_now(), -1, :second)

    Enum.count(logs, fn log ->
      case to_utc_datetime(log.inserted_at) do
        %DateTime{} = datetime -> DateTime.compare(datetime, cutoff) in [:gt, :eq]
        _ -> false
      end
    end)
  end

  defp to_utc_datetime(%DateTime{} = datetime), do: datetime

  defp to_utc_datetime(%NaiveDateTime{} = naive_datetime) do
    DateTime.from_naive!(naive_datetime, "Etc/UTC")
  end

  defp to_utc_datetime(timestamp) when is_binary(timestamp) do
    timestamp_with_z = if String.ends_with?(timestamp, "Z"), do: timestamp, else: timestamp <> "Z"

    case DateTime.from_iso8601(timestamp_with_z) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        case NaiveDateTime.from_iso8601(timestamp) do
          {:ok, naive_datetime} -> DateTime.from_naive!(naive_datetime, "Etc/UTC")
          _ -> nil
        end
    end
  end

  defp to_utc_datetime(_), do: nil
end
