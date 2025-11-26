defmodule SearchcordWeb.GuildLive do
  use SearchcordWeb, :live_view

  alias Searchcord.{Guild, User, Message, Channel, Repo, Cache}
  import Ecto.Query

  def mount(%{"guild" => guild_id, "channel" => channel_id}, _session, socket) do
    guild = Repo.get(Guild, guild_id) |> Repo.preload(:channels)

    categories =
      guild.channels
      |> Enum.filter(&(&1.type == 4))
      |> Repo.preload(channels: [:channels])

    counts =
      Cache.get(guild.id)
      |> Map.get(:channels)
      |> Enum.map(&{elem(&1, 0), elem(&1, 1).count})
      |> Map.new()

    socket =
      socket
      |> assign(guild: guild)
      |> assign(categories: categories)
      |> assign(counts: counts)

    {:noreply, socket} = handle_params(%{"channel" => channel_id}, "", socket)

    {:ok, socket}
  end

  def mount(%{"guild" => guild_id}, session, socket) do
    channel =
      Repo.get(Guild, guild_id)
      |> Repo.preload(:channels)
      |> Map.get(:channels)
      |> Enum.filter(&(&1.type == 0))
      |> Enum.sort_by(& &1.position)
      |> Enum.at(0)

    {:ok, push_navigate(socket, to: "/#{guild_id}/#{channel.id}", replace: true)}
  end

  def handle_params(%{"channel" => channel_id}, _uri, %{assigns: %{guild: guild}} = socket) do
    {channel_id, ""} = Integer.parse(channel_id)

    channel =
      guild.channels
      |> Enum.filter(&(&1.id == channel_id))
      |> Enum.at(0)

    channel_cache = Cache.get(guild.id) |> Map.get(:channels) |> Map.get(channel_id)
    count = channel_cache |> Map.get(:count)
    oldest = channel_cache |> Map.get(:oldests)

    offset_count = trunc(count / 500) * 500

    messages =
      Message
      |> where([m], m.channel_id == ^channel_id)
      |> order_by(asc: :id)
      |> preload([:author])
      |> offset(^offset_count)
      |> limit(500)
      |> Repo.all()

    socket =
      socket
      |> assign(page_title: "#{guild.name} - #{channel.name}")
      |> assign(channel: channel)
      |> assign(messages: messages)
      |> assign(count: count)
      |> assign(oldest: oldest)

    {:noreply, socket}
  end

  def handle_params(%{"channel" => channel_id}, uri, socket) do
    handle_params(%{"channel" => channel_id, "before" => nil}, uri, socket)
  end

  def handle_params(%{"guild" => guild_id}, _uri, socket) do
    {:noreply, socket}
  end
end
