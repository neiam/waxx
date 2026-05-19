defmodule Waxx.Repo.Migrations.CreateKanbanTables do
  use Ecto.Migration

  def change do
    ## Reusable workflow templates ----------------------------------------

    create table(:workflow_templates) do
      add :name, :string, null: false
      add :description, :string
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_templates, [:created_by_id])

    create table(:workflow_template_stages) do
      add :template_id, references(:workflow_templates, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false
      add :color, :string

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_template_stages, [:template_id])

    create table(:workflow_template_transitions) do
      add :template_id, references(:workflow_templates, on_delete: :delete_all), null: false

      add :from_stage_id,
          references(:workflow_template_stages, on_delete: :delete_all),
          null: false

      add :to_stage_id,
          references(:workflow_template_stages, on_delete: :delete_all),
          null: false

      add :label, :string

      timestamps(type: :utc_datetime)
    end

    create index(:workflow_template_transitions, [:template_id])

    create unique_index(:workflow_template_transitions, [:from_stage_id, :to_stage_id],
             name: :wt_transitions_from_to_index
           )

    create constraint(:workflow_template_transitions, :wt_no_self_loop,
             check: "from_stage_id <> to_stage_id"
           )

    ## Boards -------------------------------------------------------------

    create table(:boards) do
      add :name, :string, null: false
      add :description, :string
      add :owner_id, references(:users, on_delete: :nilify_all)
      add :template_id, references(:workflow_templates, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:boards, [:owner_id])

    create table(:board_stages) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :position, :integer, null: false
      add :color, :string

      timestamps(type: :utc_datetime)
    end

    create index(:board_stages, [:board_id])

    create table(:board_transitions) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :from_stage_id, references(:board_stages, on_delete: :delete_all), null: false
      add :to_stage_id, references(:board_stages, on_delete: :delete_all), null: false
      add :label, :string

      timestamps(type: :utc_datetime)
    end

    create index(:board_transitions, [:board_id])

    create unique_index(:board_transitions, [:from_stage_id, :to_stage_id],
             name: :b_transitions_from_to_index
           )

    create constraint(:board_transitions, :b_no_self_loop, check: "from_stage_id <> to_stage_id")

    ## Membership + invites ----------------------------------------------

    create table(:board_memberships) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "editor"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:board_memberships, [:board_id, :user_id])
    create index(:board_memberships, [:user_id])

    create constraint(:board_memberships, :board_memberships_role_check,
             check: "role in ('owner','editor','viewer')"
           )

    create table(:board_invites) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :role, :string, null: false, default: "editor"
      add :note, :string
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :consumed_by_id, references(:users, on_delete: :nilify_all)
      add :consumed_at, :utc_datetime
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:board_invites, [:token])
    create index(:board_invites, [:board_id])

    create constraint(:board_invites, :board_invites_role_check,
             check: "role in ('editor','viewer')"
           )

    ## Cards --------------------------------------------------------------

    create table(:cards) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :board_stage_id, references(:board_stages, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :position, :integer, null: false, default: 0
      add :created_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:cards, [:board_id])
    create index(:cards, [:board_stage_id])

    create table(:card_assignees) do
      add :card_id, references(:cards, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:card_assignees, [:card_id, :user_id])
    create index(:card_assignees, [:user_id])
  end
end
