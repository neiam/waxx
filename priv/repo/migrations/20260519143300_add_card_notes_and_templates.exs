defmodule Waxx.Repo.Migrations.AddCardNotesAndTemplates do
  use Ecto.Migration

  def change do
    create table(:card_notes) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :board_stage_id, references(:board_stages, on_delete: :nilify_all)
      add :body, :text, null: false
      add :kind, :string, null: false, default: "note"
      add :done, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:card_notes, [:card_id])
    create index(:card_notes, [:board_stage_id])

    create constraint(:card_notes, :card_notes_kind_check, check: "kind in ('note','todo')")

    create table(:card_templates) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :snapshot, :map, null: false, default: %{}
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:card_templates, [:board_id])
    create unique_index(:card_templates, [:board_id, :name])
  end
end
