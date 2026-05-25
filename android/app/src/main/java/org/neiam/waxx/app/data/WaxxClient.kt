package org.neiam.waxx.app.data

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.POST
import java.util.concurrent.TimeUnit

/**
 * Authenticated endpoints — every call carries Authorization: Bearer.
 */
interface WaxxApi {
    @GET("api/v1/users/me")
    suspend fun me(): WaxxUser

    @DELETE("api/v1/sessions/current")
    suspend fun logout(): retrofit2.Response<Unit>

    @GET("api/v1/boards")
    suspend fun boards(): BoardsListResponse

    @GET("api/v1/boards/{id}")
    suspend fun board(@retrofit2.http.Path("id") id: String): BoardDetailResponse

    @GET("api/v1/boards/{id}/workflow")
    suspend fun workflow(@retrofit2.http.Path("id") id: String): WorkflowResponse

    @GET("api/v1/boards/{id}/cards")
    suspend fun cards(@retrofit2.http.Path("id") id: String): CardsResponse

    @GET("api/v1/boards/{id}/history")
    suspend fun history(
        @retrofit2.http.Path("id") id: String,
        @retrofit2.http.Query("limit") limit: Int? = null,
    ): ActivitiesResponse

    @retrofit2.http.POST("api/v1/boards/{id}/cards")
    suspend fun createCard(
        @retrofit2.http.Path("id") boardId: String,
        @retrofit2.http.Body body: CreateCardBody,
    ): CardResponse

    @retrofit2.http.PATCH("api/v1/cards/{id}")
    suspend fun updateCard(
        @retrofit2.http.Path("id") cardId: String,
        @retrofit2.http.Body body: UpdateCardBody,
    ): CardResponse

    @retrofit2.http.POST("api/v1/cards/{id}/move")
    suspend fun moveCard(
        @retrofit2.http.Path("id") cardId: String,
        @retrofit2.http.Body body: MoveCardBody,
    ): CardResponse

    /**
     * Free-form move that can include `subboard_id` (or omit it). Used by
     * `moveCardWithSubboard` extension — prefer that wrapper over
     * building the JsonObject inline.
     */
    @retrofit2.http.POST("api/v1/cards/{id}/move")
    suspend fun moveCardRaw(
        @retrofit2.http.Path("id") cardId: String,
        @retrofit2.http.Body body: JsonObject,
    ): CardResponse

    @retrofit2.http.DELETE("api/v1/cards/{id}")
    suspend fun deleteCard(
        @retrofit2.http.Path("id") cardId: String,
    ): retrofit2.Response<Unit>

    @GET("api/v1/cards/{id}")
    suspend fun cardDetail(@retrofit2.http.Path("id") cardId: String): CardDetailResponse

    @retrofit2.http.POST("api/v1/cards/{cardId}/labels/{labelId}/toggle")
    suspend fun toggleLabel(
        @retrofit2.http.Path("cardId") cardId: String,
        @retrofit2.http.Path("labelId") labelId: String,
    ): CardResponse

    @retrofit2.http.PUT("api/v1/cards/{cardId}/fields/{fieldId}")
    suspend fun setField(
        @retrofit2.http.Path("cardId") cardId: String,
        @retrofit2.http.Path("fieldId") fieldId: String,
        @retrofit2.http.Body body: SetFieldBody,
    ): CardResponse

    @retrofit2.http.POST("api/v1/cards/{cardId}/assignees")
    suspend fun addAssignee(
        @retrofit2.http.Path("cardId") cardId: String,
        @retrofit2.http.Body body: AddAssigneeBody,
    ): CardResponse

    @retrofit2.http.DELETE("api/v1/cards/{cardId}/assignees/{userId}")
    suspend fun removeAssignee(
        @retrofit2.http.Path("cardId") cardId: String,
        @retrofit2.http.Path("userId") userId: String,
    ): CardResponse

    @retrofit2.http.POST("api/v1/cards/{cardId}/notes")
    suspend fun createNote(
        @retrofit2.http.Path("cardId") cardId: String,
        @retrofit2.http.Body body: CreateNoteBody,
    ): NoteResponse

    @retrofit2.http.PATCH("api/v1/notes/{id}")
    suspend fun updateNote(
        @retrofit2.http.Path("id") noteId: String,
        @retrofit2.http.Body body: UpdateNoteBody,
    ): NoteResponse

    @retrofit2.http.DELETE("api/v1/notes/{id}")
    suspend fun deleteNote(
        @retrofit2.http.Path("id") noteId: String,
    ): retrofit2.Response<Unit>

    // --- Phase 5: settings / members / invites ---

    @retrofit2.http.PATCH("api/v1/boards/{id}")
    suspend fun updateBoard(
        @retrofit2.http.Path("id") id: String,
        @retrofit2.http.Body body: UpdateBoardBody,
    ): BoardDetailResponse

