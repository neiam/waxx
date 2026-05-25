package org.neiam.waxx.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.AppInvite
import org.neiam.waxx.app.data.CreateAppInviteBody
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.WaxxApi
import org.neiam.waxx.app.data.WaxxClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppInvitesScreen(
    tokens: TokenStore,
    onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val creds = remember { tokens.load() }
    val clipboard = LocalClipboardManager.current

    var invites by remember { mutableStateOf<List<AppInvite>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var newNote by remember { mutableStateOf("") }
    var newDays by remember { mutableStateOf("") }

    suspend fun reload() {
        if (creds == null) return
        try {
            invites = WaxxClient.authenticated(creds).appInvites().invites
        } catch (e: Exception) {
            error = e.message
        }
    }

    LaunchedEffect(Unit) { reload() }

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
                title = { AppBarTitle("Registration invites") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text("Mint a registration link", style = MaterialTheme.typography.titleSmall)
                        OutlinedTextField(
                            value = newNote,
                            onValueChange = { newNote = it },
                            label = { Text("Note (e.g. who it's for)") },
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
                                mutate {
                                    createAppInvite(
                                        body = CreateAppInviteBody(
                                            note = newNote.ifBlank { null },
                                            expires_in_days = newDays.toIntOrNull(),
                                        ),
                                    )
                                }
                                newNote = ""
                                newDays = ""
                            },
                        ) { Text("Generate") }
                    }
                }
            }

            items(invites, key = { it.id }) { invite ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (!invite.note.isNullOrBlank()) Text(invite.note, style = MaterialTheme.typography.bodyMedium)
                        Text(invite.redemption_url, style = MaterialTheme.typography.bodySmall)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedButton(onClick = {
                                clipboard.setText(AnnotatedString(invite.redemption_url))
                            }) {
                                Icon(Icons.Default.ContentCopy, contentDescription = null); Text(" Copy link")
                            }
                            OutlinedButton(
                                enabled = !busy && invite.consumed_at == null,
                                onClick = { mutate { revokeAppInvite(invite.id) } },
                            ) { Text("Revoke") }
                        }
                        if (invite.consumed_at != null) {
                            Text(
                                "Consumed${invite.consumed_by_email?.let { " by $it" } ?: ""}",
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

            error?.let {
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
}
