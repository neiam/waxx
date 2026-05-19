defmodule Waxx.Repo.Migrations.CreateTemplateFields do
  use Ecto.Migration

  def change do
    create table(:workflow_template_fields) do
      add :template_id, references(:workflow_templates, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :options, {:array, :string}
      add :show_on_card, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_template_fields, [:template_id])
    create unique_index(:workflow_template_fields, [:template_id, :name])

    create constraint(:workflow_template_fields, :wtf_kind_check,
             check: "kind in ('text','date','datetime','select')"
           )

    create table(:board_fields) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :kind, :string, null: false
      add :options, {:array, :string}
      add :show_on_card, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:board_fields, [:board_id])
    create unique_index(:board_fields, [:board_id, :name])

    create constraint(:board_fields, :bf_kind_check,
             check: "kind in ('text','date','datetime','select')"
           )

    create table(:card_field_values) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :board_field_id, references(:board_fields, on_delete: :delete_all), null: false
      add :value, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:card_field_values, [:card_id, :board_field_id])
    create index(:card_field_values, [:board_field_id])
  end
end
