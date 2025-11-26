defmodule Searchcord.Channel do
  use Ecto.Schema

  schema "channels" do
    belongs_to :guild, Searchcord.Guild

    field :type, :integer
    field :position, :integer
    field :name, :string
    field :topic, :string
    field :nsfw, :boolean

    # thread
    belongs_to :parent, Searchcord.Channel
    belongs_to :owner, Searchcord.User, references: :user_id
    field :created_at, :utc_datetime
    field :archived_at, :utc_datetime
    belongs_to :message, Searchcord.Message, foreign_key: :id, define_field: false

    has_many :channels, Searchcord.Channel, foreign_key: :parent_id
    has_many :messages, Searchcord.Message
  end
end

defmodule Searchcord.ChannelDay do
  use Ecto.Schema

  schema "channeldays" do
    has_many :messages, Searchcord.Message
  end
end
