defmodule Waxx.Repo.Migrations.AddCardBackgrounds do
  use Ecto.Migration

  # A pasted background image for a single card. Kept in its own table
  # (one row per card) rather than a column on `cards` so the image bytes
  # never ride along with the board's card list — they're only loaded when
  # a card is expanded.
  def change do
    create table(:card_backgrounds) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :content_type, :string, null: false
      add :image_data, :binary, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:card_backgrounds, [:card_id])
  end
end
