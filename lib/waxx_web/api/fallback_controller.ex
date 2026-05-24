defmodule WaxxWeb.Api.FallbackController do
  @moduledoc """
  Translates `{:error, reason}` tuples returned from controller actions
  into the JSON error envelope defined by `WaxxWeb.Api.ErrorJSON`.

  Controllers opt in with `action_fallback WaxxWeb.Api.FallbackController`
  and then return `{:error, reason}` from their actions without manually
  handling the response.
  """

  use Phoenix.Controller, formats: [:json]

  alias WaxxWeb.Api.ErrorJSON

  def call(conn, {:error, :not_found}) do
    respond(conn, :not_found, "not_found", "Resource not found.")
  end

  def call(conn, {:error, :unauthenticated}) do
    respond(conn, :unauthorized, "unauthenticated", "Missing or invalid token.")
  end

  def call(conn, {:error, :forbidden}) do
    respond(conn, :forbidden, "forbidden", "You do not have access to this resource.")
  end

  def call(conn, {:error, :invalid_transition, details}) do
    respond(
      conn,
      :unprocessable_entity,
      "invalid_transition",
      "That move is not allowed by the workflow.",
      details
    )
  end

  def call(conn, {:error, :invalid_transition}) do
    respond(
      conn,
      :unprocessable_entity,
      "invalid_transition",
      "That move is not allowed by the workflow."
    )
  end

  def call(conn, {:error, :conflict}) do
    respond(conn, :conflict, "conflict", "The resource has changed since you last read it.")
  end

  def call(conn, {:error, :rate_limited}) do
    respond(conn, :too_many_requests, "rate_limited", "Too many requests. Please slow down.")
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    respond(
      conn,
      :unprocessable_entity,
      "validation_failed",
      "The request body failed validation.",
      ErrorJSON.changeset_errors(changeset)
    )
  end

  def call(conn, {:error, code}) when is_atom(code) do
    respond(conn, :unprocessable_entity, Atom.to_string(code), humanise(code))
  end

  defp respond(conn, status, code, message, details \\ nil) do
    error = %{code: code, message: message}
    error = if details, do: Map.put(error, :details, details), else: error

    conn
    |> put_status(status)
    |> put_view(json: ErrorJSON)
    |> render(:error, error: error)
  end

  defp humanise(code),
    do: code |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
end
