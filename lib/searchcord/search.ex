defmodule Searchcord.Search do
  alias Searchcord.{Message, Repo, Cache}
  import Ecto.Query

  def chunk_by(enumerable, fun) do
    {chunks, chunk, _} =
      Enum.reduce_while(
        enumerable,
        {[], [], nil},
        fn m, {acc, chunk, var} ->
          mvar = fun.(m)

          {acc, chunk} =
            if mvar == var do
              {acc, chunk ++ [m]}
            else
              {acc ++ [chunk], [m]}
            end

          {:cont, {acc, chunk, mvar}}
        end
      )

    (chunks ++ [chunk])
    |> Enum.filter(&(length(&1) > 0))
  end

  def search(guild_id, text) do
    IO.inspect(text)

    query =
      Message
      |> where([m], m.guild_id == ^guild_id)
      |> where(fragment("searchable @@ (? || ':*')::tsquery", ^text))
      |> order_by(desc: :id)

    channels =
      Cache.get(guild_id)
      |> Map.get(:guild)
      |> Map.get(:channels)

    time_start = :os.system_time(:millisecond)

    count = Repo.aggregate(query, :count)

    results =
      query
      |> limit(500)
      |> preload([:author])
      |> Repo.all()

    time_db = :os.system_time(:millisecond)

    results =
      results
      |> chunk_by(& &1.channel_id)
      |> Enum.map(fn e ->
        channel_id = e |> Enum.at(0) |> Map.get(:channel_id)

        channel =
          channels
          |> Enum.filter(&(&1.id == channel_id))
          |> Enum.at(0)

        {channel, chunk_by(e, & &1.author_id)}
      end)

    time_enum = :os.system_time(:millisecond)

    %{
      count: count,
      results: results,
      duration_db: time_db - time_start,
      duration_enum: time_enum - time_db
    }
  end

  def search_full(guild_id, text) do
    query =
      Message
      |> where([m], m.guild_id == ^guild_id)
      |> where([m], fragment("? ~* ?", m.content, ^text))
      |> order_by(desc: :id)

    channels =
      Cache.get(guild_id)
      |> Map.get(:guild)
      |> Map.get(:channels)

    time_start = :os.system_time(:millisecond)

    count = Repo.aggregate(query, :count)

    results =
      query
      |> limit(500)
      |> preload([:author])
      |> Repo.all()

    time_db = :os.system_time(:millisecond)

    results =
      results
      |> chunk_by(& &1.channel_id)
      |> Enum.map(fn e ->
        channel_id = e |> Enum.at(0) |> Map.get(:channel_id)

        channel =
          channels
          |> Enum.filter(&(&1.id == channel_id))
          |> Enum.at(0)

        {channel, chunk_by(e, & &1.author_id)}
      end)

    time_enum = :os.system_time(:millisecond)

    %{
      count: count,
      results: results,
      duration_db: time_db - time_start,
      duration_enum: time_enum - time_db
    }
  end
end
