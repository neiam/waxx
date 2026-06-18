package org.neiam.waxx.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.BoardDetail
import org.neiam.waxx.app.data.BoardInvite
import org.neiam.waxx.app.data.BoardLabelBody
import org.neiam.waxx.app.data.BoardMembership
import org.neiam.waxx.app.data.CreateBoardInviteBody
import org.neiam.waxx.app.data.CreateSubboardBody
import org.neiam.waxx.app.data.Label
import org.neiam.waxx.app.data.ReorderSubboardBody
import org.neiam.waxx.app.data.Subboard
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.UpdateBoardBody
import org.neiam.waxx.app.data.UpdateRoleBody
import org.neiam.waxx.app.data.WaxxApi
import org.neiam.waxx.app.data.WaxxClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BoardSettingsScreen(
    boardId: String,
    tokens: TokenStore,
    onBack: () -> Unit,
    onDeleted: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val creds = remember { tokens.load() }
    var tab by remember { mutableStateOf(0) }

    var board by remember { mutableStateOf<BoardDetail?>(null) }
    var invites by remember { mutableStateOf<List<BoardInvite>>(emptyList()) }
    var subboards by remember { mutableStateOf<List<Subboard>>(emptyList()) }
    var labels by remember { mutableStateOf<List<Label>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    suspend fun reload() {
        if (creds == null) return
        try {
            val api = WaxxClient.authenticated(creds)
            board = api.board(boardId).board
            val workflow = runCatching { api.workflow(boardId).workflow }.getOrNull()
            subboards = workflow?.subboards.orEmpty()
            labels = workflow?.labels.orEmpty()
            invites = runCatching { api.boardInvites(boardId).invites }.getOrDefault(emptyList())
        } catch (e: Exception) {
            error = e.message
        }
    }

    LaunchedEffect(boardId) { reload() }

    fun mutate(block: suspend WaxxApi.() -> Unit) {
        if (creds == null) return
        scope.launch {
            busy = true
            error = null
            try {
                WaxxClient.authenticated(creds).block()
                reload()
            } catch (e: Exception) {
                error = e.message
            } finally {
                busy = false
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { AppBarTitle(board?.name ?: "Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            TabRow(selectedTabIndex = tab) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Settings") })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Members") })
                Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text("Invites") })
                Tab(selected = tab == 3, onClick = { tab = 3 }, text = { Text("Rows") })
                Tab(selected = tab == 4, onClick = { tab = 4 }, text = { Text("Labels") })
            }

            val isOwner = board?.role == "owner"

            when (tab) {
                0 -> SettingsTab(
                    board = board,
                    isOwner = isOwner,
                    busy = busy,
                    onSave = { name, description, days ->
                        mutate {
                            updateBoard(
                                id = boardId,
                                body = UpdateBoardBody(
                                    name = name.ifBlank { null },
                                    description = description,
                                    archive_terminal_after_days = days,
                                ),
                            )
                        }
                    },
                    onDelete = {
                        mutate { deleteBoard(boardId) }
                        onDeleted()
                    },
                )

                1 -> MembersTab(
                    members = board?.memberships.orEmpty(),
                    isOwner = isOwner,
                    busy = busy,
                    onChangeRole = { userId, role ->
                        mutate {
                            updateMembershipRole(boardId, userId, UpdateRoleBody(role))
                        }
                    },
                    onRemove = { userId ->
                        mutate { removeMembership(boardId, userId) }
                    },
                )

                2 -> InvitesTab(
                    invites = invites,
                    isOwner = isOwner,
                    busy = busy,
                    onCreate = { role, note, days ->
                        mutate {
                            createBoardInvite(
                                boardId = boardId,
                                body = CreateBoardInviteBody(
                                    role = role,
                                    note = note?.ifBlank { null },
                                    expires_in_days = days,
                                ),
                            )
                        }
                    },
                    onRevoke = { inviteId ->
                        mutate { revokeBoardInvite(boardId, inviteId) }
                    },
                )

                3 -> SubboardsTab(
                    subboards = subboards,
                    isOwner = isOwner,
                    busy = busy,
                    onCreate = { name ->
                        mutate {
                            createSubboard(boardId, CreateSubboardBody(name = name))
                        }
                    },
                    onReorder = { id, newPosition ->
                        mutate {
                            reorderSubboard(id, ReorderSubboardBody(position = newPosition))
                        }
                    },
                    onDelete = { id ->
                        mutate { deleteSubboard(id) }
                    },
                )

                4 -> LabelsTab(
                    labels = labels,
                    subboards = subboards,
                    isOwner = isOwner,
                    busy = busy,
                    onCreate = { name, color, subboardIds ->
                        mutate {
                            createBoardLabel(
                                boardId = boardId,
                                body = BoardLabelBody(
                                    name = name,
                                    color = color,
                                    subboard_ids = subboardIds,
                                ),
                            )
                        }
                    },
                    onDelete = { id ->
                        mutate { deleteBoardLabel(id) }
                    },
                )
            }

            error?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(16.dp),
                )
            }
        }
    }
}

