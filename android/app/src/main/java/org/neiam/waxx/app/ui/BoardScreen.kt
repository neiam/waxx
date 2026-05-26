package org.neiam.waxx.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TextButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.BoardEvent
import org.neiam.waxx.app.data.BoardMembership
import org.neiam.waxx.app.data.CardSummary
import org.neiam.waxx.app.data.CreateCardBody
import org.neiam.waxx.app.data.Stage
import org.neiam.waxx.app.data.Subboard
import org.neiam.waxx.app.data.SubboardChange
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.WaxxApi
import org.neiam.waxx.app.data.WaxxClient
import org.neiam.waxx.app.data.WaxxSocket
import org.neiam.waxx.app.data.Workflow
import org.neiam.waxx.app.data.moveCardWithSubboard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BoardScreen(
    boardId: String,
    tokens: TokenStore,
    onBack: () -> Unit,
    onOpenHistory: (String) -> Unit,
    onOpenCard: (CardSummary) -> Unit,
    onOpenSettings: (String) -> Unit,
    onWorkflowLoaded: (Workflow) -> Unit = {},
    onMembersLoaded: (List<BoardMembership>) -> Unit = {},
) {
    var state by remember { mutableStateOf<BoardState>(BoardState.Loading) }
    var connection by remember { mutableStateOf<Connection>(Connection.Connecting) }
    val scope = rememberCoroutineScope()

    val creds = remember { tokens.load() }

    // Initial load and refresh.
    suspend fun refreshAll(api: WaxxApi) {
        try {
            val board = api.board(boardId).board
            val workflow = api.workflow(boardId).workflow
            val cards = api.cards(boardId).cards
            onWorkflowLoaded(workflow)
            onMembersLoaded(board.memberships)
            state = BoardState.Loaded(board.name, workflow, cards)
        } catch (e: Exception) {
            state = BoardState.Error(e.message ?: "Couldn't load board.")
        }
    }

    suspend fun refreshCards(api: WaxxApi) {
        val prev = state as? BoardState.Loaded ?: return
        try {
            val cards = api.cards(boardId).cards
            state = prev.copy(cards = cards)
        } catch (_: Exception) {
            // Silent — keep previous list; next push will trigger another try.
        }
    }

    suspend fun refreshWorkflow(api: WaxxApi) {
        val prev = state as? BoardState.Loaded ?: return
        try {
            val workflow = api.workflow(boardId).workflow
            onWorkflowLoaded(workflow)
            state = prev.copy(workflow = workflow)
        } catch (_: Exception) {
        }
    }

    LaunchedEffect(boardId, creds) {
        if (creds == null) {
            state = BoardState.Error("Not paired.")
            return@LaunchedEffect
        }
        refreshAll(WaxxClient.authenticated(creds))
    }

    DisposableEffect(boardId, creds) {
        if (creds == null) return@DisposableEffect onDispose {}
        val api = WaxxClient.authenticated(creds)

        val job: Job = scope.launch {
            WaxxSocket.subscribeBoard(creds, boardId).collectLatest { ev ->
                when (ev) {
                    BoardEvent.Connected -> connection = Connection.Connecting
                    BoardEvent.Joined -> connection = Connection.Live
                    BoardEvent.Disconnected -> connection = Connection.Offline
                    is BoardEvent.Error -> connection = Connection.Offline
                    BoardEvent.CardsChanged -> refreshCards(api)
                    BoardEvent.WorkflowChanged -> {
                        refreshWorkflow(api)
                        refreshCards(api)
                    }
                }
            }
        }

        onDispose { job.cancel() }
    }

    val title = (state as? BoardState.Loaded)?.name ?: "Board"
    var showCreate by remember { mutableStateOf(false) }
    val dragState = remember { DragState() }

    fun handleDrop() {
        val loaded = state as? BoardState.Loaded ?: return
        val session = dragState.session
        // Capture session details before dropAt clears them.
        val drop = dragState.dropAt(loaded.workflow) { cell ->
            loaded.cards
                .filter { it.board_stage_id == cell.stageId && it.subboard_id == cell.subboardId }
                .sortedBy { it.position }
                .map { it.id }
        }
        if (session == null || drop == null || creds == null) return

        val subboardChange = when {
            drop.target.subboardId == session.fromSubboardId -> SubboardChange.Leave
            drop.target.subboardId == null -> SubboardChange.Clear
            else -> SubboardChange.Set(drop.target.subboardId)
        }

        scope.launch {
            try {
                WaxxClient.authenticated(creds).moveCardWithSubboard(
                    cardId = session.card.id,
                    stageId = drop.target.stageId,
                    position = drop.index,
                    subboardChange = subboardChange,
                )
                refreshCards(WaxxClient.authenticated(creds))
            } catch (_: Exception) {
                // Channel push (if it lands) will eventually reconcile; if
                // the move was rejected (e.g. workflow drift), the chip
                // snaps back to its original cell on the next refresh.
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { AppBarTitle(title) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = { onOpenHistory(boardId) }) {
                        Icon(Icons.Default.History, contentDescription = "History")
                    }
                    IconButton(onClick = { onOpenSettings(boardId) }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                },
            )
        },
        floatingActionButton = {
            if (state is BoardState.Loaded) {
                FloatingActionButton(onClick = { showCreate = true }) {
                    Icon(Icons.Default.Add, contentDescription = "New card")
                }
            }
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            ConnectionBanner(connection)
            when (val s = state) {
                BoardState.Loading ->
                    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
                        Text("Loading…")
                    }
                is BoardState.Error ->
                    Column(modifier = Modifier.fillMaxSize().padding(24.dp)) {
                        Text("Error: ${s.message}")
                    }
                is BoardState.Loaded ->
                    Kanban(
                        workflow = s.workflow,
                        cards = s.cards,
                        onOpenCard = onOpenCard,
                        dragState = dragState,
                        onDropFinished = ::handleDrop,
                        modifier = Modifier.fillMaxSize(),
                    )
            }
        }
    }

    if (showCreate && creds != null) {
        CreateCardDialog(
            onDismiss = { showCreate = false },
            onCreate = { title, description ->
                scope.launch {
                    try {
                        WaxxClient.authenticated(creds).createCard(
                            boardId = boardId,
                            body = CreateCardBody(
                                title = title,
                                description = description.ifBlank { null },
                            ),
                        )
                        refreshCards(WaxxClient.authenticated(creds))
                    } catch (_: Exception) {
                        // Channel push will also fire on success; if the
                        // create itself errored, refresh shows nothing new.
                    }
                    showCreate = false
                }
            },
        )
    }
}

