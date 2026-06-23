package org.neiam.waxx.app.data

import kotlinx.serialization.Serializable

@Serializable
data class WaxxUser(
    val id: String,
    val email: String,
    val confirmed_at: String? = null,
    // Server-side `preferences` is a free-form jsonb map mixing booleans
    // ("hide_label_text:<board>"), strings ("theme_default"), and numbers.
    // Keep it as raw JsonElement on the wire — the app doesn't read prefs
    // yet, and typing it as `Map<String, String>` made the QR-pair probe
    // crash on the boolean values.
    val preferences: Map<String, kotlinx.serialization.json.JsonElement> = emptyMap(),
)

@Serializable
data class RedeemResponse(
    val api_token: String,
    val user: RedeemUser,
)

@Serializable
data class RedeemUser(
    val id: String,
    val email: String,
)

@Serializable
data class RequestMagicLinkBody(val email: String)

@Serializable
data class RedeemBody(val token: String)

@Serializable
data class ApiError(val error: ApiErrorBody)

@Serializable
data class ApiErrorBody(
    val code: String,
    val message: String,
)

// --- Phase 2 read models -------------------------------------------------

@Serializable
data class BoardSummary(
    val id: String,
    val name: String,
    val description: String? = null,
    val role: String? = null,
    val inserted_at: String? = null,
    val updated_at: String? = null,
)

@Serializable
data class BoardsListResponse(val boards: List<BoardSummary>)

@Serializable
data class BoardDetail(
    val id: String,
    val name: String,
    val description: String? = null,
    val role: String? = null,
    val memberships: List<BoardMembership> = emptyList(),
    val archive_terminal_after_days: Int? = null,
)

@Serializable
data class BoardDetailResponse(val board: BoardDetail)

@Serializable
data class BoardMembership(
    val id: String,
    val user_id: String,
    val email: String? = null,
    val role: String,
)

@Serializable
data class WorkflowResponse(val workflow: Workflow)

@Serializable
data class Workflow(
    val board_id: String,
    val stages: List<Stage> = emptyList(),
    val transitions: List<Transition> = emptyList(),
    val labels: List<Label> = emptyList(),
    val fields: List<Field> = emptyList(),
    val subboards: List<Subboard> = emptyList(),
)

@Serializable
data class Stage(
    val id: String,
    val name: String,
    val position: Int,
    val color: String? = null,
)

@Serializable
data class Transition(
    val id: String,
    val from_stage_id: String,
    val to_stage_id: String,
    val label: String? = null,
)

@Serializable
data class Label(
    val id: String,
    val name: String,
    val color: String? = null,
    // Subboards this label is scoped to. Empty = board-wide (applies to every
    // card). Present on board workflows; template labels omit it (defaults []).
    val subboard_ids: List<String> = emptyList(),
) {
    /**
     * Whether this label may be applied to a card sitting in [subboardId]
     * (null = the default row). Board-wide labels apply everywhere; scoped
     * labels only inside their subboards. Mirrors the server-side rule.
     */
    fun appliesTo(subboardId: String?): Boolean =
        subboard_ids.isEmpty() || subboardId in subboard_ids
}

@Serializable
data class Field(
    val id: String,
    val name: String,
    val kind: String,
    val options: List<String> = emptyList(),
    val show_on_card: Boolean = false,
    val position: Int = 0,
)

@Serializable
data class Subboard(
    val id: String,
    val name: String,
    val position: Int,
)

@Serializable
data class CardsResponse(val cards: List<CardSummary>)

@Serializable
data class CardSummary(
    val id: String,
    val title: String,
    val description: String? = null,
    val board_stage_id: String,
    val subboard_id: String? = null,
    val position: Int = 0,
    val stage_entered_at: String? = null,
    val assignee_ids: List<String> = emptyList(),
    val label_ids: List<String> = emptyList(),
    val field_values: List<CardFieldValue> = emptyList(),
)

@Serializable
data class CardFieldValue(
    val board_field_id: String,
    val value: String? = null,
)

@Serializable
data class ActivitiesResponse(val activities: List<Activity>)

// --- Phase 4 write payloads ----------------------------------------------

@Serializable
data class CreateCardBody(
    val title: String,
    val description: String? = null,
    val board_stage_id: String? = null,
)

@Serializable
data class UpdateCardBody(
    val title: String? = null,
    val description: String? = null,
)

@Serializable
data class MoveCardBody(
    val board_stage_id: String,
    val position: Int? = null,
)

/**
 * Move + subboard re-assignment in one call. Wire format omits
 * `subboard_id` entirely for [SubboardChange.Leave], emits null for
 * [SubboardChange.Clear], and emits the id for [SubboardChange.Set] —
 * the server distinguishes "absent" from "null" via `Map.has_key?`.
 */
sealed interface SubboardChange {
    data object Leave : SubboardChange
    data object Clear : SubboardChange
    data class Set(val id: String) : SubboardChange
}

@Serializable
data class CardResponse(val card: CardSummary)

@Serializable
data class CardDetail(
    val id: String,
    val title: String,
    val description: String? = null,
    val board_stage_id: String,
    val subboard_id: String? = null,
    val position: Int = 0,
    val stage_entered_at: String? = null,
    val assignee_ids: List<String> = emptyList(),
    val label_ids: List<String> = emptyList(),
    val field_values: List<CardFieldValue> = emptyList(),
    val notes: List<CardNote> = emptyList(),
    val background: CardBackground? = null,
)

/**
 * A pasted background image for a card. `data` is the base64-encoded image
 * bytes; only delivered on the single-card detail payload, never the list.
 */