@Composable
private fun SettingsTab(
    board: BoardDetail?,
    isOwner: Boolean,
    busy: Boolean,
    onSave: (name: String, description: String?, days: Int?) -> Unit,
    onDelete: () -> Unit,
) {
    if (board == null) {
        Text("Loading…", modifier = Modifier.padding(24.dp))
        return
    }
    var name by remember(board.id) { mutableStateOf(board.name) }
    var description by remember(board.id) { mutableStateOf(board.description.orEmpty()) }
    var daysText by remember(board.id) {
        mutableStateOf(board.archive_terminal_after_days?.toString() ?: "")
    }
    var confirmDelete by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.padding(16.dp).fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        OutlinedTextField(
            value = name,
            onValueChange = { name = it },
            label = { Text("Name") },
            enabled = isOwner && !busy,
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = description,
            onValueChange = { description = it },
            label = { Text("Description") },
            enabled = isOwner && !busy,
            modifier = Modifier.fillMaxWidth(),
        )
        OutlinedTextField(
            value = daysText,
            onValueChange = { daysText = it.filter { ch -> ch.isDigit() } },
            label = { Text("Auto-archive after N days (blank = never)") },
            enabled = isOwner && !busy,
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                enabled = isOwner && !busy,
                onClick = { onSave(name.trim(), description.ifBlank { null }, daysText.toIntOrNull()) },
            ) { Text(if (busy) "Saving…" else "Save") }
            OutlinedButton(
                enabled = isOwner && !busy,
                onClick = { confirmDelete = true },
            ) {
                Icon(Icons.Default.Delete, contentDescription = null); Text(" Delete board")
            }
        }

        if (!isOwner) {
            Text(
                "Only the board owner can change settings.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete this board?") },
            text = { Text("All cards and history will be wiped. This can't be undone.") },
            confirmButton = {
                Button(onClick = {
                    confirmDelete = false
                    onDelete()
                }) { Text("Delete") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun MembersTab(
    members: List<BoardMembership>,
    isOwner: Boolean,
    busy: Boolean,
    onChangeRole: (userId: String, role: String) -> Unit,
    onRemove: (userId: String) -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(members, key = { it.id }) { m ->
            MemberRow(
                membership = m,
                isOwner = isOwner,
                busy = busy,
                onChangeRole = { onChangeRole(m.user_id, it) },
                onRemove = { onRemove(m.user_id) },
            )
        }
        if (members.isEmpty()) {
            item { Text("No members yet.") }
        }
    }
}

@Composable
private fun SubboardsTab(
    subboards: List<Subboard>,
    isOwner: Boolean,
    busy: Boolean,
    onCreate: (String) -> Unit,
    onReorder: (id: String, newPosition: Int) -> Unit,
    onDelete: (String) -> Unit,
) {
    var newName by remember { mutableStateOf("") }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (isOwner) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("Add a row", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Rows split the kanban into a 2-D grid: rows down the side, stages across the top. " +
                                "Cards land in the Default row unless dragged or picked into a specific one.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedTextField(
                            value = newName,
                            onValueChange = { newName = it },
                            label = { Text("Name") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Button(
                            enabled = !busy && newName.isNotBlank(),
                            onClick = {
                                onCreate(newName.trim())
                                newName = ""
                            },
                        ) { Text("Add row") }
                    }
                }
            }
        }

        itemsIndexed(subboards, key = { _, sb -> sb.id }) { index, sb ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        sb.name,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.weight(1f).padding(top = 8.dp),
                    )
                    if (isOwner) {
                        IconButton(
                            enabled = !busy && index > 0,
                            onClick = { onReorder(sb.id, index - 1) },
                        ) {
                            Icon(Icons.Default.ArrowUpward, contentDescription = "Move up")
                        }
                        IconButton(
                            enabled = !busy && index < subboards.size - 1,
                            onClick = { onReorder(sb.id, index + 1) },
                        ) {
                            Icon(Icons.Default.ArrowDownward, contentDescription = "Move down")
                        }
                        OutlinedButton(
                            enabled = !busy,
                            onClick = { onDelete(sb.id) },
                        ) {
                            Icon(Icons.Default.Delete, contentDescription = null); Text(" Delete")
                        }
                    }
                }
            }
        }

        if (subboards.isEmpty()) {
            item {
                Text(
                    "No rows yet — every card sits in the Default row.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun LabelsTab(
    labels: List<Label>,
    subboards: List<Subboard>,
    isOwner: Boolean,
    busy: Boolean,
    onCreate: (name: String, color: String?, subboardIds: List<String>) -> Unit,
    onDelete: (String) -> Unit,
) {
    var newName by remember { mutableStateOf("") }
    var newColor by remember { mutableStateOf("") }
    val selectedSubboards = remember { mutableStateListOf<String>() }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (isOwner) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("Add a label", style = MaterialTheme.typography.titleSmall)
                        Text(
                            "Leave all rows unchecked for a board-wide label, or pick rows to " +
                                "scope it to them. Re-adding an existing name updates its color and scope.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        OutlinedTextField(
                            value = newName,
                            onValueChange = { newName = it },
                            label = { Text("Name") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        OutlinedTextField(
                            value = newColor,
                            onValueChange = { newColor = it },
                            label = { Text("Color hex (optional), e.g. #ef4444") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        if (subboards.isNotEmpty()) {
                            Text(
                                "Limit to rows",
                                style = MaterialTheme.typography.labelMedium,
                            )
                            subboards.forEach { sb ->
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    Checkbox(
                                        checked = sb.id in selectedSubboards,
                                        enabled = !busy,
                                        onCheckedChange = { on ->
                                            if (on) selectedSubboards.add(sb.id)
                                            else selectedSubboards.remove(sb.id)
                                        },
                                    )
                                    Text(sb.name, style = MaterialTheme.typography.bodyMedium)
                                }
                            }
                        }
                        Button(
                            enabled = !busy && newName.isNotBlank(),
                            onClick = {
                                onCreate(
                                    newName.trim(),
                                    newColor.trim().ifBlank { null },
                                    selectedSubboards.toList(),
                                )
                                newName = ""
                                newColor = ""
                                selectedSubboards.clear()
                            },
                        ) { Text("Add label") }
                    }
                }
            }
        }

        items(labels, key = { it.id }) { label ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    parseStageColor(label.color)?.let { c ->
                        Box(
                            modifier = Modifier
                                .size(16.dp)
                                .clip(CircleShape)
                                .background(c),
                        )
                    }
                    Column(modifier = Modifier.weight(1f)) {
                        Text(label.name, style = MaterialTheme.typography.bodyMedium)
                        val scope = if (label.subboard_ids.isEmpty()) {
                            "All rows"
                        } else {
                            subboards
                                .filter { it.id in label.subboard_ids }
                                .joinToString { it.name }
                                .ifBlank { "Scoped rows" }
                        }
                        Text(
                            scope,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    if (isOwner) {
                        OutlinedButton(enabled = !busy, onClick = { onDelete(label.id) }) {
                            Icon(Icons.Default.Delete, contentDescription = null); Text(" Delete")
                        }
                    }
                }
            }
        }

        if (labels.isEmpty()) {
            item {
                Text(
                    "No labels yet.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun MemberRow(
    membership: BoardMembership,
    isOwner: Boolean,
    busy: Boolean,
    onChangeRole: (String) -> Unit,
    onRemove: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(membership.email ?: membership.user_id.take(8), style = MaterialTheme.typography.bodyMedium)
            Text(
                "Role: ${membership.role}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (isOwner) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    listOf("owner", "editor", "viewer").forEach { role ->
                        OutlinedButton(
                            enabled = !busy && membership.role != role,
                            onClick = { onChangeRole(role) },
                        ) { Text(role) }
                    }
                    OutlinedButton(enabled = !busy, onClick = onRemove) {
                        Icon(Icons.Default.Delete, contentDescription = null); Text(" Remove")
                    }
                }
            }
        }
    }
}

