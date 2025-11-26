defmodule Searchcord.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    bot_options = %{
      name: Searchcord,
      wrapped_token: fn -> System.fetch_env!("BOT_TOKEN") end
    }

    children = [
      SearchcordWeb.Telemetry,
      Searchcord.Repo,
      {DNSCluster, query: Application.get_env(:searchcord, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Searchcord.PubSub},
      Searchcord.Cache,
      {Nostrum.Api.RatelimiterGroup, bot_options},
      {Nostrum.Api.Ratelimiter, bot_options},
      SearchcordWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Searchcord.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SearchcordWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
