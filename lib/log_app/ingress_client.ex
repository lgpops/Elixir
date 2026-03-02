defmodule LogApp.IngressClient do
  @moduledoc """
  Client for sending log entries to the ingress endpoint.

  Uses `Req` and supports both:

  - Unix socket ingress (default in dev via `:ingress_socket_path`)
  - TCP ingress (`localhost:<ingress_port>`)

  ## Examples

      iex> LogApp.IngressClient.send_log("info", "550e8400-e29b-41d4-a716-446655440000", %{message: "hello"})
      {:ok, %{id: 123, ok: true}}

      iex> LogApp.IngressClient.send_log(%{
      ...>   level: "error",
      ...>   workflow_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   message: %{event: "failed"}
      ...> })
      {:ok, %{id: 124, ok: true}}
  """

  @type payload :: %{level: String.t(), workflow_id: String.t(), message: map()}
  @type result :: {:ok, map()} | {:error, term()}

  @spec send_info(String.t(), String.t()) :: result()
  def send_info(workflow_id, text_message)
      when is_binary(workflow_id) and is_binary(text_message) do
    send_log("info", workflow_id, %{message: text_message})
  end

  @spec send_log(String.t(), String.t(), map()) :: result()
  def send_log(level, workflow_id, message)
      when is_binary(level) and is_binary(workflow_id) and is_map(message) do
    send_log(%{level: level, workflow_id: workflow_id, message: message})
  end

  @spec send_log(payload()) :: result()
  def send_log(%{level: level, workflow_id: workflow_id, message: message})
      when is_binary(level) and is_binary(workflow_id) and is_map(message) do
    payload = %{
      level: level,
      workflow_id: workflow_id,
      message: message
    }

    case post_over_http(payload) do
      {:ok, _} = ok ->
        ok

      {:error, _reason} = http_error ->
        case Application.get_env(:log_app, :ingress_socket_path) do
          nil ->
            http_error

          _socket_path ->
            post_internal(payload)
        end
    end
  end

  def send_log(_), do: {:error, :invalid_payload}

  defp post_over_http(payload) do
    request_options = ingress_request_options()

    case Req.post(request_options, json: payload) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, normalize_body(body)}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: normalize_body(body)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp post_internal(payload) do
    body = Jason.encode!(payload)

    conn =
      Plug.Test.conn(:post, "/logs", body)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> LogApp.Ingress.Router.call([])

    if conn.status in 200..299 do
      body = if is_binary(conn.resp_body), do: Jason.decode!(conn.resp_body), else: conn.resp_body
      {:ok, normalize_body(body)}
    else
      {:error, %{status: conn.status, body: conn.resp_body}}
    end
  end

  defp ingress_request_options do
    base_url =
      Application.get_env(:log_app, :ingress_base_url) ||
        "http://localhost:#{Application.get_env(:log_app, :ingress_port, 4001)}/logs"

    [url: base_url]
  end

  defp normalize_body(body) when is_map(body), do: atomize_top_keys(body)
  defp normalize_body(body), do: body

  defp atomize_top_keys(map) do
    Enum.into(map, %{}, fn
      {"ok", value} -> {:ok, value}
      {"id", value} -> {:id, value}
      {"error", value} -> {:error, value}
      {key, value} when is_binary(key) -> {key, value}
      pair -> pair
    end)
  end
end
