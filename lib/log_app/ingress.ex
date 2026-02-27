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

  match("logs", do: handle_logs(conn))
  match(_, do: send_error_response(conn, 404, "Not found"))

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

          {:error, status, reason} ->
            send_error_response(conn, status, reason)
        end

      {:error, _reason} ->
        send_error_response(conn, 400, "Failed to read request body")
    end
  end

  defp process_log_request(body) do
    case Jason.decode(body) do
      {:ok, %{"level" => level, "workflow_id" => workflow_id, "message" => message}} ->
        case LogApp.LogQueue.enqueue(level, workflow_id, message) do
          {:ok, log} ->
            {:ok, log}

          {:error, {:validation_failed, changeset}} ->
            {:error, 422, format_changeset_errors(changeset)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, 422, format_changeset_errors(changeset)}

          {:error, errors} when is_list(errors) ->
            {:error, 422, format_keyword_errors(errors)}

          {:error, :queue_timeout} ->
            {:error, 503, "Queue timeout while processing log"}

          {:error, :queue_unavailable} ->
            {:error, 503, "Queue unavailable"}

          {:error, reason} ->
            Logger.error("Unexpected queue failure: #{inspect(reason)}")
            {:error, 500, "Failed to process log"}
        end

      {:ok, _} ->
        {:error, 400, "Missing required fields: level, workflow_id, message"}

      {:error, _} ->
        {:error, 400, "Invalid JSON"}
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp format_keyword_errors(errors) do
    Enum.reduce(errors, %{}, fn
      {field, {message, opts}}, acc when is_list(opts) ->
        rendered_message =
          Enum.reduce(opts, message, fn {key, value}, msg ->
            String.replace(msg, "%{#{key}}", to_string(value))
          end)

        Map.update(acc, to_string(field), [rendered_message], fn list ->
          list ++ [rendered_message]
        end)

      {field, message}, acc when is_binary(message) ->
        Map.update(acc, to_string(field), [message], fn list ->
          list ++ [message]
        end)

      _, acc ->
        acc
    end)
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
    socket_path = Keyword.get(opts, :socket_path)

    cowboy_opts =
      if socket_path do
        ensure_socket_directory!(socket_path)
        remove_stale_socket(socket_path)

        Logger.info("Starting ingress server on unix socket #{socket_path}")

        [ip: {:local, socket_path}, port: 0]
      else
        port = Keyword.get(opts, :port, 4001)
        Logger.info("Starting ingress server on port #{port}")
        [ip: {127, 0, 0, 1}, port: port]
      end

    {:ok, _pid} = Plug.Cowboy.http(LogApp.Ingress.Router, [], cowboy_opts)

    {:ok, self()}
  end

  defp ensure_socket_directory!(socket_path) do
    socket_path
    |> Path.dirname()
    |> File.mkdir_p!()
  end

  defp remove_stale_socket(socket_path) do
    case File.rm(socket_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> raise "failed to remove stale socket #{socket_path}: #{inspect(reason)}"
    end
  end
end
