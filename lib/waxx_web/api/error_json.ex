defmodule WaxxWeb.Api.ErrorJSON do
  @moduledoc """
  Renders the uniform error envelope used by every `/api/v1` endpoint:

      { "error": { "code": "...", "message": "...", "details": {...} } }

  See `docs/android.md` § 3 for the contract.
  """

  def error(%{error: %{code: code, message: message} = err}) do
    base = %{code: code, message: message}

    case Map.get(err, :details) do
      nil -> %{error: base}
      details -> %{error: Map.put(base, :details, details)}
    end
  end

  @doc """
  Converts a changeset into the `details` map used by `validation_failed`
  errors: `%{field_name => ["error", ...]}`.
  """
  def changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
