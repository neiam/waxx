defmodule Waxx.Repo.Migrations.CreateBoardActivities do
  use Ecto.Migration

  def change do
    create table(:board_activities) do
      add :board_id, references(:boards, on_delete: :delete_all), null: false
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :card_id, references(:cards, on_delete: :nilify_all)
      add :action, :string, null: false
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:board_activities, [:board_id, :inserted_at])
    create index(:board_activities, [:card_id])
    create index(:board_activities, [:actor_id])
  end
end