    @retrofit2.http.DELETE("api/v1/boards/{id}")
    suspend fun deleteBoard(
        @retrofit2.http.Path("id") id: String,
    ): retrofit2.Response<Unit>

    @retrofit2.http.PUT("api/v1/boards/{boardId}/memberships/{userId}")
    suspend fun updateMembershipRole(
        @retrofit2.http.Path("boardId") boardId: String,
        @retrofit2.http.Path("userId") userId: String,
        @retrofit2.http.Body body: UpdateRoleBody,
    ): MembershipResponse

    @retrofit2.http.DELETE("api/v1/boards/{boardId}/memberships/{userId}")
    suspend fun removeMembership(
        @retrofit2.http.Path("boardId") boardId: String,
        @retrofit2.http.Path("userId") userId: String,
    ): retrofit2.Response<Unit>

    @GET("api/v1/boards/{id}/invites")
    suspend fun boardInvites(@retrofit2.http.Path("id") boardId: String): BoardInvitesResponse

    @retrofit2.http.POST("api/v1/boards/{id}/invites")
    suspend fun createBoardInvite(
        @retrofit2.http.Path("id") boardId: String,
        @retrofit2.http.Body body: CreateBoardInviteBody,
    ): BoardInviteResponse

    @retrofit2.http.DELETE("api/v1/boards/{boardId}/invites/{inviteId}")
    suspend fun revokeBoardInvite(
        @retrofit2.http.Path("boardId") boardId: String,
        @retrofit2.http.Path("inviteId") inviteId: String,
    ): retrofit2.Response<Unit>

    @GET("api/v1/users/invites")
    suspend fun appInvites(): AppInvitesResponse

    @retrofit2.http.POST("api/v1/users/invites")
    suspend fun createAppInvite(
        @retrofit2.http.Body body: CreateAppInviteBody,
    ): AppInviteResponse

    @retrofit2.http.DELETE("api/v1/users/invites/{id}")
    suspend fun revokeAppInvite(
        @retrofit2.http.Path("id") id: String,
    ): retrofit2.Response<Unit>

    // --- Phase 6: subboards ---

    @retrofit2.http.POST("api/v1/boards/{id}/subboards")
    suspend fun createSubboard(
        @retrofit2.http.Path("id") boardId: String,
        @retrofit2.http.Body body: CreateSubboardBody,
    ): SubboardResponse

    @retrofit2.http.PATCH("api/v1/subboards/{id}")
    suspend fun reorderSubboard(
        @retrofit2.http.Path("id") id: String,
        @retrofit2.http.Body body: ReorderSubboardBody,
    ): SubboardResponse

    // --- Phase 5b: workflow templates ---

    @GET("api/v1/workflow_templates")
    suspend fun templates(): TemplatesListResponse

    @GET("api/v1/workflow_templates/{id}")
    suspend fun template(@retrofit2.http.Path("id") id: String): TemplateResponse

    @retrofit2.http.POST("api/v1/workflow_templates")
    suspend fun createTemplate(@retrofit2.http.Body body: CreateTemplateBody): TemplateResponse

    @retrofit2.http.PATCH("api/v1/workflow_templates/{id}")
    suspend fun updateTemplate(
        @retrofit2.http.Path("id") id: String,
        @retrofit2.http.Body body: UpdateTemplateBody,
    ): TemplateResponse

    @retrofit2.http.DELETE("api/v1/workflow_templates/{id}")
    suspend fun deleteTemplate(@retrofit2.http.Path("id") id: String): retrofit2.Response<Unit>

    @retrofit2.http.POST("api/v1/workflow_templates/{id}/stages")
    suspend fun addTemplateStage(
        @retrofit2.http.Path("id") templateId: String,
        @retrofit2.http.Body body: CreateStageBody,
    ): TemplateStageResponse

    @retrofit2.http.PATCH("api/v1/template_stages/{id}")
    suspend fun updateTemplateStage(
        @retrofit2.http.Path("id") id: String,
        @retrofit2.http.Body body: UpdateStageBody,
    ): TemplateStageResponse

    @retrofit2.http.DELETE("api/v1/template_stages/{id}")
    suspend fun deleteTemplateStage(@retrofit2.http.Path("id") id: String): retrofit2.Response<Unit>

    @retrofit2.http.POST("api/v1/workflow_templates/{id}/transitions")
    suspend fun addTemplateTransition(
        @retrofit2.http.Path("id") templateId: String,
        @retrofit2.http.Body body: CreateTransitionBody,
    ): TemplateTransitionResponse