@Serializable
data class CardBackground(
    val content_type: String,
    val data: String,
)

@Serializable
data class CardDetailResponse(val card: CardDetail)

@Serializable
data class CardNote(
    val id: String,
    val body: String,
    val kind: String,
    val done: Boolean = false,
    val position: Int = 0,
    val board_stage_id: String? = null,
    val created_by_id: String? = null,
    val inserted_at: String? = null,
    val updated_at: String? = null,
)

@Serializable
data class NoteResponse(val note: CardNote)

@Serializable
data class CreateNoteBody(
    val body: String,
    val kind: String? = null,
    val board_stage_id: String? = null,
)

@Serializable
data class UpdateNoteBody(
    val body: String? = null,
    val done: Boolean? = null,
    val kind: String? = null,
    val board_stage_id: String? = null,
)

@Serializable
data class SetFieldBody(val value: String? = null)

@Serializable
data class AddAssigneeBody(val user_id: String)

@Serializable
data class CreateSubboardBody(val name: String)

@Serializable
data class ReorderSubboardBody(val position: Int)

@Serializable
data class SubboardResponse(val subboard: Subboard)

// --- Phase 5b: workflow templates ----------------------------------------

@Serializable
data class TemplateSummary(
    val id: String,
    val name: String,
    val description: String? = null,
    val created_by_id: String? = null,
    val inserted_at: String? = null,
    val updated_at: String? = null,
)

@Serializable
data class TemplatesListResponse(val templates: List<TemplateSummary>)

@Serializable
data class TemplateGraph(
    val id: String,
    val name: String,
    val description: String? = null,
    val created_by_id: String? = null,
    val stages: List<Stage> = emptyList(),
    val transitions: List<Transition> = emptyList(),
    val labels: List<Label> = emptyList(),
    val fields: List<Field> = emptyList(),
)

@Serializable
data class TemplateResponse(val template: TemplateGraph)

@Serializable
data class TemplateStageResponse(val stage: Stage)

@Serializable
data class TemplateTransitionResponse(val transition: Transition)

@Serializable
data class TemplateLabelResponse(val label: Label)

@Serializable
data class TemplateFieldResponse(val field: Field)

@Serializable
data class CreateTemplateBody(val name: String, val description: String? = null)

@Serializable
data class UpdateTemplateBody(val name: String? = null, val description: String? = null)

@Serializable
data class CreateStageBody(val name: String, val color: String? = null)

@Serializable
data class UpdateStageBody(val name: String? = null, val color: String? = null)

@Serializable
data class CreateTransitionBody(
    val from_stage_id: String,
    val to_stage_id: String,
    val label: String? = null,
)

@Serializable
data class CreateLabelBody(val name: String, val color: String? = null)

// Board labels carry an optional subboard scope. Posting an existing name
// upserts (updates color + scope) server-side rather than failing.
@Serializable
data class BoardLabelBody(
    val name: String? = null,
    val color: String? = null,
    val subboard_ids: List<String>? = null,
)

@Serializable
data class BoardLabelResponse(val label: Label)

@Serializable
data class CreateFieldBody(
    val name: String,
    val kind: String,
    val options: List<String>? = null,
    val show_on_card: Boolean? = null,
)

@Serializable
data class UpdateFieldBody(
    val name: String? = null,
    val kind: String? = null,
    val options: List<String>? = null,
    val show_on_card: Boolean? = null,
)

@Serializable
data class CreateBoardBody(
    val template_id: String,
    val name: String,
    val description: String? = null,
    val archive_terminal_after_days: Int? = null,
)

// --- Phase 5 settings / members / invites --------------------------------

@Serializable
data class UpdateBoardBody(
    val name: String? = null,
    val description: String? = null,
    val archive_terminal_after_days: Int? = null,
)

@Serializable
data class UpdateRoleBody(val role: String)

@Serializable
data class MembershipResponse(val membership: BoardMembership)

@Serializable
data class BoardInvite(
    val id: String,
    val token: String,
    val role: String,
    val note: String? = null,
    val expires_at: String? = null,
    val consumed_at: String? = null,
    val inserted_at: String? = null,
    val redemption_url: String,
    val consumed_by_email: String? = null,
)

@Serializable
data class BoardInvitesResponse(val invites: List<BoardInvite>)

@Serializable
data class BoardInviteResponse(val invite: BoardInvite)

@Serializable
data class CreateBoardInviteBody(
    val role: String? = null,
    val note: String? = null,
    val expires_in_days: Int? = null,
)

@Serializable
data class AppInvite(
    val id: String,
    val token: String,
    val note: String? = null,
    val expires_at: String? = null,
    val consumed_at: String? = null,
    val inserted_at: String? = null,
    val redemption_url: String,
    val consumed_by_email: String? = null,
)

@Serializable
data class AppInvitesResponse(val invites: List<AppInvite>)

@Serializable
data class AppInviteResponse(val invite: AppInvite)

@Serializable
data class CreateAppInviteBody(
    val note: String? = null,
    val expires_in_days: Int? = null,
)

@Serializable
data class Activity(
    val id: String,
    val action: String,
    // `meta` is a free-form jsonb map server-side; the dedicated history
    // formatter on the web renders it per-action. For Phase 2 we just
    // show action + actor + card_title, so `meta` is intentionally
    // dropped here (ignoreUnknownKeys skips it on the wire).
    val actor_id: String? = null,
    val actor_email: String? = null,
    val card_id: String? = null,
    val card_title: String? = null,
    val inserted_at: String,
)
