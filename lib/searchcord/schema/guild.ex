defmodule Searchcord.Guild do
  use Ecto.Schema

  schema "guilds" do
    field :name, :string
    field :icon, :string
    field :description, :string

    field :roles, {:map, :string}
    field :emojis, {:map, :string}
    field :stickers, {:map, :string}

    has_many :channels, Searchcord.Channel
  end
end
