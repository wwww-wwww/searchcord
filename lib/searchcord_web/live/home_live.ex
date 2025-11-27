defmodule SearchcordWeb.HomeLive do
  use SearchcordWeb, :live_view

  alias Searchcord.{Repo, Guild}

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(guilds: Repo.all(Guild))
      |> assign(queue: Searchcord.UpdateQueue.get().items)

    Phoenix.PubSub.subscribe(Searchcord.PubSub, "update_queue")

    {:ok, socket}
  end

  def handle_event("add_guild", %{"guild_id" => guild_id}, socket) do
    case Integer.parse(guild_id) do
      {guild_id, ""} ->
        socket =
          case Repo.get(Guild, guild_id) do
            nil ->
              case Searchcord.get_guild(guild_id) do
                {:error,
                 %Nostrum.Error.ApiError{
                   response: resp
                 }} ->
                  socket |> put_flash(:error, inspect(resp))

                guild ->
                  socket
                  |> put_flash(:info, "Added guild #{guild.name}")
                  |> assign(guilds: Repo.all(Guild))
              end

            %{name: name} ->
              put_flash(socket, :error, "Guild #{name} already added")
          end

        {:noreply, socket}

      _err ->
        {:noreply, put_flash(socket, :error, "Failed to parse server id")}
    end
  end

  def handle_info({:update_queue, items}, socket) do
    socket = socket |> assign(queue: items)
    {:noreply, socket}
  end
end
