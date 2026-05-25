defmodule WaxxWeb.Api.V1.BoardJSON do
  @moduledoc """
  Serialization helpers for board-shaped resources. Each function returns
  a plain map that the controller hands to `json/2`. Keys are snake_case
  to match the schemas.

  Three resource families:
  - `board_summary` / `board` — board metadata (list and detail).
  - `workflow` — the static structure (stages, transitions, labels,
    fields, subboards) the kanban view needs to lay out columns and
    chips. Refreshed on `:workflow_changed`.
  - `cards` — the dynamic content (cards with their assignees, labels,
    field values, positions). Refreshed on `:cards_changed`.
  - `activities` — paginated history log.
  """

  alias Waxx.Kanban.{
    Board,
    BoardActivity,
    BoardField,
    BoardLabel,
    BoardStage,
    BoardTransition,
    Card,
    CardNote,
    Membership,
    Subboard
  }

  ## Boards --------------------------------------------------------------

  def boards_list(boards_with_roles) when is_list(boards_with_roles) do
    %{boards: Enum.map(boards_with_roles, &board_summary/1)}
  end

  defp board_summary({%Board{} = board, role}) do
    %{
      id: board.id,
      name: board.name,
      description: board.description,
      archive_terminal_after_days: board.archive_terminal_after_days,
      role: role,
      inserted_at: board.inserted_at,
      updated_at: board.updated_at
    }
  end

  def board(%Board{} = board, role, memberships) do
    %{
      board: %{
        id: board.id,
        name: board.name,
        description: board.description,
        archive_terminal_after_days: board.archive_terminal_after_days,
        owner_id: board.owner_id,
        template_id: board.template_id,
        role: role,
        memberships: Enum.map(memberships, &membership/1),
        inserted_at: board.inserted_at,
        updated_at: board.updated_at
      }
    }
  end

  defp membership(%Membership{} = m) do
    %{
      id: m.id,
      user_id: m.user_id,
      email: m.user && m.user.email,
      role: m.role,
      inserted_at: m.inserted_at
    }
  end

  ## Workflow ------------------------------------------------------------

  def workflow(%Board{} = board) do
    %{
      workflow: %{
        board_id: board.id,
        stages: Enum.map(board.stages, &stage/1),
        transitions: Enum.map(board.transitions, &transition/1),
        labels: Enum.map(board.labels, &label/1),
        fields: Enum.map(board.fields, &field/1),
        subboards: Enum.map(board.subboards, &subboard/1)
      }
    }
  end

  defp stage(%BoardStage{} = s) do
    %{id: s.id, name: s.name, position: s.position, color: s.color}
  end

  defp transition(%BoardTransition{} = t) do
    %{
      id: t.id,
      from_stage_id: t.from_stage_id,
      to_stage_id: t.to_stage_id,
      label: t.label
    }
  end

  defp label(%BoardLabel{} = l) do
    %{id: l.id, name: l.name, color: l.color}
  end

  defp field(%BoardField{} = f) do
    %{
      id: f.id,
      name: f.name,
      kind: f.kind,
      options: f.options || [],
      show_on_card: f.show_on_card,
      position: f.position
    }
  end

  defp subboard(%Subboard{} = sb) do
    %{id: sb.id, name: sb.name, position: sb.position}
  end

  def subboard_response(%Subboard{} = sb), do: %{subboard: subboard(sb)}

  ## Cards ---------------------------------------------------------------

  def cards(cards) when is_list(cards) do
    %{cards: Enum.map(cards, &card/1)}
  end

  @doc "Single-card envelope used by mutation endpoints."
  def card_response(%Card{} = c), do: %{card: card(c)}

  @doc """
  Single-card envelope with `notes` included. `notes` is intentionally
  not on the list payload (`cards/1`) — would bloat every board fetch.
  """
  def card_detail_response(%Card{} = c) do
    %{card: c |> card() |> Map.put(:notes, render_notes(c))}
  end

  defp render_notes(%Card{notes: %Ecto.Association.NotLoaded{}}), do: []
  defp render_notes(%Card{notes: notes}) when is_list(notes), do: Enum.map(notes, &note/1)

  def note(%CardNote{} = n) do
    %{
      id: n.id,
      body: n.body,
      kind: n.kind,
      done: n.done,
      position: n.position,
      board_stage_id: n.board_stage_id,
      created_by_id: n.created_by_id,
      inserted_at: n.inserted_at,
      updated_at: n.updated_at
    }
  end

  def note_response(%CardNote{} = n), do: %{note: note(n)}

  ## Members + invites --------------------------------------------------

  def members_list(memberships) when is_list(memberships) do
    %{memberships: Enum.map(memberships, &membership/1)}
  end

  def membership_response(%Membership{} = m), do: %{membership: membership(m)}

  def board_invites_list(invites, base_url) when is_list(invites) do
    %{invites: Enum.map(invites, &board_invite(&1, base_url))}
  end

  def board_invite_response(invite, base_url) do
    %{invite: board_invite(invite, base_url)}
  end

  defp board_invite(invite, base_url) do
    %{
      id: invite.id,
      token: invite.token,
      role: invite.role,
      note: invite.note,
      expires_at: invite.expires_at,
      consumed_at: invite.consumed_at,
      inserted_at: invite.inserted_at,
      redemption_url: "#{base_url}/b/#{invite.token}",
      consumed_by_email:
        case Map.get(invite, :consumed_by) do
          %{email: email} -> email
          _ -> nil
        end
    }
  end

  def app_invites_list(invites, base_url) when is_list(invites) do
    %{invites: Enum.map(invites, &app_invite(&1, base_url))}
  end

  def app_invite_response(invite, base_url) do
    %{invite: app_invite(invite, base_url)}
  end

  defp app_invite(invite, base_url) do
    %{
      id: invite.id,
      token: invite.token,
      note: invite.note,
      expires_at: invite.expires_at,
      consumed_at: invite.consumed_at,
      inserted_at: invite.inserted_at,
      redemption_url: "#{base_url}/users/register?invite=#{invite.token}",
      consumed_by_email:
        case Map.get(invite, :consumed_by) do
          %{email: email} -> email
          _ -> nil
        end
    }
  end

  def card(%Card{} = c) do
    %{
      id: c.id,
      title: c.title,
      description: c.description,
      board_stage_id: c.board_stage_id,
      subboard_id: c.subboard_id,
      position: c.position,
      stage_entered_at: c.stage_entered_at,
      created_by_id: c.created_by_id,
      assignee_ids: assignee_ids(c.assignees),
      label_ids: label_ids(c.labels),
      field_values: field_values(c.field_values),
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  defp assignee_ids(%Ecto.Association.NotLoaded{}), do: []
  defp assignee_ids(assignees) when is_list(assignees), do: Enum.map(assignees, & &1.id)

  defp label_ids(%Ecto.Association.NotLoaded{}), do: []
  defp label_ids(labels) when is_list(labels), do: Enum.map(labels, & &1.id)

  defp field_values(%Ecto.Association.NotLoaded{}), do: []

  defp field_values(values) when is_list(values) do
    Enum.map(values, &%{board_field_id: &1.board_field_id, value: &1.value})
  end

  ## Activities ----------------------------------------------------------

  def activities(activities) when is_list(activities) do
    %{activities: Enum.map(activities, &activity/1)}
  end

  defp activity(%BoardActivity{} = a) do
    %{
      id: a.id,
      action: a.action,
      meta: a.meta || %{},
      actor_id: a.actor_id,
      actor_email: a.actor && a.actor.email,
      card_id: a.card_id,
      card_title: a.card && a.card.title,
      inserted_at: a.inserted_at
    }
  end
end
