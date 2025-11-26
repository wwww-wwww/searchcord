defmodule Searchcord.Cache do
  use Agent

  alias Searchcord.{Guild, User, Message, Channel, Repo}
  import Ecto.Query

  def start_link(_) do
    Agent.start_link(
      fn ->
        guilds =
          Repo.all(Guild)
          |> Repo.preload(:channels)
          |> Enum.map(fn guild ->
            channels =
              guild.channels
              |> Enum.map(fn channel ->
                count =
                  Message
                  |> where([m], m.channel_id == ^channel.id)
                  |> Repo.aggregate(:count)

                oldest =
                  Message
                  |> where([m], m.channel_id == ^channel.id)
                  |> order_by(asc: :created_at)
                  |> limit(1)
                  |> Repo.one()

                {channel.id, %{count: count, oldest: oldest}}
              end)
              |> Map.new()


            {guild.id, %{channels: channels}}
          end)
          |> Map.new()
      end,
      name: __MODULE__
    )
  end

  def get(guild_id) do
    Agent.get(__MODULE__, &(&1 |> Map.get(guild_id)))
  end

  def increment do
    Agent.update(__MODULE__, &(&1 + 1))
  end
end
