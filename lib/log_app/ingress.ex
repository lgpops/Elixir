defmodule LogApp.Ingress.Router do
  @moduledoc """
  Lightweight HTTP router for the ingress server.
  Handles POST /logs requests containing log entries.
  """

  use Plug.Router
  require Logger

  plug :log_request
  plug :match
  plug :dispatch

  def log_request(conn, _opts) do
    Logger.debug("#{conn.method} #{conn.request_path}")
    conn
  end

  match "logs", do: handle_logs(conn)
  match _, do: send_error_response(conn, 404, "Not found")

  defp handle_logs(conn) do
    case conn.method do
      "POST" -> handle_post_logs(conn)
      _ -> send_error_response(conn, 405, "Method not allowed")
    end
  end

  defp handle_post_logs(conn) do
    case Plug.Conn.read_body(conn) do
      {:ok, body, _conn} ->
        case process_log_request(body) do
          {:ok, log} ->
            response = Jason.encode!(%{ok: true, id: log.id})

            conn
            |> Plug.Conn.put_resp_header("content-type", "application/json")
            |> Plug.Conn.send_resp(201, response)

          {:error, reason} ->
            send_error_response(conn, 400, to_string(reason))
        end

      {:error, _reason} ->
        send_error_response(conn, 400, "Failed to read request body")
    end
  end

  defp process_log_request(body) do
    case Jason.decode(body) do
      {:ok, %{"level" => level, "workflow_id" => workflow_id, "message" => message}} ->
        LogApp.Logs.create_log(%{
          level: level,
          workflow_id: workflow_id,
          message: message
        })
        |> tap(fn
          {:ok, log} ->
            Logger.info("Log created: id=#{log.id}, level=#{log.level}, workflow_id=#{log.workflow_id}")
            LogApp.Logs.broadcast_log(log)

          {:error, changeset} ->
            Logger.error("Failed to create log: #{inspect(changeset.errors)}")
        end)

      {:ok, _} ->
        {:error, "Missing required fields: level, workflow_id, message"}

      {:error, _} ->
        {:error, "Invalid JSON"}
    end
  end

  defp send_error_response(conn, status, error_message) do
    response = Jason.encode!(%{error: error_message})

    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(status, response)
  end
end

defmodule LogApp.Ingress do
  @moduledoc """
  HTTP Ingress server for receiving logs from external systems.
  
  Lightweight implementation using Plug.Router with Cowboy.
  Accepts POST requests to /logs containing log entries in JSON format.
  """

  require Logger

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def start_link(opts) do
    port = Keyword.get(opts, :port, 4001)

    Logger.info("Starting ingress server on port #{port}")

    {:ok, _pid} =
      Plug.Cowboy.http(LogApp.Ingress.Router, [], ip: {127, 0, 0, 1}, port: port)

    {:ok, self()}
  end
end
