package org.neiam.waxx.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
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
import org.neiam.waxx.app.data.CreateFieldBody
import org.neiam.waxx.app.data.CreateLabelBody
import org.neiam.waxx.app.data.CreateStageBody
import org.neiam.waxx.app.data.CreateTransitionBody
import org.neiam.waxx.app.data.Field
import org.neiam.waxx.app.data.Label
import org.neiam.waxx.app.data.Stage
import org.neiam.waxx.app.data.TemplateGraph
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.Transition
import org.neiam.waxx.app.data.UpdateFieldBody
import org.neiam.waxx.app.data.WaxxApi
import org.neiam.waxx.app.data.WaxxClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TemplateEditorScreen(
    templateId: String,
    tokens: TokenStore,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val creds = remember { tokens.load() }
    var tab by remember { mutableStateOf(0) }
    var template by remember { mutableStateOf<TemplateGraph?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }

    suspend fun reload() {
        if (creds == null) return
        try {
            template = WaxxClient.authenticated(creds).template(templateId).template
        } catch (e: Exception) {
            error = e.message
        }
    }

    LaunchedEffect(templateId) { reload() }

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
                title = { AppBarTitle(template?.name ?: "Template") },
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
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Workflow") })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Labels") })
                Tab(selected = tab == 2, onClick = { tab = 2 }, text = { Text("Fields") })
            }

            val t = template
            when {
                t == null -> Text("Loading…", modifier = Modifier.padding(24.dp))
                tab == 0 -> WorkflowTab(
                    template = t,
                    busy = busy,
                    onAddStage = { name, color ->
                        mutate { addTemplateStage(templateId, CreateStageBody(name, color)) }
                    },
                    onDeleteStage = { id ->
                        mutate { deleteTemplateStage(id) }
                    },
                    onAddTransition = { fromId, toId, label ->
                        mutate {
                            addTemplateTransition(
                                templateId,
                                CreateTransitionBody(fromId, toId, label),
                            )
                        }
                    },
                    onDeleteTransition = { id ->
                        mutate { deleteTemplateTransition(id) }
                    },
                )

                tab == 1 -> LabelsTab(
                    template = t,
                    busy = busy,
                    onAdd = { name, color ->
                        mutate { addTemplateLabel(templateId, CreateLabelBody(name, color)) }
                    },
                    onDelete = { id ->
                        mutate { deleteTemplateLabel(id) }
                    },
                )

                tab == 2 -> FieldsTab(
                    template = t,
                    busy = busy,
                    onAdd = { name, kind, options, showOnCard ->
                        mutate {
                            addTemplateField(
                                templateId,
                                CreateFieldBody(name, kind, options, showOnCard),
                            )
                        }
                    },
                    onToggleShowOnCard = { f ->
                        mutate {
                            updateTemplateField(f.id, UpdateFieldBody(show_on_card = !f.show_on_card))
                        }
                    },
                    onDelete = { id ->
                        mutate { deleteTemplateField(id) }
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
private fun WorkflowTab(
    template: TemplateGraph,
    busy: Boolean,
    onAddStage: (name: String, color: String?) -> Unit,
    onDeleteStage: (String) -> Unit,
    onAddTransition: (fromId: String, toId: String, label: String?) -> Unit,
    onDeleteTransition: (String) -> Unit,
) {
    val stagesById = remember(template) { template.stages.associateBy { it.id } }
    var newStageName by remember { mutableStateOf("") }
    var newStageColor by remember { mutableStateOf("") }

    var transFrom by remember { mutableStateOf<String?>(null) }
    var transTo by remember { mutableStateOf<String?>(null) }
    var transLabel by remember { mutableStateOf("") }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item { Text("Stages", style = MaterialTheme.typography.titleSmall) }
        items(template.stages.sortedBy { it.position }, key = { it.id }) { s ->
            StageRow(stage = s, busy = busy, onDelete = { onDeleteStage(s.id) })
        }
        item {
            Card {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Add stage", style = MaterialTheme.typography.labelLarge)
                    OutlinedTextField(
                        value = newStageName,
                        onValueChange = { newStageName = it },
                        label = { Text("Name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OutlinedTextField(
                        value = newStageColor,
                        onValueChange = { newStageColor = it },
                        label = { Text("Color (#hex, optional)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        enabled = !busy && newStageName.isNotBlank(),
                        onClick = {
                            onAddStage(newStageName.trim(), newStageColor.ifBlank { null })
                            newStageName = ""
                            newStageColor = ""
                        },
                    ) { Text("Add stage") }
                }
            }
        }

        item { Text("Transitions", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp)) }
        items(template.transitions, key = { it.id }) { tr ->
            TransitionRow(
                transition = tr,
                fromName = stagesById[tr.from_stage_id]?.name ?: "?",
                toName = stagesById[tr.to_stage_id]?.name ?: "?",
                busy = busy,
                onDelete = { onDeleteTransition(tr.id) },
            )
        }
        item {
            Card {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Add transition", style = MaterialTheme.typography.labelLarge)
                    Text("From", style = MaterialTheme.typography.labelSmall)
                    StagePicker(
                        stages = template.stages,
                        selected = transFrom,
                        onPick = { transFrom = it },
                    )
                    Text("To", style = MaterialTheme.typography.labelSmall)
                    StagePicker(
                        stages = template.stages,
                        selected = transTo,
                        onPick = { transTo = it },
                    )
                    OutlinedTextField(
                        value = transLabel,
                        onValueChange = { transLabel = it },
                        label = { Text("Label (optional)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        enabled = !busy && transFrom != null && transTo != null && transFrom != transTo,
                        onClick = {
                            onAddTransition(transFrom!!, transTo!!, transLabel.ifBlank { null })
                            transFrom = null
                            transTo = null
                            transLabel = ""
                        },
                    ) { Text("Add transition") }
                }
            }
        }
    }
}

@Composable
private fun StageRow(stage: Stage, busy: Boolean, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(stage.name, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            stage.color?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(enabled = !busy, onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete")
            }
        }
    }
}

@Composable
private fun TransitionRow(
    transition: Transition,
    fromName: String,
    toName: String,
    busy: Boolean,
    onDelete: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("$fromName → $toName", style = MaterialTheme.typography.bodyMedium)
                if (!transition.label.isNullOrBlank()) {
                    Text(
                        transition.label,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            IconButton(enabled = !busy, onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete")
            }
        }
    }
}

@Composable
private fun StagePicker(stages: List<Stage>, selected: String?, onPick: (String) -> Unit) {
    LazyColumn(modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(vertical = 2.dp)) {
        items(stages.sortedBy { it.position }, key = { it.id }) { s ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onPick(s.id) }
                    .padding(vertical = 4.dp),
            ) {
                FilterChip(
                    selected = s.id == selected,
                    onClick = { onPick(s.id) },
                    label = { Text(s.name) },
                )
            }
        }
    }
}

@Composable
private fun LabelsTab(
    template: TemplateGraph,
    busy: Boolean,
    onAdd: (name: String, color: String?) -> Unit,
    onDelete: (String) -> Unit,
) {
    var newName by remember { mutableStateOf("") }
    var newColor by remember { mutableStateOf("") }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(template.labels, key = { it.id }) { l ->
            LabelRow(label = l, busy = busy, onDelete = { onDelete(l.id) })
        }
        item {
            Card {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Add label", style = MaterialTheme.typography.labelLarge)
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
                        label = { Text("Color (#hex, optional)") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Button(
                        enabled = !busy && newName.isNotBlank(),
                        onClick = {
                            onAdd(newName.trim(), newColor.ifBlank { null })
                            newName = ""
                            newColor = ""
                        },
                    ) { Text("Add label") }
                }
            }
        }
        if (template.labels.isEmpty()) {
            item { Text("No labels yet.") }
        }
    }
}

@Composable
private fun LabelRow(label: Label, busy: Boolean, onDelete: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(label.name, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
            label.color?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            IconButton(enabled = !busy, onClick = onDelete) {
                Icon(Icons.Default.Delete, contentDescription = "Delete")
            }
        }
    }
}

