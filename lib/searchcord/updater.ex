defmodule Searchcord.Updater do
  use GenServer

  def init(_) do
    {:ok, {}}
  end

  def start_link(_) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def wake() do
    GenServer.cast(__MODULE__, :wake)
  end

  def handle_cast(:wake, state) do
    case Searchcord.UpdateQueue.pop() do
      nil ->
        Phoenix.PubSub.broadcast(Searchcord.PubSub, "update_queue", {:update_queue, []})
        Searchcord.UpdateQueue.updating(false)

      {{fun, args}, items} ->
        Phoenix.PubSub.broadcast(Searchcord.PubSub, "update_queue", {:update_queue, items})
        Searchcord.UpdateQueue.updating(true)
        Kernel.apply(fun, args)

        GenServer.cast(__MODULE__, :wake)
    end

    {:noreply, state}
  end
end

defmodule Searchcord.UpdateQueue do
  use Agent

  defstruct updating: false, items: []

  def start_link(_) do
    Agent.start_link(fn -> %__MODULE__{} end, name: __MODULE__)
  end

  def get(), do: Agent.get(__MODULE__, & &1)

  def push(fun) do
    Agent.update(__MODULE__, &%{&1 | items: &1.items ++ [fun]})
    Searchcord.Updater.wake()
  end

  def updating(b), do: Agent.update(__MODULE__, &%{&1 | updating: b})

  def pop() do
    Agent.get_and_update(__MODULE__, fn state ->
      case state.items do
        [item | items] -> {{item, items}, %{state | items: items}}
        [] -> {nil, state}
      end
    end)
  end
end
