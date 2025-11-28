defmodule Searchcord.Repo.Migrations.Create do
  use Ecto.Migration

  def change do
    create table("guilds") do
      add :name, :string
      add :icon, :string
      add :description, :string

      add :roles, {:map, :text}
      add :emojis, {:map, :text}
      add :stickers, {:map, :text}
    end

    create table("users", primary_key: false) do
      add :user_id, :bigint, primary_key: true
      add :guild_id, references("guilds"), primary_key: true, type: :bigint
      add :username, :string
      add :name, :string
      add :nick, :string
      add :avatar, :string
      add :roles, {:array, :bigint}
      add :joined_at, :utc_datetime
      add :bot, :boolean
    end

    create table("channels") do
      add :guild_id, references("guilds"), type: :bigint
      add :type, :integer
      add :position, :integer
      add :name, :string
      add :topic, :string
      add :nsfw, :boolean

      add :parent_id, :bigint
      add :owner_id, references("users", column: :user_id, with: [guild_id: :guild_id]),
        type: :bigint

      add :created_at, :utc_datetime
      add :archived_at, :utc_datetime
    end

    create table("messages") do
      add :guild_id, references("guilds"), type: :bigint
      add :channel_id, references("channels"), type: :bigint

      add :author_id, references("users", column: :user_id, with: [guild_id: :guild_id]),
        type: :bigint

      add :content, :text
      add :attachments, {:array, :text}
      add :embeds, {:array, :text}
      add :created_at, :utc_datetime
      add :edited_at, :utc_datetime

      add :reactions, {:array, :text}
      add :reply_to_id, :bigint
    end
  end
end
