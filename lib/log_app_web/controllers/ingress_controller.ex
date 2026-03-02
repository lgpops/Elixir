defmodule LogAppWeb.IngressController do
  use LogAppWeb, :controller

  require Logger

  def create(conn, %{"level" => level, "workflow_id" => workflow_id, "message" => message})
      when is_binary(level) and is_binary(workflow_id) and is_map(message) do
    case LogApp.LogQueue.enqueue(level, workflow_id, message) do
      {:ok, log} ->
        conn
        |> put_status(:created)
        |> json(%{ok: true, id: log.id})

      {:error, {:validation_failed, changeset}} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_changeset_errors(changeset)})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_changeset_errors(changeset)})

      {:error, errors} when is_list(errors) ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: format_keyword_errors(errors)})

      {:error, :queue_timeout} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Queue timeout while processing log"})

      {:error, :queue_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Queue unavailable"})

      {:error, reason} ->
        Logger.error("Unexpected queue failure: #{inspect(reason)}")

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to process log"})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required fields: level, workflow_id, message"})
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
end
