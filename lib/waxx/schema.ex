defmodule Waxx.Schema do
  @moduledoc """
  Shared `use` macro for application schemas. Defaults every schema to
  UUIDv7 primary and foreign keys via `Waxx.UUIDv7`.

      defmodule Waxx.Accounts.User do
        use Waxx.Schema
        schema "users" do
          ...
        end
      end
  """

  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      @primary_key {:id, Waxx.UUIDv7, autogenerate: true}
      @foreign_key_type Waxx.UUIDv7
    end
  end
end