@Composable
private fun FieldsTab(
    template: TemplateGraph,
    busy: Boolean,
    onAdd: (name: String, kind: String, options: List<String>?, showOnCard: Boolean) -> Unit,
    onToggleShowOnCard: (Field) -> Unit,
    onDelete: (String) -> Unit,
) {
    var newName by remember { mutableStateOf("") }
    var newKind by remember { mutableStateOf("text") }
    var newOptions by remember { mutableStateOf("") }
    var newShowOnCard by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(template.fields.sortedBy { it.position }, key = { it.id }) { f ->
            FieldRow(
                field = f,
                busy = busy,
                onToggleShowOnCard = { onToggleShowOnCard(f) },
                onDelete = { onDelete(f.id) },
            )
        }
        item {
            Card {
                Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Add field", style = MaterialTheme.typography.labelLarge)
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it },
                        label = { Text("Name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text("Kind", style = MaterialTheme.typography.labelSmall)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        listOf("text", "date", "datetime", "select").forEach { k ->
                            FilterChip(
                                selected = newKind == k,
                                onClick = { newKind = k },
                                label = { Text(k) },
                            )
                        }
                    }
                    if (newKind == "select") {
                        OutlinedTextField(
                            value = newOptions,
                            onValueChange = { newOptions = it },
                            label = { Text("Options (comma-separated)") },
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Checkbox(
                            checked = newShowOnCard,
                            onCheckedChange = { newShowOnCard = it },
                        )
                        Text("Show value on card chip")
                    }
                    Button(
                        enabled = !busy && newName.isNotBlank(),
                        onClick = {
                            val opts = if (newKind == "select") {
                                newOptions.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                            } else null
                            onAdd(newName.trim(), newKind, opts, newShowOnCard)
                            newName = ""
                            newOptions = ""
                            newShowOnCard = false
                        },
                    ) { Text("Add field") }
                }
            }
        }
        if (template.fields.isEmpty()) {
            item { Text("No fields yet.") }
        }
    }
}

@Composable
private fun FieldRow(
    field: Field,
    busy: Boolean,
    onToggleShowOnCard: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(field.name, style = MaterialTheme.typography.bodyMedium)
                    Text(
                        "kind: ${field.kind}" +
                            (if (field.kind == "select" && field.options.isNotEmpty()) " · " + field.options.joinToString(", ") else ""),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(enabled = !busy, onClick = onDelete) {
                    Icon(Icons.Default.Delete, contentDescription = "Delete")
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Switch(
                    checked = field.show_on_card,
                    enabled = !busy,
                    onCheckedChange = { onToggleShowOnCard() },
                )
                Text("Show on card chip", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}
