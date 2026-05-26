package org.neiam.waxx.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.AddAssigneeBody
import org.neiam.waxx.app.data.BoardMembership
import org.neiam.waxx.app.data.CardDetail
import org.neiam.waxx.app.data.CardSummary
import org.neiam.waxx.app.data.CreateNoteBody
import org.neiam.waxx.app.data.MoveCardBody
import org.neiam.waxx.app.data.SetFieldBody
import org.neiam.waxx.app.data.Stage
import org.neiam.waxx.app.data.SubboardChange
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.UpdateCardBody
import org.neiam.waxx.app.data.UpdateNoteBody
import org.neiam.waxx.app.data.WaxxClient
import org.neiam.waxx.app.data.Workflow
import org.neiam.waxx.app.data.moveCardWithSubboard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CardSheet(
    initialCard: CardSummary,
    workflow: Workflow?,
    members: List<BoardMembership>,
    creds: TokenStore.Credentials?,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()

    // Detail (with notes) replaces the chip-level data once loaded.
    var detail by remember { mutableStateOf<CardDetail?>(null) }
    var loadError by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var mode by remember { mutableStateOf<Mode>(Mode.View) }
    var confirmDelete by remember { mutableStateOf(false) }

    suspend fun refresh() {
        if (creds == null) return
        try {
            detail = WaxxClient.authenticated(creds).cardDetail(initialCard.id).card
        } catch (e: Exception) {
            loadError = e.message
        }
    }

    LaunchedEffect(initialCard.id) { refresh() }

    fun mutate(block: suspend () -> Unit) {
        if (creds == null) return
        scope.launch {
            busy = true
            try {
                block()
                refresh()
                if (mode != Mode.View) mode = Mode.View
            } catch (e: Exception) {
                loadError = e.message
            } finally {
                busy = false
            }
        }
    }

    val title = detail?.title ?: initialCard.title
    val description = detail?.description ?: initialCard.description
    val stageId = detail?.board_stage_id ?: initialCard.board_stage_id
    val subboardId = detail?.subboard_id ?: initialCard.subboard_id
    val labelIds = detail?.label_ids ?: initialCard.label_ids
    val assigneeIds = detail?.assignee_ids ?: initialCard.assignee_ids
    val fieldValues = detail?.field_values ?: initialCard.field_values
    val notes = detail?.notes.orEmpty()

    val stage = workflow?.stages?.firstOrNull { it.id == stageId }
    val fieldDefs = workflow?.fields.orEmpty().sortedBy { it.position }
    val labelDefs = workflow?.labels.orEmpty()
    val subboardDefs = workflow?.subboards.orEmpty().sortedBy { it.position }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        LazyColumn(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
        ) {
            item {
                when (val m = mode) {
                    Mode.View -> {
                        Text(title, style = MaterialTheme.typography.headlineSmall)
                        if (stage != null) {
                            Text(
                                "Stage: ${stage.name}",
                                style = MaterialTheme.typography.labelMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (!description.isNullOrBlank()) {
                            Text(description, style = MaterialTheme.typography.bodyMedium)
                        }
                        if (creds != null) {
                            Spacer(Modifier.height(4.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                OutlinedButton(onClick = {
                                    mode = Mode.Edit(title, description.orEmpty())
                                }) {
                                    Icon(Icons.Default.Edit, contentDescription = null); Text(" Edit")
                                }
                                OutlinedButton(onClick = { mode = Mode.Move }) {
                                    Icon(Icons.Default.SwapHoriz, contentDescription = null); Text(" Move")
                                }
                                OutlinedButton(onClick = { confirmDelete = true }) {
                                    Icon(Icons.Default.Delete, contentDescription = null); Text(" Delete")
                                }
                            }
                        }
                    }

                    is Mode.Edit -> EditPane(
                        initialTitle = m.title,
                        initialDescription = m.description,
                        busy = busy,
                        onCancel = { mode = Mode.View },
                        onSave = { newTitle, newDescription ->
                            mutate {
                                WaxxClient.authenticated(creds!!).updateCard(
                                    cardId = initialCard.id,
                                    body = UpdateCardBody(
                                        title = newTitle,
                                        description = newDescription.ifBlank { null },
                                    ),
                                )
                            }
                        },
                    )

                    Mode.Move -> MovePane(
                        currentStageId = stageId,
                        workflow = workflow,
                        busy = busy,
                        onCancel = { mode = Mode.View },
                        onPick = { stage ->
                            mutate {
                                WaxxClient.authenticated(creds!!).moveCard(
                                    cardId = initialCard.id,
                                    body = MoveCardBody(board_stage_id = stage),
                                )
                            }
                        },
                    )
                }
            }

            if (mode == Mode.View) {
                if (subboardDefs.isNotEmpty()) {
                    item { SectionHeader("Row") }
                    item {
                        FlowRowChips {
                            FilterChip(
                                selected = subboardId == null,
                                enabled = creds != null && !busy,
                                onClick = {
                                    if (subboardId != null) {
                                        mutate {
                                            WaxxClient.authenticated(creds!!).moveCardWithSubboard(
                                                cardId = initialCard.id,
                                                stageId = stageId,
                                                subboardChange = SubboardChange.Clear,
                                            )
                                        }
                                    }
                                },
                                label = { Text("Default") },
                            )
                            subboardDefs.forEach { sb ->
                                FilterChip(
                                    selected = sb.id == subboardId,
                                    enabled = creds != null && !busy,
                                    onClick = {
                                        if (sb.id != subboardId) {
                                            mutate {
                                                WaxxClient.authenticated(creds!!).moveCardWithSubboard(
                                                    cardId = initialCard.id,
                                                    stageId = stageId,
                                                    subboardChange = SubboardChange.Set(sb.id),
                                                )
                                            }
                                        }
                                    },
                                    label = { Text(sb.name) },
                                )
                            }
                        }
                    }
                }

                if (labelDefs.isNotEmpty()) {
                    item { SectionHeader("Labels") }
                    item {
                        FlowRowChips {
                            labelDefs.forEach { label ->
                                val selected = label.id in labelIds
                                FilterChip(
                                    selected = selected,
                                    enabled = creds != null && !busy,
                                    onClick = {
                                        mutate {
                                            WaxxClient.authenticated(creds!!)
                                                .toggleLabel(initialCard.id, label.id)
                                        }
                                    },
                                    label = { Text(label.name) },
                                )
                            }
                        }
                    }
                }

                if (fieldDefs.isNotEmpty()) {
                    item { SectionHeader("Fields") }
                    items(fieldDefs, key = { it.id }) { field ->
                        val current = fieldValues.firstOrNull { it.board_field_id == field.id }?.value
                        FieldRow(
                            name = field.name,
                            kind = field.kind,
                            options = field.options,
                            value = current,
                            enabled = creds != null && !busy,
                            onSet = { v ->
                                mutate {
                                    WaxxClient.authenticated(creds!!).setField(
                                        cardId = initialCard.id,
                                        fieldId = field.id,
                                        body = SetFieldBody(v),
                                    )
                                }
                            },
                        )
                    }
                }

                if (members.isNotEmpty()) {
                    item { SectionHeader("Assignees") }
                    item {
                        FlowRowChips {
                            members.forEach { m ->
                                val selected = m.user_id in assigneeIds
                                FilterChip(
                                    selected = selected,
                                    enabled = creds != null && !busy,
                                    onClick = {
                                        mutate {
                                            val api = WaxxClient.authenticated(creds!!)
                                            if (selected) {
                                                api.removeAssignee(initialCard.id, m.user_id)
                                            } else {
                                                api.addAssignee(
                                                    initialCard.id,
                                                    AddAssigneeBody(user_id = m.user_id),
                                                )
                                            }
                                        }
                                    },
                                    label = { Text(m.email ?: m.user_id.take(8)) },
                                )
                            }
                        }
                    }
                }

                item { SectionHeader("Notes") }
                items(notes.sortedBy { it.position }, key = { it.id }) { n ->
                    NoteRow(
                        note = n,
                        stages = workflow?.stages.orEmpty(),
                        enabled = creds != null && !busy,
                        onToggleDone = {
                            mutate {
                                WaxxClient.authenticated(creds!!).updateNote(
                                    noteId = n.id,
                                    body = UpdateNoteBody(done = !n.done),
                                )
                            }
                        },
                        onPickStage = { stageId ->
                            mutate {
                                WaxxClient.authenticated(creds!!).updateNote(
                                    noteId = n.id,
                                    body = UpdateNoteBody(board_stage_id = stageId),
                                )
                            }
                        },
                        onDelete = {
                            mutate {
                                WaxxClient.authenticated(creds!!).deleteNote(n.id)
                            }
                        },
                    )
                }
                item {
                    AddNoteRow(
                        stages = workflow?.stages.orEmpty(),
                        currentStageId = stageId,
                        enabled = creds != null && !busy,
                        onAdd = { body, kind, stageIdForNote ->
                            mutate {
                                WaxxClient.authenticated(creds!!).createNote(
                                    cardId = initialCard.id,
                                    body = CreateNoteBody(
                                        body = body,
                                        kind = kind,
                                        board_stage_id = stageIdForNote,
                                    ),
                                )
                            }
                        },
                    )
                }
            }

            loadError?.let {
                item {
                    Text(
                        it,
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete card?") },
            text = { Text("\"$title\" will be removed for everyone.") },
            confirmButton = {
                Button(onClick = {
                    confirmDelete = false
                    mutate {
                        WaxxClient.authenticated(creds!!).deleteCard(initialCard.id)
                        onDismiss()
                    }
                }) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 8.dp, bottom = 2.dp),
    )
}

@Composable
private fun FlowRowChips(content: @Composable () -> Unit) {
    // Compose Foundation 1.7+ has FlowRow; use a simple Row with horizontal
    // scroll fallback to avoid pulling in a beta API for one screen.
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) { content() }
}

@Composable
private fun FieldRow(
    name: String,
    kind: String,
    options: List<String>,
    value: String?,
    enabled: Boolean,
    onSet: (String?) -> Unit,
) {
    var editing by remember { mutableStateOf(false) }
    var text by remember(value) { mutableStateOf(value.orEmpty()) }

    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            "$name: ",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.width(120.dp),
        )

        if (!editing) {
            Text(
                value ?: "—",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            if (enabled) {
                TextButton(onClick = { editing = true; text = value.orEmpty() }) {
                    Text("Edit")
                }
            }
        } else {
            Column(modifier = Modifier.weight(1f)) {
                when (kind) {
                    "select" -> {
                        Column {
                            options.forEach { opt ->
                                Row(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { text = opt }
                                        .padding(vertical = 4.dp),
                                ) {
                                    Checkbox(checked = text == opt, onCheckedChange = null)
                                    Text(opt)
                                }
                            }
                        }
                    }
                    else -> {
                        OutlinedTextField(
                            value = text,
                            onValueChange = { text = it },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                            placeholder = { Text(kind) },
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = {
                        editing = false
                        onSet(text.ifBlank { null })
                    }) { Text("Save") }
                    TextButton(onClick = {
                        editing = false
                        onSet(null)
                    }) { Text("Clear") }
                    TextButton(onClick = { editing = false }) { Text("Cancel") }
                }
            }
        }
    }
}

@Composable
private fun NoteRow(
    note: org.neiam.waxx.app.data.CardNote,
    stages: List<org.neiam.waxx.app.data.Stage>,
    enabled: Boolean,
    onToggleDone: () -> Unit,
    onPickStage: (String) -> Unit,
    onDelete: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val stage = stages.firstOrNull { it.id == note.board_stage_id }
    val tint = parseStageColor(stage?.color)
        ?: MaterialTheme.colorScheme.surfaceVariant
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(8.dp)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .background(tint.copy(alpha = 0.35f), shape)
            .padding(8.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (note.kind == "todo") {
                Checkbox(
                    checked = note.done,
                    enabled = enabled,
                    onCheckedChange = { onToggleDone() },
                )
            } else {
                Box(modifier = Modifier.width(40.dp).height(20.dp))
            }
            Text(
                note.body,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            if (enabled) {
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = "Delete note")
                }
            }
        }
        // Stage label + tap-to-reassign. The whole row already shows the
        // stage color; this just labels which stage it is and exposes the
        // picker.
        Row(modifier = Modifier.padding(start = 48.dp)) {
            Box {
                androidx.compose.material3.AssistChip(
                    enabled = enabled && stages.isNotEmpty(),
                    onClick = { menuOpen = true },
                    label = { Text(stage?.name ?: "—") },
                )
                androidx.compose.material3.DropdownMenu(
                    expanded = menuOpen,
                    onDismissRequest = { menuOpen = false },
                ) {
                    stages.sortedBy { it.position }.forEach { s ->
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text(s.name) },
                            onClick = {
                                menuOpen = false
                                if (s.id != note.board_stage_id) onPickStage(s.id)
                            },
                        )
                    }
                }
            }
        }
    }
}

// parseStageColor moved to ui/StageColor.kt — also used by BoardScreen.

@Composable
private fun AddNoteRow(
    stages: List<org.neiam.waxx.app.data.Stage>,
    currentStageId: String,
    enabled: Boolean,
    onAdd: (body: String, kind: String?, stageId: String?) -> Unit,
) {
    var body by remember { mutableStateOf("") }
    var asTodo by remember { mutableStateOf(false) }
    var stageId by remember(currentStageId) { mutableStateOf(currentStageId) }

    Column(modifier = Modifier.fillMaxWidth().padding(top = 4.dp)) {
        OutlinedTextField(
            value = body,
            onValueChange = { body = it },
            label = { Text("Add a note") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = false,
        )
        // Stage picker — defaults to the card's current stage but lets
        // the user log against any stage on the board.
        if (stages.isNotEmpty()) {
            Text(
                "Log against",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                stages.sortedBy { it.position }.forEach { s ->
                    FilterChip(
                        selected = s.id == stageId,
                        onClick = { stageId = s.id },
                        label = { Text(s.name) },
                    )
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FilterChip(
                selected = asTodo,
                onClick = { asTodo = !asTodo },
                label = { Text("Todo") },
                leadingIcon = if (asTodo) {
                    { Icon(Icons.Default.Check, contentDescription = null) }
                } else null,
            )
            Spacer(Modifier.weight(1f))
            Button(
                enabled = enabled && body.isNotBlank(),
                onClick = {
                    val text = body.trim()
                    body = ""
                    // Omit the stage param when the user kept the default
                    // (card's current stage) — the server already does
                    // that when board_stage_id is absent.
                    val explicit = if (stageId != currentStageId) stageId else null
                    onAdd(text, if (asTodo) "todo" else null, explicit)
                },
            ) {
                Icon(Icons.Default.Add, contentDescription = null); Text(" Add")
            }
        }
    }
}

@Composable
private fun EditPane(
    initialTitle: String,
    initialDescription: String,
    busy: Boolean,
    onCancel: () -> Unit,
    onSave: (String, String) -> Unit,
) {
    var title by remember { mutableStateOf(initialTitle) }
    var description by remember { mutableStateOf(initialDescription) }

    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedTextField(
            value = title,
            onValueChange = { title = it },
            label = { Text("Title") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = description,
            onValueChange = { description = it },
            label = { Text("Description") },
            modifier = Modifier.fillMaxWidth(),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                enabled = !busy && title.isNotBlank(),
                onClick = { onSave(title.trim(), description.trim()) },
            ) { Text(if (busy) "Saving…" else "Save") }
            TextButton(onClick = onCancel) { Text("Cancel") }
        }
    }
}

@Composable
private fun MovePane(
    currentStageId: String,
    workflow: Workflow?,
    busy: Boolean,
    onCancel: () -> Unit,
    onPick: (String) -> Unit,
) {
    if (workflow == null) {
        Text("Workflow not loaded; can't move.")
        TextButton(onClick = onCancel) { Text("Back") }
        return
    }

    val targets = remember(currentStageId, workflow) {
        val edges = workflow.transitions
            .filter { it.from_stage_id == currentStageId }
            .map { it.to_stage_id }
            .toSet()
        workflow.stages.filter { it.id in edges }
    }

    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Move to…", style = MaterialTheme.typography.titleSmall)
        if (targets.isEmpty()) {
            Text(
                "No valid transitions from this stage.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        } else {
            targets.forEach { stage: Stage ->
                Text(
                    stage.name,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable(enabled = !busy) { onPick(stage.id) }
                        .padding(vertical = 10.dp),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
        TextButton(onClick = onCancel) { Text("Cancel") }
    }
}

private sealed interface Mode {
    data object View : Mode
    data class Edit(val title: String, val description: String) : Mode
    data object Move : Mode
}
