package org.neiam.waxx.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.BoardSummary
import org.neiam.waxx.app.data.CreateBoardBody
import org.neiam.waxx.app.data.TemplateSummary
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.WaxxClient
import org.neiam.waxx.app.ui.theme.ALL_THEMES
import org.neiam.waxx.app.ui.theme.AppTheme

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BoardsListScreen(
    tokens: TokenStore,
    currentTheme: AppTheme,
    onPickTheme: (AppTheme) -> Unit,
    onOpenBoard: (String) -> Unit,
    onOpenAppInvites: () -> Unit,
    onOpenTemplates: () -> Unit,
    onUnpair: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf<BoardsState>(BoardsState.Loading) }
    var menuOpen by remember { mutableStateOf(false) }
    var themePickerOpen by remember { mutableStateOf(false) }
    var createOpen by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        val creds = tokens.load()
        state = if (creds == null) {
            BoardsState.Error("Not paired.")
        } else {
            try {
                val response = WaxxClient.authenticated(creds).boards()
                BoardsState.Loaded(response.boards)
            } catch (e: Exception) {
                BoardsState.Error(e.message ?: "Couldn't load boards.")
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { AppBarTitle("Boards") },
                actions = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "Menu")
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Theme: ${currentTheme.name}") },
                            onClick = {
                                menuOpen = false
                                themePickerOpen = true
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Workflow templates") },
                            onClick = {
                                menuOpen = false
                                onOpenTemplates()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Registration invites") },
                            onClick = {
                                menuOpen = false
                                onOpenAppInvites()
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("Sign out") },
                            leadingIcon = {
                                Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = null)
                            },
                            onClick = {
                                menuOpen = false
                                onUnpair()
                            },
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            FloatingActionButton(onClick = { createOpen = true }) {
                Icon(Icons.Default.Add, contentDescription = "New board")
            }
        },
    ) { padding ->
        when (val s = state) {
            BoardsState.Loading -> CenterText("Loading…", Modifier.padding(padding))
            is BoardsState.Error -> CenterText("Error: ${s.message}", Modifier.padding(padding))
            is BoardsState.Loaded ->
                if (s.boards.isEmpty()) {
                    CenterText(
                        "No boards yet. Create one in the web UI.",
                        Modifier.padding(padding),
                    )
                } else {
                    LazyColumn(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(padding),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(s.boards, key = { it.id }) { board ->
                            BoardRow(board = board, onClick = { onOpenBoard(board.id) })
                        }
                    }
                }
        }
    }

    if (themePickerOpen) {
        ThemePickerDialog(
            current = currentTheme,
            onDismiss = { themePickerOpen = false },
            onPick = { picked ->
                themePickerOpen = false
                onPickTheme(picked)
            },
        )
    }

    val creds = remember { tokens.load() }
    if (createOpen && creds != null) {
        CreateBoardDialog(
            tokens = tokens,
            onDismiss = { createOpen = false },
            onCreated = { newId ->
                createOpen = false
                onOpenBoard(newId)
            },
        )
    }
}

@Composable
private fun CreateBoardDialog(
    tokens: TokenStore,
    onDismiss: () -> Unit,
    onCreated: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val creds = remember { tokens.load() }
    var templates by remember { mutableStateOf<List<TemplateSummary>>(emptyList()) }
    var selectedTemplate by remember { mutableStateOf<String?>(null) }
    var name by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        if (creds != null) {
            try {
                templates = WaxxClient.authenticated(creds).templates().templates
            } catch (e: Exception) {
                error = e.message
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("New board") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                )
                Text("Template", style = MaterialTheme.typography.labelMedium)
                if (templates.isEmpty()) {
                    Text(
                        "No templates yet — create one from the Workflow templates menu first.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                templates.forEach { t ->
                    FilterChip(
                        selected = selectedTemplate == t.id,
                        onClick = { selectedTemplate = t.id },
                        label = { Text(t.name) },
                    )
                }
                error?.let {
                    Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
            }
        },
        confirmButton = {
            Button(
                enabled = !busy && name.isNotBlank() && selectedTemplate != null,
                onClick = {
                    if (creds != null) {
                        scope.launch {
                            busy = true
                            try {
                                val board = WaxxClient.authenticated(creds).createBoard(
                                    CreateBoardBody(
                                        template_id = selectedTemplate!!,
                                        name = name.trim(),
                                    ),
                                ).board
                                onCreated(board.id)
                            } catch (e: Exception) {
                                error = e.message
                            } finally {
                                busy = false
                            }
                        }
                    }
                },
            ) { Text(if (busy) "Creating…" else "Create") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}

@Composable
private fun BoardRow(board: BoardSummary, onClick: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(board.name, style = MaterialTheme.typography.titleMedium)
            if (!board.description.isNullOrBlank()) {
                Text(
                    board.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                "Role: ${board.role ?: "—"}",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun CenterText(text: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(text, style = MaterialTheme.typography.bodyLarge)
    }
}

private sealed interface BoardsState {
    data object Loading : BoardsState
    data class Loaded(val boards: List<BoardSummary>) : BoardsState
    data class Error(val message: String) : BoardsState
}

// Theme picker also lives in this file so the dropdown wiring is local.
@Composable
private fun ThemePickerDialog(
    current: AppTheme,
    onDismiss: () -> Unit,
    onPick: (AppTheme) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Theme") },
        text = {
            Column {
                ALL_THEMES.forEach { theme ->
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onPick(theme) }
                            .padding(vertical = 4.dp),
                    ) {
                        RadioButton(
                            selected = theme.key == current.key,
                            onClick = { onPick(theme) },
                        )
                        Spacer(Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(theme.name)
                            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Swatch(theme.bg)
                                Swatch(theme.cardBg)
                                Swatch(theme.primary)
                                Swatch(theme.accent)
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
    )
}

@Composable
private fun Swatch(color: Color) {
    Box(modifier = Modifier.size(12.dp)) {
        Surface(color = color, shape = CircleShape, modifier = Modifier.size(12.dp), content = {})
    }
}
