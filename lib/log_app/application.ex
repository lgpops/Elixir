defmodule LogApp.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        LogAppWeb.Telemetry,
        LogApp.Repo,
        {DNSCluster, query: Application.get_env(:log_app, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: LogApp.PubSub},
        LogApp.LogQueue
      ]
      |> maybe_add_ingress()
      |> Kernel.++([
        # Start to serve requests, typically the last entry
        LogAppWeb.Endpoint
      ])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LogApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_ingress(children) do
    if Application.get_env(:log_app, :start_ingress, true) do
      port = Application.get_env(:log_app, :ingress_port, 4001)
      socket_path = Application.get_env(:log_app, :ingress_socket_path)

      ingress_opts =
        if socket_path do
          [socket_path: socket_path]
        else
          [port: port]
        end

      children ++ [{LogApp.Ingress, ingress_opts}]
    else
      children
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LogAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
