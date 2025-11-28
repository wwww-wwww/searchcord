defmodule SearchcordWeb.GuildLive do
  use SearchcordWeb, :live_view

  alias Searchcord.{Guild, User, Message, Channel, Repo, Cache, Search}
  import Ecto.Query

  @limit 500

  def mount(%{"guild" => guild_id}, session, socket) do
    case Repo.get(Guild, guild_id) |> Repo.preload(:channels) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Guild doesn't exist")
         |> push_navigate(to: ~p"/")}

      guild ->
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
          |> assign(limit: @limit)
          |> assign(channel: nil)
          |> assign(search: nil)
          |> assign(query: "")

        Phoenix.PubSub.subscribe(Searchcord.PubSub, "update_guild:#{guild.id}")

        {:ok, socket}
    end
  end

  def handle_params(%{"query" => query}, _uri, socket) do
    guild = socket.assigns.guild

    search = Search.search_full(guild.id, query)

    socket =
      socket
      |> assign(search: search)
      |> assign(query: query)

    {:noreply, socket}
  end

  def handle_params(%{"channel" => channel_id, "offset" => offset}, _uri, socket) do
    {channel_id, ""} =
      if is_number(channel_id), do: {channel_id, ""}, else: Integer.parse(channel_id)

    {offset, ""} = if is_number(offset), do: {offset, ""}, else: Integer.parse(offset)

    offset = offset - 1

    guild = socket.assigns.guild

    Cache.get(guild.id)
    |> Map.get(:channels)
    |> Map.get(channel_id)
    |> case do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel doesn't exist")
         |> push_navigate(to: ~p"/#{guild.id}")}

      channel_cache ->
        channel =
          guild.channels
          |> Enum.filter(&(&1.id == channel_id))
          |> Enum.at(0)

        count = channel_cache |> Map.get(:count)
        oldest = channel_cache |> Map.get(:oldest)

        messages =
          Message
          |> where([m], m.channel_id == ^channel_id)
          |> order_by(asc: :id)
          |> offset(^offset)
          |> limit(@limit)
          |> preload([:author])
          |> Repo.all()
          |> Search.chunk_by(& &1.author_id)

        channel = %{channel: channel, messages: messages, count: count, oldest: oldest}

        socket =
          socket
          |> assign(page_title: "#{guild.name} - #{channel.channel.name}")
          |> assign(channel: channel)
          |> assign(search: nil)

        {:noreply, socket}
    end
  end

  def handle_params(%{"channel" => channel_id}, uri, %{assigns: %{guild: guild}} = socket) do
    {channel_id, ""} = Integer.parse(channel_id)

    Cache.get(guild.id)
    |> Map.get(:channels)
    |> Map.get(channel_id)
    |> case do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Channel doesn't exist")
         |> push_navigate(to: ~p"/#{guild.id}")}

      channel ->
        count = Map.get(channel, :count)
        offset = trunc(count / @limit) * @limit + 1

        handle_params(%{"channel" => channel_id, "offset" => offset}, uri, socket)
    end
  end

  def handle_params(%{"message" => message_id, "guild" => guild_id}, _uri, socket) do
    {message_id, ""} = Integer.parse(message_id)
    message = Repo.get(Message, message_id)

    n =
      Message
      |> where([m], m.channel_id == ^message.channel_id)
      |> order_by(asc: :id)
      |> Repo.all()
      |> Enum.with_index()
      |> Enum.filter(&(elem(&1, 0).id == message_id))
      |> Enum.at(0)
      |> elem(1)
      |> Kernel./(@limit)
      |> trunc()
      |> Kernel.*(@limit)

    {:noreply,
     push_navigate(socket,
       to: ~p"/#{guild_id}/#{message.channel_id}/#{n}" <> "\#message_#{message_id}"
     )}
  end

  def handle_params(%{"guild" => _}, _uri, socket) do
    socket =
      socket
      |> assign(channel: nil)
      |> assign(search: nil)

    {:noreply, socket}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, push_patch(socket, to: ~p"/#{socket.assigns.guild.id}/search/#{query}")}
  end

  def handle_event("update-channels", _, socket) do
    if Searchcord.UpdateQueue.get().items |> length() == 0 do
      Searchcord.UpdateQueue.push({&Searchcord.get_channels/1, [socket.assigns.guild.id]})
    end

    {:noreply, socket}
  end

  def handle_event("update-messages", _, socket) do
    if Searchcord.UpdateQueue.get().items |> length() == 0 do
      socket.assigns.guild
      |> Repo.preload(:channels)
      |> Map.get(:channels)
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn channel ->
        Searchcord.UpdateQueue.push({&Searchcord.update_channel_messages/1, [channel.id]})
      end)
    end

    {:noreply, socket}
  end

  def handle_info({:counts, counts}, socket) do
    socket = socket |> assign(counts: counts)
    {:noreply, socket}
  end
end
