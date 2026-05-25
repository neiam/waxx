package org.neiam.waxx.app.auth

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.QrCodeScanner
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
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import kotlinx.coroutines.launch
import org.neiam.waxx.app.data.PairPayload
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.WaxxClient

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PairScreen(
    prefilled: PairPayload?,
    tokens: TokenStore,
    onPaired: () -> Unit,
    onBack: () -> Unit,
) {
    var baseUrl by remember { mutableStateOf(prefilled?.baseUrl ?: "") }
    var token by remember { mutableStateOf(prefilled?.token ?: "") }
    var status by remember { mutableStateOf<PairStatus>(PairStatus.Idle) }
    val scope = rememberCoroutineScope()

    val scanLauncher = rememberLauncherForActivityResult(ScanContract()) { result ->
        val raw = result.contents ?: return@rememberLauncherForActivityResult
        val parsed = PairPayload.parse(raw)
        if (parsed != null) {
            baseUrl = parsed.baseUrl
            token = parsed.token
            status = PairStatus.Idle
        } else {
            status = PairStatus.Error("QR didn't look like a Waxx pair URI: $raw")
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { org.neiam.waxx.app.ui.AppBarTitle("Pair with Waxx") },
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
                "Generate a token in the web UI under Settings → Connected devices, " +
                    "then scan the QR. You can also paste the URI / fields directly.",
                style = MaterialTheme.typography.bodyMedium,
            )

            Button(
                onClick = {
                    scanLauncher.launch(
                        ScanOptions().apply {
                            setPrompt("Point at the Waxx pairing QR")
                            setBeepEnabled(false)
                            setOrientationLocked(false)
                            captureActivity = com.journeyapps.barcodescanner.CaptureActivity::class.java
                        },
                    )
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.QrCodeScanner, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Scan QR")
            }

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
                value = token,
                onValueChange = { token = it },
                label = { Text("API token") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Button(
                enabled = baseUrl.isNotBlank() && token.isNotBlank() && status !is PairStatus.Verifying,
                onClick = {
                    val creds = TokenStore.Credentials(baseUrl.trim().trimEnd('/'), token.trim())
                    status = PairStatus.Verifying
                    scope.launch {
                        status = try {
                            val api = WaxxClient.authenticated(creds)
                            val me = api.me()
                            tokens.save(creds.baseUrl, creds.token)
                            PairStatus.Success(me.email)
                        } catch (e: Exception) {
                            PairStatus.Error("Couldn't reach the server: ${e.message}")
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(if (status is PairStatus.Verifying) "Verifying…" else "Connect")
            }

            when (val s = status) {
                PairStatus.Idle, PairStatus.Verifying -> {}
                is PairStatus.Success -> {
                    Text(
                        "Connected as ${s.email}",
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Button(onClick = onPaired, modifier = Modifier.fillMaxWidth()) {
                        Text("Continue")
                    }
                }
                is PairStatus.Error -> {
                    Text(s.message, color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}

private sealed interface PairStatus {
    data object Idle : PairStatus
    data object Verifying : PairStatus
    data class Success(val email: String) : PairStatus
    data class Error(val message: String) : PairStatus
}
