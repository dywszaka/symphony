defmodule Symphony.MixProject do
  use Mix.Project

  def project do
    [
      app: :symphony,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      test_ignore_filters: [~r|test/support/.*\.exs$|],
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Symphony.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.8"},
      {:phoenix, "~> 1.8.0"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.12"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
