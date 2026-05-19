defmodule Waxx.Repo.Migrations.CreateSubboards do
  use Ecto.Migration

  def change do
    create table(:board_subboards) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:board_subboards, [:board_id])
    create unique_index(:board_subboards, [:board_id, :name])

    alter table(:cards) do
      add :subboard_id, references(:board_subboards, on_delete: :nilify_all, type: :binary_id)
    end

    create index(:cards, [:subboard_id])
  end
end
