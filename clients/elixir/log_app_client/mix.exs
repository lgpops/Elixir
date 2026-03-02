defmodule LogAppClient.MixProject do
  use Mix.Project

  def project do
    [
      app: :log_app_client,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client SDK for sending logs to LogApp ingress",
      package: package(),
      source_url: "https://github.com/lgpops/Elixir"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/lgpops/Elixir"}
    ]
  end
end