@Composable
private fun InvitesTab(
    invites: List<BoardInvite>,
    isOwner: Boolean,
    busy: Boolean,
    onCreate: (role: String, note: String?, days: Int?) -> Unit,
    onRevoke: (String) -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    var newRole by remember { mutableStateOf("editor") }
    var newNote by remember { mutableStateOf("") }
    var newDays by remember { mutableStateOf("") }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (isOwner) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("New invite", style = MaterialTheme.typography.titleSmall)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            listOf("editor", "viewer").forEach { r ->
                                OutlinedButton(
                                    enabled = !busy && newRole != r,
                                    onClick = { newRole = r },
                                ) { Text(r) }
                            }
                        }
                        OutlinedTextField(
                            value = newNote,
                            onValueChange = { newNote = it },
                            label = { Text("Note (optional)") },
                            enabled = !busy,
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        OutlinedTextField(
                            value = newDays,
                            onValueChange = { newDays = it.filter { ch -> ch.isDigit() } },
                            label = { Text("Expires in N days (optional)") },
                            enabled = !busy,
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Button(
                            enabled = !busy,
                            onClick = {
                                onCreate(newRole, newNote, newDays.toIntOrNull())
                                newNote = ""
                                newDays = ""
                            },
                        ) { Text("Generate") }
                    }
                }
            }
        }

        items(invites, key = { it.id }) { invite ->
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text("Role: ${invite.role}", style = MaterialTheme.typography.labelMedium)
                    if (!invite.note.isNullOrBlank()) Text(invite.note)
                    Text(
                        invite.redemption_url,
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        OutlinedButton(onClick = {
                            clipboard.setText(AnnotatedString(invite.redemption_url))
                        }) {
                            Icon(Icons.Default.ContentCopy, contentDescription = null); Text(" Copy link")
                        }
                        if (isOwner) {
                            OutlinedButton(
                                enabled = !busy && invite.consumed_at == null,
                                onClick = { onRevoke(invite.id) },
                            ) { Text("Revoke") }
                        }
                    }
                    if (invite.consumed_at != null) {
                        Text(
                            "Consumed${invite.consumed_by_email?.let { " by $it" } ?: ""} at ${invite.consumed_at}",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        if (invites.isEmpty()) {
            item { Text("No invites yet.") }
        }
    }
}
