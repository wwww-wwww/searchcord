defmodule Searchcord.Repo.Migrations.AddTsvector do
  use Ecto.Migration

  def change do
    execute(
      "CREATE EXTENSION IF NOT EXISTS \"pg_trgm\"",
      "DROP EXTENSION IF EXISTS \"pg_trgm\""
    )

    execute """
      ALTER TABLE messages
        ADD COLUMN searchable tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english', coalesce(content, ''))
        ) STORED;
    """

    create index("messages", ["searchable"],
             name: :messages_searchable_index,
             using: "GIN"
           )
  end
end
