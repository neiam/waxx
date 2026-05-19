defmodule Waxx.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :email, :citext
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime
      add :kind, :string, null: false, default: "registered"
      add :display_name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email], where: "email IS NOT NULL", name: :users_email_index)
    create constraint(:users, :users_kind_check, check: "kind in ('registered','anonymous')")

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
