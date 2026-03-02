defmodule LogApp do
  @moduledoc """
  LogApp keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias LogApp.IngressClient

  @spec send_log(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def send_log(level, workflow_id, message) do
    IngressClient.send_log(level, workflow_id, message)
  end

  @spec send_info(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def send_info(workflow_id, text_message) do
    IngressClient.send_info(workflow_id, text_message)
  end
end
