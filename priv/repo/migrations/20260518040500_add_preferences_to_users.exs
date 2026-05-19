defmodule Waxx.Repo.Migrations.AddPreferencesToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :preferences, :map, default: %{}, null: false
    end
  end
end
