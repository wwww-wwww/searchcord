defmodule Searchcord.Cache do
  use Agent

  alias Searchcord.{Guild, User, Message, Channel, Repo}
  import Ecto.Query

  def start_link(_) do
    Agent.start_link(fn -> _reset() end, name: __MODULE__)
  end

  def get(guild_id) do
    Agent.get(__MODULE__, &(&1 |> Map.get(guild_id)))
  end

  def reset() do
    Agent.update(__MODULE__, fn _ -> _reset() end)
  end

  defp _reset() do
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

      {guild.id, %{guild: guild, channels: channels}}
    end)
    |> Map.new()
  end

  def update_guild(guild_id) do
    Agent.update(__MODULE__, fn state ->
      guild =
        Repo.get(Guild, guild_id)
        |> Repo.preload(:channels)

      channels =
        guild
        |> Map.get(:channels)
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

      new_guild = %{guild: guild, channels: channels}

      Map.put(state, guild_id, new_guild)
    end)
  end

  def update_channel(channel_id) do
    channel = Repo.get(Channel, channel_id)

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

    channels =
      Agent.get_and_update(__MODULE__, fn state ->
        guild = Map.get(state, channel.guild_id)

        new_channels =
          guild
          |> Map.get(:channels)
          |> Map.put(channel_id, %{count: count, oldest: oldest})

        new_guild = %{guild | channels: new_channels}

        new_state = Map.put(state, channel.guild_id, new_guild)
        {new_channels, new_state}
      end)

    counts =
      channels
      |> Enum.map(&{elem(&1, 0), elem(&1, 1).count})
      |> Map.new()

    Phoenix.PubSub.broadcast(
      Searchcord.PubSub,
      "update_guild:#{channel.guild_id}",
      {:counts, counts}
    )
  end

  def increment do
    Agent.update(__MODULE__, &(&1 + 1))
  end
end
