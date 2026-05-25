package org.neiam.waxx.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.CreateTemplateBody
import org.neiam.waxx.app.data.TemplateSummary
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.WaxxClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TemplatesListScreen(
    tokens: TokenStore,
    onBack: () -> Unit,
    onOpenTemplate: (String) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val creds = remember { tokens.load() }
    var templates by remember { mutableStateOf<List<TemplateSummary>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var showCreate by remember { mutableStateOf(false) }

    suspend fun reload() {
        if (creds == null) return
        try {
            templates = WaxxClient.authenticated(creds).templates().templates
        } catch (e: Exception) {
            error = e.message
        }
    }

    LaunchedEffect(Unit) { reload() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { AppBarTitle("Workflow templates") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
        floatingActionButton = {
            if (creds != null) {
                FloatingActionButton(onClick = { showCreate = true }) {
                    Icon(Icons.Default.Add, contentDescription = "New template")
                }
            }
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(templates, key = { it.id }) { t ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpenTemplate(t.id) },
                ) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(t.name, style = MaterialTheme.typography.titleMedium)
                        if (!t.description.isNullOrBlank()) {
                            Text(
                                t.description,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            if (templates.isEmpty()) {
                item {
                    Text(
                        "No templates yet. Tap + to create one.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
            error?.let {
                item {
                    Text(it, color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }

    if (showCreate && creds != null) {
        var newName by remember { mutableStateOf("") }
        var newDesc by remember { mutableStateOf("") }

        AlertDialog(
            onDismissRequest = { showCreate = false },
            title = { Text("New template") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("Name") },
                        singleLine = true,
                    )
                    OutlinedTextField(
                        value = newDesc,
                        onValueChange = { newDesc = it },
                        label = { Text("Description (optional)") },
                    )
                }
            },
            confirmButton = {
                Button(
                    enabled = !busy && newName.isNotBlank(),
                    onClick = {
                        scope.launch {
                            busy = true
                            try {
                                WaxxClient.authenticated(creds).createTemplate(
                                    CreateTemplateBody(
                                        name = newName.trim(),
                                        description = newDesc.ifBlank { null },
                                    ),
                                )
                                reload()
                                showCreate = false
                            } catch (e: Exception) {
                                error = e.message
                            } finally {
                                busy = false
                            }
                        }
                    },
                ) { Text("Create") }
            },
            dismissButton = {
                TextButton(onClick = { showCreate = false }) { Text("Cancel") }
            },
        )
    }
}
