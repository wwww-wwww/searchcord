defmodule SearchcordWeb.HomeLive do
  use SearchcordWeb, :live_view

  alias Searchcord.{Repo, Guild}

  def mount(params, _session, socket) do
    IO.inspect(params)

    socket =
      socket
      |> assign(guilds: Repo.all(Guild))

    # IO.inspect(session)
    {:ok, socket}
  end
end
