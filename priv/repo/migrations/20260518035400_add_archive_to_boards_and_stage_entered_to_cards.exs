defmodule Waxx.Repo.Migrations.AddArchiveToBoardsAndStageEnteredToCards do
  use Ecto.Migration

  def change do
    alter table(:boards) do
      add :archive_terminal_after_days, :integer, default: 7
    end

    alter table(:cards) do
      add :stage_entered_at, :utc_datetime
    end

    # Backfill: existing cards "entered their current stage" at insertion time.
    execute(
      "UPDATE cards SET stage_entered_at = inserted_at WHERE stage_entered_at IS NULL",
      ""
    )

    alter table(:cards) do
      modify :stage_entered_at, :utc_datetime, null: false
    end
  end
end