@Composable
private fun CreateCardDialog(
    onDismiss: () -> Unit,
    onCreate: (title: String, description: String) -> Unit,
) {
    var title by remember { mutableStateOf("") }
    var description by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New card") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    label = { Text("Title") },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = description,
                    onValueChange = { description = it },
                    label = { Text("Description (optional)") },
                )
            }
        },
        confirmButton = {
            Button(
                enabled = title.isNotBlank(),
                onClick = { onCreate(title.trim(), description.trim()) },
            ) { Text("Create") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ConnectionBanner(connection: Connection) {
    when (connection) {
        Connection.Live -> {}
        Connection.Connecting ->
            Banner("Connecting…", MaterialTheme.colorScheme.secondaryContainer)
        Connection.Offline ->
            Banner("Offline — changes won't sync until reconnect.",
                MaterialTheme.colorScheme.errorContainer)
    }
}

@Composable
private fun Banner(text: String, color: androidx.compose.ui.graphics.Color) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .background(color)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(text, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun Kanban(
    workflow: Workflow,
    cards: List<CardSummary>,
    onOpenCard: (CardSummary) -> Unit,
    dragState: DragState,
    onDropFinished: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sortedStages = remember(workflow) { workflow.stages.sortedBy { it.position } }
    val sortedSubboards = remember(workflow) { workflow.subboards.sortedBy { it.position } }
    val cardsByCell = remember(cards) {
        cards.groupBy { it.board_stage_id to it.subboard_id }
    }

    val scrollState = rememberScrollState()
    var viewportBounds by remember { mutableStateOf<Rect?>(null) }
    val density = LocalDensity.current
    val edgePx = with(density) { 80.dp.toPx() }
    val maxStepPx = with(density) { 16.dp.toPx() }

    // While a drag is in progress, edge-scroll the kanban horizontally
    // when the pointer is within `edgePx` of either side of the viewport.
    LaunchedEffect(Unit) {
        while (true) {
            val sess = dragState.session
            val bounds = viewportBounds
            if (sess != null && bounds != null) {
                val pointerX = sess.globalPos.x
                val leftEdge = bounds.left + edgePx
                val rightEdge = bounds.right - edgePx
                val raw = when {
                    pointerX < leftEdge -> -((leftEdge - pointerX) / edgePx) * maxStepPx
                    pointerX > rightEdge -> ((pointerX - rightEdge) / edgePx) * maxStepPx
                    else -> 0f
                }
                if (raw != 0f) {
                    scrollState.animateScrollBy(raw.coerceIn(-maxStepPx, maxStepPx))
                }
            }
            kotlinx.coroutines.delay(16)
        }
    }

    if (sortedSubboards.isEmpty()) {
        Row(
            modifier = modifier
                .onGloballyPositioned { viewportBounds = it.boundsInWindowSafe() }
                .horizontalScroll(scrollState)
                .padding(horizontal = 8.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            sortedStages.forEach { stage ->
                StageCell(
                    stage = stage,
                    subboard = null,
                    showStageLabel = true,
                    cards = cardsByCell[stage.id to null].orEmpty(),
                    workflow = workflow,
                    dragState = dragState,
                    onOpenCard = onOpenCard,
                    onDropFinished = onDropFinished,
                )
            }
        }
    } else {
        // 2-D: vertical column of subboard rows (default first), each a
        // horizontal row of stage cells. The whole grid scrolls horizontally
        // together so columns line up. Reuses the same scrollState as the
        // 1-D branch so the edge-scroll effect above drives whichever
        // layout is active.
        val rows: List<Subboard?> = listOf(null) + sortedSubboards
        Column(
            modifier = modifier
                .onGloballyPositioned { viewportBounds = it.boundsInWindowSafe() }
                .horizontalScroll(scrollState)
                .padding(horizontal = 8.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Column header — each stage label sits in a tinted box
            // matching its stage color so the grid header reads like the
            // 1-D cell headers below.
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(modifier = Modifier.width(120.dp))
                sortedStages.forEach { stage ->
                    val tint = parseStageColor(stage.color)
                    Box(
                        modifier = Modifier
                            .width(240.dp)
                            .then(
                                if (tint != null) {
                                    Modifier.background(
                                        tint.copy(alpha = 0.35f),
                                        RoundedCornerShape(6.dp),
                                    )
                                } else Modifier,
                            )
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                    ) {
                        Text(
                            stage.name,
                            fontWeight = FontWeight.SemiBold,
                            style = MaterialTheme.typography.titleSmall,
                        )
                    }
                }
            }
            rows.forEach { sb ->
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        sb?.name ?: "Default",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.width(120.dp).padding(top = 8.dp),
                    )
                    sortedStages.forEach { stage ->
                        StageCell(
                            stage = stage,
                            subboard = sb,
                            showStageLabel = false,
                            cards = cardsByCell[stage.id to sb?.id].orEmpty(),
                            workflow = workflow,
                            dragState = dragState,
                            onOpenCard = onOpenCard,
                            onDropFinished = onDropFinished,
                            cellWidth = 240.dp,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun StageCell(
    stage: Stage,
    subboard: Subboard?,
    showStageLabel: Boolean,
    cards: List<CardSummary>,
    workflow: Workflow,
    dragState: DragState,
    onOpenCard: (CardSummary) -> Unit,
    onDropFinished: () -> Unit,
    cellWidth: androidx.compose.ui.unit.Dp = 280.dp,
) {
    val session = dragState.session
    val isSource = session != null &&
        session.fromStageId == stage.id &&
        session.fromSubboardId == subboard?.id
    val highlight: Color? = when {
        session == null -> null
        isSource -> Color(0x33888888) // dim grey
        dragState.isValidTarget(stage.id, subboard?.id, workflow) -> Color(0x6680FF80) // green
        else -> Color(0x66FF8080) // red
    }

    Card(
        modifier = Modifier
            .width(cellWidth)
            .onGloballyPositioned {
                dragState.setCellBounds(stage.id, subboard?.id, it.boundsInWindowSafe())
            },
    ) {
        Column(
            modifier = Modifier
                .padding(8.dp)
                .then(
                    if (highlight != null) {
                        Modifier
                            .background(highlight, RoundedCornerShape(6.dp))
                            .border(2.dp, highlight, RoundedCornerShape(6.dp))
                    } else Modifier,
                ),
        ) {
            if (showStageLabel) {
                val tint = parseStageColor(stage.color)
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(
                            if (tint != null) {
                                Modifier.background(
                                    tint.copy(alpha = 0.35f),
                                    RoundedCornerShape(6.dp),
                                )
                            } else Modifier,
                        )
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                ) {
                    Text(
                        stage.name,
                        fontWeight = FontWeight.SemiBold,
                        style = MaterialTheme.typography.titleSmall,
                    )
                }
            }
            Text(
                "${cards.size} card${if (cards.size == 1) "" else "s"}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 8.dp),
            )

            if (cards.isEmpty()) {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp)) {
                    Text(
                        "—",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                    contentPadding = PaddingValues(vertical = 2.dp),
                ) {
                    items(cards.sortedBy { it.position }, key = { it.id }) { c ->
                        CardChip(
                            card = c,
                            fromStageId = stage.id,
                            fromSubboardId = subboard?.id,
                            dragState = dragState,
                            onClick = { onOpenCard(c) },
                            onDropFinished = onDropFinished,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CardChip(
    card: CardSummary,
    fromStageId: String,
    fromSubboardId: String?,
    dragState: DragState,
    onClick: () -> Unit,
    onDropFinished: () -> Unit,
) {
    var chipOrigin by remember { mutableStateOf(Offset.Zero) }
    val isMe = dragState.session?.card?.id == card.id

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .onGloballyPositioned {
                val origin = it.positionInWindow()
                chipOrigin = origin
                dragState.setChipCenterY(card.id, origin.y + it.size.height / 2f)
            }
            .pointerInput(card.id) {
                detectDragGesturesAfterLongPress(
                    onDragStart = { local ->
                        dragState.start(card, fromStageId, fromSubboardId, chipOrigin + local)
                    },
                    onDrag = { change, delta ->
                        dragState.update(delta)
                        change.consume()
                    },
                    onDragEnd = { onDropFinished() },
                    onDragCancel = { dragState.cancel() },
                )
            }
            .clickable(onClick = onClick)
            .then(if (isMe) Modifier.border(2.dp, Color(0xFF40A0FF), RoundedCornerShape(6.dp)) else Modifier),
    ) {
        Column(modifier = Modifier.padding(8.dp)) {
            Text(card.title, style = MaterialTheme.typography.bodyMedium)
            if (!card.description.isNullOrBlank()) {
                Text(
                    card.description.take(80),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun androidx.compose.ui.layout.LayoutCoordinates.boundsInWindowSafe(): androidx.compose.ui.geometry.Rect {
    val origin = positionInWindow()
    return androidx.compose.ui.geometry.Rect(
        offset = origin,
        size = androidx.compose.ui.geometry.Size(size.width.toFloat(), size.height.toFloat()),
    )
}

private sealed interface BoardState {
    data object Loading : BoardState
    data class Loaded(val name: String, val workflow: Workflow, val cards: List<CardSummary>) :
        BoardState
    data class Error(val message: String) : BoardState
}

private sealed interface Connection {
    data object Connecting : Connection
    data object Live : Connection
    data object Offline : Connection
}
