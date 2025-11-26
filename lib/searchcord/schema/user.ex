defmodule Searchcord.User do
  use Ecto.Schema

  @primary_key false
  schema "users" do
    field :user_id, :integer, primary_key: true
    belongs_to :guild, Searchcord.Guild, primary_key: true, type: :integer
    field :username, :string
    field :name, :string
    field :nick, :string
    field :avatar, :string
    field :roles, {:array, :integer}
    field :joined_at, :utc_datetime
    field :bot, :boolean

    has_many :messages, Searchcord.Message, references: :user_id
  end
end
