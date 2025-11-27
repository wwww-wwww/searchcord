defmodule Searchcord do
  alias Searchcord.{Guild, User, Message, Channel, Repo, Cache}
  import Ecto.Query

  def api(fun), do: Nostrum.Bot.with_bot(Searchcord, fun)

  defp insert_users(users, guild_id) do
    users
    |> Enum.uniq_by(& &1.id)
    |> Enum.filter(fn %{id: user_id} ->
      not Repo.exists?(from u in User, where: u.user_id == ^user_id and u.guild_id == ^guild_id)
    end)
    |> Enum.each(fn user ->
      user =
        case api(fn -> Nostrum.Api.User.get(user.id) end) do
          {:ok, user} ->
            user

          {:error,
           %Nostrum.Error.ApiError{
             status_code: 404,
             response: %{code: 10013, message: "Unknown User"}
           }} ->
            user
        end

      {nick, roles, joined_at} =
        case api(fn -> Nostrum.Api.Guild.member(guild_id, user.id) end) do
          {:ok, member} -> {member.nick, member.roles, DateTime.from_unix!(member.joined_at)}
          {:error, _} -> {nil, [], nil}
        end

      case Repo.get_by(User, user_id: user.id, guild_id: guild_id) do
        nil -> %User{user_id: user.id, guild_id: guild_id}
        user -> user
      end
      |> Ecto.Changeset.change(%{
        username: user.username,
        name: user.global_name,
        nick: nick,
        avatar: user.avatar,
        roles: roles,
        joined_at: joined_at,
        bot: user.bot
      })
      |> Repo.insert_or_update()
    end)
  end

  def get_messages(guild_id, channel_id, locator, after_date) do
    messages =
      case api(fn -> Nostrum.Api.Channel.messages(channel_id, 100, locator) end) do
        {:ok, messages} ->
          messages

        {:error,
         %Nostrum.Error.ApiError{
           status_code: 403,
           response: %{code: 50001, message: "Missing Access"}
         }} ->
          []
      end

    messages
    |> Enum.map(& &1.author)
    |> insert_users(guild_id)

    count =
      messages
      |> Enum.map(fn message ->
        case Repo.get(Message, message.id) do
          nil ->
            %Message{
              id: message.id,
              guild_id: guild_id,
              channel_id: channel_id,
              author_id: message.author.id,
              content: message.content,
              attachments:
                Enum.map(message.attachments, &(Map.from_struct(&1) |> Jason.encode!())),
              embeds: Enum.map(message.embeds, &(Map.from_struct(&1) |> Jason.encode!())),
              created_at: trunc_time(message.timestamp),
              edited_at: trunc_time(message.edited_timestamp)
            }
            |> Repo.insert()

            1

          m ->
            m
            |> Ecto.Changeset.change(%{
              content: message.content,
              attachments:
                Enum.map(message.attachments, &(Map.from_struct(&1) |> Jason.encode!())),
              embeds: Enum.map(message.embeds, &(Map.from_struct(&1) |> Jason.encode!())),
              edited_at: trunc_time(message.edited_timestamp)
            })
            |> Repo.update()

            0
        end
      end)
      |> Enum.sum()

    Cache.update_channel(channel_id)

    if after_date != nil and
         Enum.all?(messages, &(DateTime.compare(&1.timestamp, after_date) == :lt)) do
      {count, :finish}
    else
      if length(messages) > 0,
        do: {count, {:before, messages |> Enum.at(-1) |> Map.get(:id)}},
        else: {0, :finish}
    end
  end

  def download_all_messages(_guild_id, _channel_id, _after_date, :finish, count), do: count

  def download_all_messages(guild_id, channel_id, after_date, locator, acc) do
    {count, locator} = get_messages(guild_id, channel_id, locator, after_date)
    download_all_messages(guild_id, channel_id, after_date, locator, acc + count)
  end

  def download_all_messages(guild_id, channel_id, after_date),
    do: download_all_messages(guild_id, channel_id, after_date, {}, 0)

  def get_guild(guild_id) do
    case api(fn -> Nostrum.Api.Guild.get(guild_id) end) do
      {:ok, guild} ->
        roles =
          guild.roles
          |> Map.values()
          |> Enum.map(&{&1.id, &1 |> Map.from_struct() |> Jason.encode!()})
          |> Map.new()

        emojis =
          guild.emojis
          |> Enum.map(&{&1.id, &1 |> Map.from_struct() |> Jason.encode!()})
          |> Map.new()

        stickers =
          guild.stickers
          |> Enum.map(&{&1.id, &1 |> Map.from_struct() |> Jason.encode!()})
          |> Map.new()

        {:ok, guild} =
          %Guild{
            id: guild.id,
            name: guild.name,
            icon: guild.icon,
            description: guild.description,
            roles: roles,
            emojis: emojis,
            stickers: stickers
          }
          |> Repo.insert()
          |> IO.inspect()

        Cache.update_guild(guild.id)

        guild

      err ->
        err
    end
  end

  def download_all(after_date) do
    Repo.all(Channel)
    |> Enum.filter(&(&1.type != 4))
    |> Enum.each(&download_all_messages(&1.guild_id, &1.id, after_date))
  end

  def download_all_old() do
    Repo.all(Channel)
    |> Enum.filter(&(&1.type != 4))
    |> Enum.each(fn channel ->
      Message
      |> where([m], m.channel_id == ^channel.id)
      |> order_by(asc: :created_at)
      |> limit(1)
      |> Repo.one()
      |> case do
        nil ->
          download_all_messages(channel.guild_id, channel.id, nil)

        oldest ->
          download_all_messages(channel.guild_id, channel.id, nil, {:before, oldest.id}, 0)
      end
    end)
  end

  defp trunc_time(nil), do: nil
  defp trunc_time(time), do: DateTime.truncate(time, :second)

  def get_channels(guild_id) do
    {:ok, channels} = api(fn -> Nostrum.Api.Guild.channels(guild_id) end)
    {:ok, %{threads: threads}} = api(fn -> Nostrum.Api.Thread.list(guild_id) end)

    archived_threads =
      channels
      |> Enum.filter(&(&1.type == 0))
      |> Enum.reduce([], fn %{id: id}, acc ->
        try do
          {:ok, %{threads: archived_threads}} =
            api(fn -> Nostrum.Api.Thread.public_archived_threads(id) end)

          acc ++ archived_threads
        rescue
          MatchError -> acc
        end
      end)

    channels =
      Enum.map(
        channels,
        &%{
          id: &1.id,
          guild_id: &1.guild_id,
          type: &1.type,
          position: &1.position,
          name: &1.name,
          topic: &1.topic,
          nsfw: &1.nsfw,
          parent_id: &1.parent_id
        }
      )

    threads =
      Enum.map(
        threads ++ archived_threads,
        &%{
          id: &1.id,
          guild_id: &1.guild_id,
          type: &1.type,
          position: &1.position,
          name: &1.name,
          topic: &1.topic,
          nsfw: &1.nsfw,
          parent_id: &1.parent_id,
          owner_id: &1.owner_id,
          created_at: trunc_time(&1.thread_metadata.create_timestamp),
          archived_at: trunc_time(&1.thread_metadata.archive_timestamp)
        }
      )

    threads
    |> Enum.map(&%{id: &1.owner_id})
    |> insert_users(guild_id)

    (channels ++ threads)
    |> Enum.sort_by(&(&1.type != 4))
    |> Enum.each(fn channel ->
      case Repo.get(Channel, channel.id) do
        nil -> %Channel{id: channel.id}
        channel -> channel
      end
      |> Ecto.Changeset.change(channel)
      |> Repo.insert_or_update()
    end)
  end

  def update_channel_messages(channel_id) do
    channel = Repo.get(Channel, channel_id)

    count =
      Message
      |> where([m], m.channel_id == ^channel_id)
      |> order_by(desc: :created_at)
      |> limit(1)
      |> Repo.one()
      |> case do
        nil ->
          download_all_messages(channel.guild_id, channel_id, nil)

        newest ->
          download_all_messages(channel.guild_id, channel_id, newest.created_at)
      end

    count
  end

  def update_guild_messages(guild) do
    guild
    |> Repo.preload(:channels)
    |> Map.get(:channels)
    |> Enum.map(&update_channel_messages(&1))
    |> Enum.sum()
  end

  def update_all() do
    Repo.all(Guild)
    |> Enum.each(fn guild ->
      get_channels(guild.id)
      Cache.update_guild(guild.id)
    end)

    Repo.all(Channel)
    |> Enum.filter(&(&1.type != 4))
    |> Enum.map(fn channel ->
      update_channel_messages(channel)
    end)
    |> Enum.sum()
  end

  def delete_guild() do
    Repo.one(Guild) |> Repo.delete()
  end
end
