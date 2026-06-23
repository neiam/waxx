defmodule WaxxWeb.Api.V1.CardController do
  @moduledoc """
  Card writes (Phase 4 — core surface).

      POST   /api/v1/boards/:board_id/cards   {title, description?, board_stage_id?,
                                               subboard_id?, position?}
      PATCH  /api/v1/cards/:id                {title?, description?}
      POST   /api/v1/cards/:id/move           {board_stage_id, position?}
      DELETE /api/v1/cards/:id

  All routes require owner or editor membership on the card's board.
  Non-members get 404 (we don't leak existence); members without edit
  permission get 403.

  Mutations run through the existing `Waxx.Kanban` context, so the
  activity log + PubSub broadcasts that drive the LiveView + the Phase 3
  channel push happen automatically.
  """

  use WaxxWeb, :controller

  alias Waxx.{Accounts, Kanban, Repo}
  alias Waxx.Kanban.{BoardField, BoardLabel, Card, Subboard}
  alias WaxxWeb.Api.V1.BoardJSON

  action_fallback WaxxWeb.Api.FallbackController

  ## Create -------------------------------------------------------------

  def create(conn, %{"board_id" => board_id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, board} <- fetch_editable_board(board_id, user) do
      attrs = Map.drop(params, ["board_id"])

      case Kanban.create_card(board, user, attrs) do
        {:ok, card} ->
          conn
          |> put_status(:created)
          |> json(BoardJSON.card_response(reload_card(card)))

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  ## Update -------------------------------------------------------------

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(id, user) do
      attrs = Map.take(params, ["title", "description"])

      case Kanban.update_card(card, attrs, actor: user) do
        {:ok, updated} ->
          json(conn, BoardJSON.card_response(reload_card(updated)))

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  ## Move ---------------------------------------------------------------

  def move(conn, %{"id" => id} = params) do
    user = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(id, user),
         {:ok, target_stage_id} <- require_param(params, "board_stage_id") do
      target_index = parse_position(params["position"])

      with {:ok, moved} <- Kanban.move_card(card, target_stage_id, target_index, actor: user),
           {:ok, final} <- apply_subboard_change(moved, params, user) do
        json(conn, BoardJSON.card_response(reload_card(final)))
      else
        {:error, reason}
        when reason in [:invalid_transition, :invalid_stage, :invalid_subboard] ->
          {:error, reason}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # Optional second leg of a move: re-assign the card's subboard. Omitting
  # the key leaves it alone; `null` clears it to the default row.
  defp apply_subboard_change(card, params, user) do
    if Map.has_key?(params, "subboard_id") do
      case params["subboard_id"] do
        nil ->
          Kanban.set_card_subboard(card, nil, actor: user)

        id when is_binary(id) ->
          case Repo.get(Subboard, id) do
            nil -> {:error, :not_found}
            %Subboard{} = sb -> Kanban.set_card_subboard(card, sb, actor: user)
          end

        _ ->
          {:error, :validation_failed}
      end
    else
      {:ok, card}
    end
  end

  ## Delete -------------------------------------------------------------

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(id, user),
         {:ok, _} <- Kanban.delete_card(card, actor: user) do
      send_resp(conn, :no_content, "")
    end
  end

  ## Show (single card with notes) -------------------------------------

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_visible_card(id, user) do
      json(conn, BoardJSON.card_detail_response(reload_card_with_notes(card)))
    end
  end

  ## Labels -------------------------------------------------------------

  def toggle_label(conn, %{"id" => card_id, "label_id" => label_id}) do
    user = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(card_id, user),
         %BoardLabel{} = label <- Repo.get(BoardLabel, label_id) || {:error, :not_found},
         {:ok, _} <- Kanban.toggle_card_label(card, label, actor: user) do
      json(conn, BoardJSON.card_response(reload_card(card)))
    else
      {:error, :invalid_label} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Fields -------------------------------------------------------------

  def set_field(conn, %{"id" => card_id, "field_id" => field_id} = params) do
    user = conn.assigns.current_scope.user
    raw_value = Map.get(params, "value")

    with {:ok, card} <- fetch_editable_card(card_id, user),
         %BoardField{} = field <- Repo.get(BoardField, field_id) || {:error, :not_found},
         {:ok, _} <- Kanban.set_card_field_value(card, field, raw_value, actor: user) do
      json(conn, BoardJSON.card_response(reload_card(card)))
    else
      {:error, :invalid_field} -> {:error, :not_found}
      {:error, :invalid_option} -> {:error, :validation_failed}
      {:error, :invalid_value} -> {:error, :validation_failed}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Assignees ----------------------------------------------------------

  def add_assignee(conn, %{"id" => card_id, "user_id" => user_id}) do
    actor = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(card_id, actor),
         {:ok, target} <- fetch_board_member(card.board_id, user_id),
         {:ok, _} <- Kanban.assign_user(card, target, actor: actor) do
      json(conn, BoardJSON.card_response(reload_card(card)))
    end
  end

  def remove_assignee(conn, %{"id" => card_id, "user_id" => user_id}) do
    actor = conn.assigns.current_scope.user

    with {:ok, card} <- fetch_editable_card(card_id, actor),
         {:ok, target} <- fetch_board_member(card.board_id, user_id) do
      _ = Kanban.unassign_user(card, target, actor: actor)
      json(conn, BoardJSON.card_response(reload_card(card)))
    end
  end

  defp fetch_board_member(board_id, user_id) do
    user = Accounts.get_user!(user_id)

    if Kanban.role_for(board_id, user),
      do: {:ok, user},
      else: {:error, :forbidden}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  ## Helpers ------------------------------------------------------------

  defp fetch_visible_card(card_id, user) do
    case Repo.get(Card, card_id) do
      nil ->
        {:error, :not_found}

      %Card{board_id: board_id} = card ->
        if Kanban.role_for(board_id, user), do: {:ok, card}, else: {:error, :not_found}
    end
  end

  defp reload_card_with_notes(%Card{id: id}) do
    Repo.get!(Card, id)
    |> Repo.preload([:assignees, :labels, :field_values, :notes, :background])
  end

  ## Helpers ------------------------------------------------------------

  defp fetch_editable_board(board_id, user) do
    case Kanban.get_board_for_user(board_id, user) do
      nil ->
        {:error, :not_found}

      board ->
        role = Kanban.role_for(board.id, user)
        if Kanban.can_edit?(role), do: {:ok, board}, else: {:error, :forbidden}
    end
  end

  defp fetch_editable_card(card_id, user) do
    case Repo.get(Card, card_id) do
      nil ->
        {:error, :not_found}

      %Card{board_id: board_id} = card ->
        case Kanban.get_board_for_user(board_id, user) do
          nil ->
            {:error, :not_found}

          _board ->
            role = Kanban.role_for(board_id, user)
            if Kanban.can_edit?(role), do: {:ok, card}, else: {:error, :forbidden}
        end
    end
  end

  defp reload_card(%Card{id: id}) do
    Repo.get!(Card, id)
    |> Repo.preload([:assignees, :labels, :field_values])
  end

  defp require_param(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, :validation_failed}
    end
  end

  defp parse_position(nil), do: nil
  defp parse_position(n) when is_integer(n), do: n

  defp parse_position(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      _ -> nil
    end
  end

  defp parse_position(_), do: nil
end
