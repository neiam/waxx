defmodule Waxx.Repo.Migrations.CreateLabels do
  use Ecto.Migration

  def change do
    create table(:workflow_template_labels) do
      add :template_id, references(:workflow_templates, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :color, :string

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_template_labels, [:template_id])
    create unique_index(:workflow_template_labels, [:template_id, :name])

    create table(:board_labels) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :color, :string

      timestamps(type: :utc_datetime)
    end

    create index(:board_labels, [:board_id])
    create unique_index(:board_labels, [:board_id, :name])

    create table(:card_labels) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :board_label_id, references(:board_labels, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:card_labels, [:card_id, :board_label_id])
    create index(:card_labels, [:board_label_id])
  end
end