    @retrofit2.http.DELETE("api/v1/template_transitions/{id}")
    suspend fun deleteTemplateTransition(@retrofit2.http.Path("id") id: String): retrofit2.Response<Unit>

    @retrofit2.http.POST("api/v1/workflow_templates/{id}/labels")
    suspend fun addTemplateLabel(
        @retrofit2.http.Path("id") templateId: String,
        @retrofit2.http.Body body: CreateLabelBody,
    ): TemplateLabelResponse

    @retrofit2.http.DELETE("api/v1/template_labels/{id}")
    suspend fun deleteTemplateLabel(@retrofit2.http.Path("id") id: String): retrofit2.Response<Unit>

    @retrofit2.http.POST("api/v1/workflow_templates/{id}/fields")
    suspend fun addTemplateField(
        @retrofit2.http.Path("id") templateId: String,
        @retrofit2.http.Body body: CreateFieldBody,
    ): TemplateFieldResponse

    @retrofit2.http.PATCH("api/v1/template_fields/{id}")
    suspend fun updateTemplateField(
        @retrofit2.http.Path("id") id: String,
        @retrofit2.http.Body body: UpdateFieldBody,
    ): TemplateFieldResponse

    @retrofit2.http.DELETE("api/v1/template_fields/{id}")
    suspend fun deleteTemplateField(@retrofit2.http.Path("id") id: String): retrofit2.Response<Unit>

    @retrofit2.http.POST("api/v1/boards")
    suspend fun createBoard(@retrofit2.http.Body body: CreateBoardBody): BoardDetailResponse

    @retrofit2.http.DELETE("api/v1/subboards/{id}")
    suspend fun deleteSubboard(
        @retrofit2.http.Path("id") id: String,
    ): retrofit2.Response<Unit>
}

/**
 * Move that can also re-assign subboard in one call. See [SubboardChange]
 * for the wire semantics ("leave alone" vs "clear" vs "set").
 */
suspend fun WaxxApi.moveCardWithSubboard(
    cardId: String,
    stageId: String,
    position: Int? = null,
    subboardChange: SubboardChange = SubboardChange.Leave,
): CardResponse {
    val body = buildJsonObject {
        put("board_stage_id", stageId)
        position?.let { put("position", it) }
        when (subboardChange) {
            SubboardChange.Leave -> {}
            SubboardChange.Clear -> put("subboard_id", JsonNull)
            is SubboardChange.Set -> put("subboard_id", JsonPrimitive(subboardChange.id))
        }
    }
    return moveCardRaw(cardId, body)
}

/**
 * Unauthenticated endpoints used during the magic-link login dance.
 */
interface WaxxAuthApi {
    @POST("api/v1/sessions/request_magic_link")
    suspend fun requestMagicLink(@Body body: RequestMagicLinkBody): retrofit2.Response<Unit>

    @POST("api/v1/sessions/redeem")
    suspend fun redeem(@Body body: RedeemBody): RedeemResponse
}

object WaxxClient {
    private val json = Json { ignoreUnknownKeys = true }
    private val converter = json.asConverterFactory("application/json".toMediaType())

    fun authenticated(creds: TokenStore.Credentials): WaxxApi {
        val ok = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val req = chain.request().newBuilder()
                    .addHeader("Authorization", "Bearer ${creds.token}")
                    .addHeader("Accept", "application/json")
                    .build()
                chain.proceed(req)
            }
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            })
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        return Retrofit.Builder()
            .baseUrl(asBaseUrl(creds.baseUrl))
            .client(ok)
            .addConverterFactory(converter)
            .build()
            .create(WaxxApi::class.java)
    }

    fun anon(baseUrl: String): WaxxAuthApi {
        val ok = OkHttpClient.Builder()
            .addInterceptor(HttpLoggingInterceptor().apply {
                level = HttpLoggingInterceptor.Level.BASIC
            })
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        return Retrofit.Builder()
            .baseUrl(asBaseUrl(baseUrl))
            .client(ok)
            .addConverterFactory(converter)
            .build()
            .create(WaxxAuthApi::class.java)
    }

    private fun asBaseUrl(s: String) = if (s.endsWith("/")) s else "$s/"
}

/**
 * Extracts the token from a magic-link URL like `https://host/m/<token>`
 * or `waxx://login/<token>` — either format the server might end up
 * emitting. Returns null on no match.
 */
fun extractMagicLinkToken(url: String): String? {
    val uri = runCatching { android.net.Uri.parse(url) }.getOrNull() ?: return null
    val segs = uri.pathSegments ?: return null
    if (segs.size >= 2 && segs[0] == "m") return segs[1].takeIf { it.isNotBlank() }
    if (uri.scheme == "waxx" && uri.host == "login" && segs.size >= 1) {
        return segs[0].takeIf { it.isNotBlank() }
    }
    return null
}
