defmodule LogAppClient do
  @moduledoc """
  Elixir SDK for sending logs to a LogApp ingress endpoint.

  ## Quick start

      client = LogAppClient.new(base_url: "http://localhost:4001")

      LogAppClient.send_info(
        client,
        "550e8400-e29b-41d4-a716-446655440000",
        "hello from elixir sdk"
      )
  """

  @type t :: %__MODULE__{
          base_url: String.t(),
          timeout: non_neg_integer(),
          headers: [{String.t(), String.t()}]
        }

  defstruct base_url: "http://localhost:4001",
            timeout: 5_000,
            headers: []

  @type result :: {:ok, map()} | {:error, term()}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      base_url: Keyword.get(opts, :base_url, "http://localhost:4001"),
      timeout: Keyword.get(opts, :timeout, 5_000),
      headers: Keyword.get(opts, :headers, [])
    }
  end

  @spec send_info(t(), String.t(), String.t()) :: result()
  def send_info(%__MODULE__{} = client, workflow_id, text)
      when is_binary(workflow_id) and is_binary(text) do
    send_log(client, "info", workflow_id, %{"message" => text})
  end

  @spec send_log(t(), String.t(), String.t(), map()) :: result()
  def send_log(%__MODULE__{} = client, level, workflow_id, message)
      when is_binary(level) and is_binary(workflow_id) and is_map(message) do
    request_body = %{
      level: level,
      workflow_id: workflow_id,
      message: message
    }

    url = client.base_url <> "/logs"

    case Req.post(
           url: url,
           json: request_body,
           receive_timeout: client.timeout,
           headers: [{"content-type", "application/json"} | client.headers]
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
