defmodule Waxx.Repo.Migrations.AddSubboardScopedLabels do
  use Ecto.Migration

  # Join table letting a board label be restricted to one or more subboards.
  # A label with NO rows here is board-wide (applies to every card); a label
  # with rows applies only to cards living in those subboards.
  def change do
    create table(:board_label_subboards) do
      add :board_label_id, references(:board_labels, on_delete: :delete_all), null: false
      add :subboard_id, references(:board_subboards, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:board_label_subboards, [:board_label_id, :subboard_id])
    create index(:board_label_subboards, [:subboard_id])
  end
end
