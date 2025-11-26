defmodule Searchcord do
  alias Searchcord.{Guild, User, Message, Channel, Repo}
  import Ecto.Query, only: [from: 2]

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
    {:ok, messages} = api(fn -> Nostrum.Api.Channel.messages(channel_id, 100, locator) end)

    users =
      messages
      |> Enum.map(& &1.author)
      |> insert_users(guild_id)

    messages
    |> Enum.each(fn message ->
      case Repo.get(Message, message.id) do
        nil ->
          %Message{
            id: message.id,
            guild_id: guild_id,
            channel_id: channel_id,
            author_id: message.author.id
          }

        m ->
          m
      end
      |> Ecto.Changeset.change(%{
        content: message.content,
        attachments: Enum.map(message.attachments, &(Map.from_struct(&1) |> Jason.encode!())),
        embeds: Enum.map(message.embeds, &(Map.from_struct(&1) |> Jason.encode!())),
        created_at: trunc_time(message.timestamp),
        edited_at: trunc_time(message.edited_timestamp)
      })
      |> Repo.insert_or_update()
    end)

    if after_date != nil and
         Enum.all?(messages, &(DateTime.compare(&1.timestamp, after_date) == :lt)) do
      {length(messages), :finish}
    else
      case messages do
        [message | _] -> {length(messages), {:before, messages |> Enum.at(-1) |> Map.get(:id)}}
        [] -> {0, :finish}
      end
    end
  end

  def download_all_messages(guild_id, channel_id, after_date, :finish, count), do: count

  def download_all_messages(guild_id, channel_id, after_date, locator, acc) do
    {count, locator} = get_messages(guild_id, channel_id, locator, after_date)
    download_all_messages(guild_id, channel_id, after_date, locator, acc + count)
  end

  def download_all_messages(guild_id, channel_id, after_date),
    do: download_all_messages(guild_id, channel_id, after_date, {}, 0)

  def get_guild(guild_id) do
    {:ok, guild} = api(fn -> Nostrum.Api.Guild.get(guild_id) end)

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

    users =
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
end
