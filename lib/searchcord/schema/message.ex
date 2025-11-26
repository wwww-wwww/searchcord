defmodule Searchcord.Message do
  use Ecto.Schema

  schema "messages" do
    belongs_to :guild, Searchcord.Guild
    belongs_to :channel, Searchcord.Channel
    belongs_to :author, Searchcord.User, references: :user_id
    field :content, :string
    field :attachments, {:array, :string}
    field :embeds, {:array, :string}
    field :created_at, :utc_datetime
    field :edited_at, :utc_datetime
  end
end
