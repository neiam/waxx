defmodule Waxx.Repo.Migrations.AddLabelToUsersTokens do
  use Ecto.Migration

  def change do
    alter table(:users_tokens) do
      add :label, :string
    end
  end
end
