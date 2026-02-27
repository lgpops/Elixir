defmodule LogAppWeb.LogLive.Index do
  use LogAppWeb, :live_view

  alias LogApp.Logs

  @time_ranges %{
    "5m" => 5 * 60,
    "15m" => 15 * 60,
    "1h" => 60 * 60,
    "all" => :infinity
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      LogAppWeb.Endpoint.subscribe("logs:updates")
      :timer.send_interval(1000, self(), :tick_rate)
    end

    logs = Logs.list_logs()

    socket =
      socket
      |> assign(:logs, logs)
      |> assign(:filtered_logs, logs)
      |> assign(:selected_log, nil)
      |> assign(:search, "")
      |> assign(:active_levels, MapSet.new(["error", "warning", "info", "debug"]))
      |> assign(:time_range, "all")
      |> assign(:workflow_filter, "")
      |> assign(:page_title, "Log Dashboard")
      |> assign(:recent_count, 0)
      |> compute_stats()

    {:ok, socket, layout: false}
  end

  @impl true
  def handle_info(%{"event" => "log_created", "payload" => payload}, socket) do
    new_log = %{
      id: payload["id"],
      level: payload["level"],
      workflow_id: payload["workflow_id"],
      message: payload["message"],
      inserted_at: payload["inserted_at"]
    }

    logs = [new_log | socket.assigns.logs]

    socket =
      socket
      |> assign(:logs, logs)
      |> assign(:recent_count, socket.assigns.recent_count + 1)
      |> apply_filters()
      |> compute_stats()

    {:noreply, socket}
  end

  def handle_info(:tick_rate, socket) do
    {:noreply, assign(socket, :recent_count, 0)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:search, search)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("toggle_level", %{"level" => level}, socket) do
    levels = socket.assigns.active_levels

    new_levels =
      if MapSet.member?(levels, level) do
        MapSet.delete(levels, level)
      else
        MapSet.put(levels, level)
      end

    socket =
      socket
      |> assign(:active_levels, new_levels)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("set_time_range", %{"range" => range}, socket) do
    socket =
      socket
      |> assign(:time_range, range)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("filter_workflow", %{"workflow" => workflow}, socket) do
    socket =
      socket
      |> assign(:workflow_filter, workflow)
      |> apply_filters()

    {:noreply, socket}
  end

  def handle_event("select_log", %{"id" => id}, socket) do
    log = Enum.find(socket.assigns.logs, &(to_string(&1.id) == id))
    {:noreply, assign(socket, :selected_log, log)}
  end

  def handle_event("close_detail", _, socket) do
    {:noreply, assign(socket, :selected_log, nil)}
  end

  def handle_event("clear_logs", _, socket) do
    socket =
      socket
      |> assign(:logs, [])
      |> assign(:filtered_logs, [])
      |> assign(:selected_log, nil)
      |> compute_stats()

    {:noreply, socket}
  end

  # ── Filtering ──

  defp apply_filters(socket) do
    %{
      logs: logs,
      active_levels: levels,
      search: search,
      time_range: time_range,
      workflow_filter: wf
    } = socket.assigns

    now = DateTime.utc_now()
    range_seconds = Map.get(@time_ranges, time_range, :infinity)

    filtered =
      Enum.filter(logs, fn log ->
        level_match?(log.level, levels) &&
          workflow_match?(log.workflow_id, wf) &&
          search_match?(log, search) &&
          time_match?(log.inserted_at, now, range_seconds)
      end)

    assign(socket, :filtered_logs, filtered)
  end

  defp level_match?(level, levels), do: MapSet.member?(levels, level)

  defp workflow_match?(_wid, ""), do: true
  defp workflow_match?(wid, filter), do: wid == filter

  defp search_match?(_log, ""), do: true

  defp search_match?(log, search) do
    search_lower = String.downcase(search)
    message_str = if is_map(log.message), do: Jason.encode!(log.message), else: to_string(log.message)

    String.contains?(String.downcase(message_str), search_lower) ||
      String.contains?(String.downcase(to_string(log.workflow_id)), search_lower)
  end

  defp time_match?(_inserted_at, _now, :infinity), do: true

  defp time_match?(inserted_at, now, range_seconds) when is_binary(inserted_at) do
    case DateTime.from_iso8601(inserted_at) do
      {:ok, dt, _} -> DateTime.diff(now, dt) <= range_seconds
      _ -> true
    end
  end

  defp time_match?(%DateTime{} = inserted_at, now, range_seconds) do
    DateTime.diff(now, inserted_at) <= range_seconds
  end

  defp time_match?(%NaiveDateTime{} = inserted_at, now, range_seconds) do
    case DateTime.from_naive(inserted_at, "Etc/UTC") do
      {:ok, dt} -> DateTime.diff(now, dt) <= range_seconds
      _ -> true
    end
  end

  defp time_match?(_, _, _), do: true

  # ── Stats ──

  defp compute_stats(socket) do
    logs = socket.assigns.logs

    counts =
      Enum.reduce(logs, %{"error" => 0, "warning" => 0, "info" => 0, "debug" => 0}, fn log, acc ->
        Map.update(acc, log.level, 1, &(&1 + 1))
      end)

    workflows =
      logs
      |> Enum.map(& &1.workflow_id)
      |> Enum.uniq()
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(:stats, counts)
    |> assign(:workflows, workflows)
  end

  # ── Helpers ──

  defp format_timestamp(nil), do: "--:--:--"

  defp format_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%H:%M:%S")
      _ -> ts
    end
  end

  defp format_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_timestamp(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_timestamp(other), do: to_string(other)

  defp format_full_timestamp(nil), do: "N/A"

  defp format_full_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
      _ -> ts
    end
  end

  defp format_full_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_full_timestamp(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")
  defp format_full_timestamp(other), do: to_string(other)

  defp truncate_workflow(nil), do: "--------"
  defp truncate_workflow(id) when byte_size(id) > 8, do: String.slice(id, 0, 8) <> "..."
  defp truncate_workflow(id), do: id

  defp truncate_message(msg) when is_map(msg) do
    str = Jason.encode!(msg)
    if String.length(str) > 80, do: String.slice(str, 0, 80) <> "...", else: str
  end

  defp truncate_message(msg), do: inspect(msg)

  defp format_json(msg) when is_map(msg) do
    Jason.encode!(msg, pretty: true)
  end

  defp format_json(msg), do: inspect(msg, pretty: true)

  defp level_badge_class("error"), do: "bg-red-500/20 text-red-400 border-red-500/30"
  defp level_badge_class("warning"), do: "bg-yellow-500/20 text-yellow-400 border-yellow-500/30"
  defp level_badge_class("info"), do: "bg-blue-500/20 text-blue-400 border-blue-500/30"
  defp level_badge_class("debug"), do: "bg-gray-500/20 text-gray-400 border-gray-500/30"
  defp level_badge_class(_), do: "bg-gray-500/20 text-gray-400 border-gray-500/30"

  defp level_dot_class("error"), do: "bg-red-500"
  defp level_dot_class("warning"), do: "bg-yellow-500"
  defp level_dot_class("info"), do: "bg-blue-500"
  defp level_dot_class("debug"), do: "bg-gray-500"
  defp level_dot_class(_), do: "bg-gray-500"

  defp level_count_class("error"), do: "text-red-400"
  defp level_count_class("warning"), do: "text-yellow-400"
  defp level_count_class("info"), do: "text-blue-400"
  defp level_count_class("debug"), do: "text-gray-400"
  defp level_count_class(_), do: "text-gray-400"

  defp level_check_class("error"), do: "accent-red-500"
  defp level_check_class("warning"), do: "accent-yellow-500"
  defp level_check_class("info"), do: "accent-blue-500"
  defp level_check_class("debug"), do: "accent-gray-500"
  defp level_check_class(_), do: "accent-gray-500"

  defp level_label("warning"), do: "Warning"
  defp level_label(level), do: String.capitalize(level)

  @impl true
  def render(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={get_csrf_token()} />
        <title>Elixir Log Dashboard</title>
        <link
          href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Inter:wght@400;500;600;700&display=swap"
          rel="stylesheet"
        />
        <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
        <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
        </script>
        <style>
          * { font-family: 'Inter', system-ui, sans-serif; }
          .font-mono { font-family: 'JetBrains Mono', monospace !important; }
        </style>
      </head>
      <body class="h-full" style="background-color: #2e1065; color: #f3f4f6;">
        <div class="h-full flex flex-col overflow-hidden">
          <%!-- Header --%>
          <header
            class="flex-shrink-0 px-6 py-4 border-b"
            style="background: linear-gradient(to right, #4c1d95, #5b21b6, #4c1d95); border-color: rgba(109,40,217,0.5);"
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-4">
                <div
                  class="w-10 h-10 rounded-xl flex items-center justify-center glow-effect"
                  style="background: linear-gradient(to bottom right, #8b5cf6, #6d28d9);"
                >
                  <svg viewBox="0 0 24 24" class="w-6 h-6 text-white" fill="currentColor">
                    <path d="M12 2C8.5 6 6 10.5 6 14c0 3.31 2.69 6 6 6s6-2.69 6-6c0-3.5-2.5-8-6-12zm0 16c-1.1 0-2-.9-2-2 0-.55.22-1.05.58-1.42C11 14.22 12 13 12 13s1 1.22 1.42 1.58c.36.37.58.87.58 1.42 0 1.1-.9 2-2 2z" />
                  </svg>
                </div>
                <div>
                  <h1 class="text-xl font-bold text-white">Elixir Log Dashboard</h1>
                  <p class="text-sm" style="color: #c4b5fd;">
                    Real-time log aggregation & monitoring
                  </p>
                </div>
              </div>
              <div class="flex items-center gap-6">
                <div
                  class="flex items-center gap-2 px-4 py-2 rounded-lg"
                  style="background: rgba(76,29,149,0.5); border: 1px solid rgba(109,40,217,0.3);"
                >
                  <span class="w-2.5 h-2.5 bg-green-400 rounded-full live-indicator"></span>
                  <span class="text-sm font-medium text-green-400">Live</span>
                  <span class="text-xs ml-2" style="color: #a78bfa;">Updated just now</span>
                </div>
                <div class="flex items-center gap-2 text-sm">
                  <span style="color: #a78bfa;">Phoenix PubSub</span>
                  <span class="px-2 py-0.5 rounded text-xs font-medium" style="background: rgba(34,197,94,0.2); color: #4ade80;">
                    Connected
                  </span>
                </div>
              </div>
            </div>
          </header>

          <%!-- Stats Bar --%>
          <div
            class="flex-shrink-0 px-6 py-3 border-b"
            style="background: rgba(76,29,149,0.5); border-color: rgba(91,33,182,0.5);"
          >
            <div class="flex items-center gap-6">
              <div class="flex items-center gap-4">
                <div :for={level <- ["error", "warning", "info", "debug"]} class="flex items-center gap-2">
                  <span class={"w-3 h-3 rounded-full #{level_dot_class(level)}"}></span>
                  <span class="text-sm text-gray-300">{level_label(level)}</span>
                  <span class={"font-mono text-sm font-semibold #{level_count_class(level)}"}>
                    {Map.get(@stats, level, 0)}
                  </span>
                </div>
              </div>
              <div class="w-px h-6" style="background: #6d28d9;"></div>
              <div class="flex items-center gap-4">
                <div class="text-sm">
                  <span style="color: #a78bfa;">Total:</span>
                  <span class="font-mono font-semibold text-white ml-1">{length(@logs)}</span>
                </div>
                <div class="text-sm">
                  <span style="color: #a78bfa;">Rate:</span>
                  <span class="font-mono font-semibold ml-1" style="color: #c4b5fd;">
                    {@recent_count}/s
                  </span>
                </div>
                <div class="text-sm">
                  <span style="color: #a78bfa;">Workflows:</span>
                  <span class="font-mono font-semibold ml-1" style="color: #c4b5fd;">
                    {length(@workflows)}
                  </span>
                </div>
              </div>
            </div>
          </div>

          <%!-- Main Content --%>
          <div class="flex-1 flex overflow-hidden">
            <%!-- Sidebar Filters --%>
            <aside
              class="w-72 flex-shrink-0 border-r p-4 flex flex-col gap-4 overflow-y-auto"
              style="background: rgba(76,29,149,0.3); border-color: rgba(91,33,182,0.5);"
            >
              <%!-- Search --%>
              <div>
                <label
                  class="block text-xs font-medium mb-2 uppercase tracking-wider"
                  style="color: #a78bfa;"
                >
                  Search
                </label>
                <div class="relative">
                  <input
                    type="text"
                    placeholder="Search messages..."
                    value={@search}
                    phx-keyup="search"
                    phx-key=""
                    name="search"
                    phx-debounce="200"
                    class="w-full rounded-lg px-4 py-2.5 text-sm text-white placeholder-purple-400 focus:outline-none focus:ring-2"
                    style="background: rgba(76,29,149,0.5); border: 1px solid rgba(109,40,217,0.5); --tw-ring-color: #8b5cf6;"
                  />
                  <svg
                    class="absolute right-3 top-2.5 w-5 h-5"
                    style="color: #8b5cf6;"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                    />
                  </svg>
                </div>
              </div>

              <%!-- Level Filter --%>
              <div>
                <label
                  class="block text-xs font-medium mb-2 uppercase tracking-wider"
                  style="color: #a78bfa;"
                >
                  Log Level
                </label>
                <div class="flex flex-col gap-2">
                  <label
                    :for={level <- ["error", "warning", "info", "debug"]}
                    class="flex items-center gap-3 cursor-pointer group"
                  >
                    <input
                      type="checkbox"
                      checked={MapSet.member?(@active_levels, level)}
                      phx-click="toggle_level"
                      phx-value-level={level}
                      class={"w-4 h-4 rounded #{level_check_class(level)}"}
                    />
                    <span class="flex items-center gap-2">
                      <span class={"w-2 h-2 rounded-full #{level_dot_class(level)}"}></span>
                      <span class="text-sm text-gray-300 group-hover:text-white">
                        {level_label(level)}
                      </span>
                    </span>
                  </label>
                </div>
              </div>

              <%!-- Workflow Filter --%>
              <div>
                <label
                  class="block text-xs font-medium mb-2 uppercase tracking-wider"
                  style="color: #a78bfa;"
                >
                  Workflow ID
                </label>
                <select
                  phx-change="filter_workflow"
                  name="workflow"
                  class="w-full rounded-lg px-4 py-2.5 text-sm text-white focus:outline-none focus:ring-2"
                  style="background: rgba(76,29,149,0.5); border: 1px solid rgba(109,40,217,0.5); --tw-ring-color: #8b5cf6;"
                >
                  <option value="">All Workflows</option>
                  <option :for={wf <- @workflows} value={wf} selected={@workflow_filter == wf}>
                    {truncate_workflow(wf)}
                  </option>
                </select>
              </div>

              <%!-- Time Range --%>
              <div>
                <label
                  class="block text-xs font-medium mb-2 uppercase tracking-wider"
                  style="color: #a78bfa;"
                >
                  Time Range
                </label>
                <div class="grid grid-cols-2 gap-2">
                  <button
                    :for={{label, range} <- [{"5 min", "5m"}, {"15 min", "15m"}, {"1 hour", "1h"}, {"All", "all"}]}
                    phx-click="set_time_range"
                    phx-value-range={range}
                    class={[
                      "px-3 py-2 text-sm rounded-lg transition-colors",
                      if(@time_range == range,
                        do: "font-medium text-white",
                        else: "hover:opacity-80"
                      )
                    ]}
                    style={
                      if(@time_range == range,
                        do: "background: #6d28d9; color: white;",
                        else: "background: rgba(76,29,149,0.5); color: #c4b5fd;"
                      )
                    }
                  >
                    {label}
                  </button>
                </div>
              </div>

              <%!-- Clear Logs --%>
              <div class="mt-auto pt-4 border-t" style="border-color: rgba(91,33,182,0.5);">
                <button
                  phx-click="clear_logs"
                  class="w-full px-4 py-2.5 text-sm rounded-lg flex items-center justify-center gap-2 transition-colors"
                  style="background: rgba(239,68,68,0.1); color: #f87171;"
                  onmouseover="this.style.background='rgba(239,68,68,0.2)'"
                  onmouseout="this.style.background='rgba(239,68,68,0.1)'"
                >
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                    />
                  </svg>
                  Clear Display
                </button>
              </div>
            </aside>

            <%!-- Log Table --%>
            <main class="flex-1 flex flex-col overflow-hidden">
              <%!-- Table Header --%>
              <div
                class="flex-shrink-0 px-4 py-3 border-b"
                style="background: rgba(76,29,149,0.5); border-color: rgba(91,33,182,0.5);"
              >
                <div class="grid grid-cols-12 gap-6 text-xs font-medium uppercase tracking-wider" style="color: #a78bfa;">
                  <div class="col-span-2">Level</div>
                  <div class="col-span-2">Timestamp</div>
                  <div class="col-span-2">Workflow ID</div>
                  <div class="col-span-6">Message</div>
                </div>
              </div>

              <%!-- Table Body --%>
              <div class="flex-1 overflow-y-auto log-table">
                <%= if Enum.empty?(@filtered_logs) do %>
                  <%!-- Empty State --%>
                  <div class="flex flex-col items-center justify-center h-full text-center py-12">
                    <div
                      class="w-16 h-16 rounded-full flex items-center justify-center mb-4"
                      style="background: rgba(91,33,182,0.5);"
                    >
                      <svg class="w-8 h-8" style="color: #8b5cf6;" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
                        />
                      </svg>
                    </div>
                    <h3 class="text-lg font-medium text-white mb-2">No logs yet</h3>
                    <p class="text-sm max-w-sm" style="color: #a78bfa;">
                      Logs will appear here in real-time as they are ingested through the Phoenix PubSub channel.
                    </p>
                    <div class="mt-6 flex items-center gap-2 text-xs" style="color: #8b5cf6;">
                      <span class="w-2 h-2 bg-green-400 rounded-full live-indicator"></span>
                      {"Listening on logs:updates topic"}
                    </div>
                  </div>
                <% else %>
                  <div id="log-list">
                    <div
                      :for={log <- @filtered_logs}
                      phx-click="select_log"
                      phx-value-id={log.id}
                      class="grid grid-cols-12 gap-6 px-4 py-3 cursor-pointer transition-colors border-b"
                      style={"border-color: rgba(91,33,182,0.3); #{if @selected_log && @selected_log.id == log.id, do: "background: rgba(109,40,217,0.3);", else: ""}"}
                      onmouseover="this.style.background='rgba(91,33,182,0.3)'"
                      onmouseout={"this.style.background='#{if @selected_log && @selected_log.id == log.id, do: "rgba(109,40,217,0.3)", else: ""}'"}
                    >
                      <div class="col-span-2 flex items-center">
                        <span class={"inline-flex items-center px-2.5 py-1 rounded-md text-xs font-medium border #{level_badge_class(log.level)}"}>
                          {String.upcase(log.level)}
                        </span>
                      </div>
                      <div class="col-span-2 flex items-center text-sm font-mono" style="color: #c4b5fd;">
                        {format_timestamp(log.inserted_at)}
                      </div>
                      <div class="col-span-2 flex items-center">
                        <code
                          class="text-sm px-2 py-1 rounded font-mono"
                          style="color: #a78bfa; background: rgba(76,29,149,0.5);"
                        >
                          {truncate_workflow(log.workflow_id)}
                        </code>
                      </div>
                      <div class="col-span-6 flex items-center text-sm text-gray-300 truncate font-mono">
                        {truncate_message(log.message)}
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </main>

            <%!-- Detail Panel --%>
            <aside
              :if={@selected_log}
              class="w-96 flex-shrink-0 flex flex-col border-l"
              style="background: rgba(76,29,149,0.3); border-color: rgba(91,33,182,0.5);"
            >
              <div
                class="flex items-center justify-between px-4 py-3 border-b"
                style="border-color: rgba(91,33,182,0.5);"
              >
                <h3 class="font-medium text-white">Log Details</h3>
                <button phx-click="close_detail" class="p-1 rounded cursor-pointer" style="color: #a78bfa;">
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                </button>
              </div>
              <div class="flex-1 overflow-y-auto p-4">
                <div class="flex flex-col gap-4">
                  <div>
                    <label class="text-xs font-medium uppercase tracking-wider" style="color: #a78bfa;">
                      Level
                    </label>
                    <div class="mt-1">
                      <span class={"inline-flex items-center px-2.5 py-1 rounded-md text-xs font-medium border #{level_badge_class(@selected_log.level)}"}>
                        {String.upcase(@selected_log.level)}
                      </span>
                    </div>
                  </div>

                  <div>
                    <label class="text-xs font-medium uppercase tracking-wider" style="color: #a78bfa;">
                      Timestamp
                    </label>
                    <div class="mt-1 text-sm text-white font-mono">
                      {format_full_timestamp(@selected_log.inserted_at)}
                    </div>
                  </div>

                  <div>
                    <label class="text-xs font-medium uppercase tracking-wider" style="color: #a78bfa;">
                      Workflow ID
                    </label>
                    <div class="mt-1">
                      <code
                        class="text-sm px-2 py-1 rounded font-mono break-all"
                        style="color: #c4b5fd; background: rgba(76,29,149,0.5);"
                      >
                        {@selected_log.workflow_id}
                      </code>
                    </div>
                  </div>

                  <div>
                    <label class="text-xs font-medium uppercase tracking-wider" style="color: #a78bfa;">
                      {"Message (JSONB)"}
                    </label>
                    <pre
                      class="mt-1 text-sm rounded-lg p-4 overflow-x-auto font-mono text-xs leading-relaxed text-gray-200"
                      style="background: #2e1065;"
                    >{format_json(@selected_log.message)}</pre>
                  </div>

                  <div class="pt-4 border-t" style="border-color: rgba(91,33,182,0.5);">
                    <button
                      id="copy-json-btn"
                      phx-hook="CopyToClipboard"
                      data-clipboard-text={Jason.encode!(@selected_log.message, pretty: true)}
                      class="w-full px-4 py-2 text-sm text-white rounded-lg flex items-center justify-center gap-2 transition-colors cursor-pointer"
                      style="background: #6d28d9;"
                      onmouseover="this.style.background='#7c3aed'"
                      onmouseout="this.style.background='#6d28d9'"
                    >
                      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="2"
                          d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z"
                        />
                      </svg>
                      Copy JSON
                    </button>
                  </div>
                </div>
              </div>
            </aside>
          </div>
        </div>
      </body>
    </html>
    """
  end
end
