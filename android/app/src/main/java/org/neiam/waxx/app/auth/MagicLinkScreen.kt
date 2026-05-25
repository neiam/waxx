package org.neiam.waxx.app.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.RedeemBody
import org.neiam.waxx.app.data.RequestMagicLinkBody
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.WaxxClient
import org.neiam.waxx.app.data.extractMagicLinkToken

/**
 * Magic-link login.
 *
 * Two phases:
 *   1. Enter (server URL, email) → POST request_magic_link → server emails
 *      a `https://<host>/m/<token>` link.
 *   2. Either:
 *      - the user taps the link in their mail app and (with App Links
 *        wired up correctly) lands here with the token prefilled, OR
 *      - the user pastes the whole link / token into the field below.
 *
 *  Then POST /sessions/redeem to exchange for an API token.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MagicLinkScreen(
    prefilledToken: String?,
    tokens: TokenStore,
    onPaired: () -> Unit,
    onBack: () -> Unit,
) {
    var baseUrl by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var tokenInput by remember { mutableStateOf(prefilledToken ?: "") }
    var status by remember { mutableStateOf<MagicStatus>(MagicStatus.Idle) }
    val scope = rememberCoroutineScope()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { org.neiam.waxx.app.ui.AppBarTitle("Email me a link") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Step 1: enter your Waxx server URL and email. We'll mail you a link.",
                style = MaterialTheme.typography.bodyMedium,
            )

            OutlinedTextField(
                value = baseUrl,
                onValueChange = { baseUrl = it },
                label = { Text("Server URL") },
                placeholder = { Text("https://waxx.example.com") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
            )
            OutlinedTextField(
                value = email,
                onValueChange = { email = it },
                label = { Text("Email") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            )

            Button(
                enabled = baseUrl.isNotBlank() && email.isNotBlank()
                    && status !is MagicStatus.Sending,
                onClick = {
                    status = MagicStatus.Sending
                    scope.launch {
                        status = try {
                            WaxxClient.anon(baseUrl.trim().trimEnd('/'))
                                .requestMagicLink(RequestMagicLinkBody(email.trim()))
                            MagicStatus.Sent
                        } catch (e: Exception) {
                            MagicStatus.Error("Couldn't reach the server: ${e.message}")
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    when (status) {
                        MagicStatus.Sending -> "Sending…"
                        else -> "Send link"
                    },
                )
            }

            if (status is MagicStatus.Sent || prefilledToken != null) {
                Text(
                    "Step 2: tap the link in your inbox. If it doesn't open the app " +
                        "directly, paste the full URL or just the token below.",
                    style = MaterialTheme.typography.bodyMedium,
                )
                OutlinedTextField(
                    value = tokenInput,
                    onValueChange = { tokenInput = it },
                    label = { Text("Link or token") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )

                Button(
                    enabled = tokenInput.isNotBlank() && baseUrl.isNotBlank()
                        && status !is MagicStatus.Redeeming,
                    onClick = {
                        val token = extractMagicLinkToken(tokenInput) ?: tokenInput.trim()
                        val base = baseUrl.trim().trimEnd('/')
                        status = MagicStatus.Redeeming
                        scope.launch {
                            status = try {
                                val redeemed = WaxxClient.anon(base)
                                    .redeem(RedeemBody(token))
                                tokens.save(base, redeemed.api_token)
                                MagicStatus.Success(redeemed.user.email)
                            } catch (e: Exception) {
                                MagicStatus.Error("Couldn't redeem the link: ${e.message}")
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        when (status) {
                            MagicStatus.Redeeming -> "Redeeming…"
                            else -> "Sign in"
                        },
                    )
                }
            }

            when (val s = status) {
                MagicStatus.Idle, MagicStatus.Sending, MagicStatus.Redeeming, MagicStatus.Sent -> {}
                is MagicStatus.Success -> {
                    Text(
                        "Signed in as ${s.email}",
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Button(onClick = onPaired, modifier = Modifier.fillMaxWidth()) {
                        Text("Continue")
                    }
                }
                is MagicStatus.Error -> {
                    Text(s.message, color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

private sealed interface MagicStatus {
    data object Idle : MagicStatus
    data object Sending : MagicStatus
    data object Sent : MagicStatus
    data object Redeeming : MagicStatus
    data class Success(val email: String) : MagicStatus
    data class Error(val message: String) : MagicStatus
}
