defmodule LogAppWeb.LogLive.Index do
  use LogAppWeb, :live_view

  alias LogApp.Logs

  def mount(_params, _session, socket) do
    if connected?(socket) do
      LogAppWeb.Endpoint.subscribe("logs:updates")
    end

    logs = Logs.list_logs()

    {:ok, assign(socket, :logs, logs)}
  end

  def handle_info(%{"event" => "log_created", "payload" => payload}, socket) do
    new_log = %{
      id: payload["id"],
      level: payload["level"],
      workflow_id: payload["workflow_id"],
      message: payload["message"],
      inserted_at: payload["inserted_at"]
    }

    logs = [new_log | socket.assigns.logs]
    {:noreply, assign(socket, :logs, logs)}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="px-4 py-6 sm:px-6 lg:px-8">
        <div class="sm:flex sm:items-center">
          <div class="sm:flex-auto">
            <h1 class="text-base font-semibold leading-6 text-gray-900">Logs</h1>
            <p class="mt-2 text-sm text-gray-700">
              Real-time log stream from ingress. Updates appear instantly.
            </p>
          </div>
        </div>
        <div class="mt-8 flow-root">
          <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
            <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
              <table class="min-w-full border-collapse border border-gray-300">
                <thead class="bg-gray-50">
                  <tr>
                    <th class="border border-gray-300 px-3 py-3.5 text-left text-sm font-semibold text-gray-900">ID</th>
                    <th class="border border-gray-300 px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Level</th>
                    <th class="border border-gray-300 px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Workflow ID</th>
                    <th class="border border-gray-300 px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Message</th>
                    <th class="border border-gray-300 px-3 py-3.5 text-left text-sm font-semibold text-gray-900">Created At</th>
                  </tr>
                </thead>
                <tbody class="bg-white">
                  <%= if Enum.empty?(@logs) do %>
                    <tr>
                      <td colspan="5" class="border border-gray-300 px-3 py-2 text-center text-sm text-gray-500">
                        No logs yet. Send logs to POST /logs on the ingress server.
                      </td>
                    </tr>
                  <% else %>
                    <%= for log <- @logs do %>
                      <tr class="border-b border-gray-300">
                        <td class="border border-gray-300 whitespace-nowrap px-3 py-2 text-sm font-medium text-gray-900"><%= log.id %></td>
                        <td class="border border-gray-300 whitespace-nowrap px-3 py-2 text-sm">
                          <span class={log_level_badge(log.level)}><%= log.level %></span>
                        </td>
                        <td class="border border-gray-300 whitespace-nowrap px-3 py-2 text-sm text-gray-700 font-mono text-xs"><%= log.workflow_id %></td>
                        <td class="border border-gray-300 px-3 py-2 text-sm text-gray-700">
                          <div class="max-w-xs overflow-hidden text-ellipsis">
                            <code class="text-xs"><%= format_message(log.message) %></code>
                          </div>
                        </td>
                        <td class="border border-gray-300 whitespace-nowrap px-3 py-2 text-sm text-gray-700">
                          <%= log.inserted_at %>
                        </td>
                      </tr>
                    <% end %>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp log_level_badge("error") do
    "inline-flex items-center rounded-full bg-red-100 px-3 py-1 text-sm font-medium text-red-700"
  end

  defp log_level_badge("warning") do
    "inline-flex items-center rounded-full bg-yellow-100 px-3 py-1 text-sm font-medium text-yellow-700"
  end

  defp log_level_badge("info") do
    "inline-flex items-center rounded-full bg-blue-100 px-3 py-1 text-sm font-medium text-blue-700"
  end

  defp log_level_badge("debug") do
    "inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700"
  end

  defp log_level_badge(_) do
    "inline-flex items-center rounded-full bg-gray-100 px-3 py-1 text-sm font-medium text-gray-700"
  end

  defp format_message(map) when is_map(map) do
    inspect(map)
  end

  defp format_message(other) do
    inspect(other)
  end
end

