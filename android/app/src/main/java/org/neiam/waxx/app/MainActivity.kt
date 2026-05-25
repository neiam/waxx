package org.neiam.waxx.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import kotlinx.coroutines.flow.MutableStateFlow
import org.neiam.waxx.app.auth.LoginScreen
import org.neiam.waxx.app.auth.MagicLinkScreen
import org.neiam.waxx.app.auth.PairScreen
import org.neiam.waxx.app.data.BoardMembership
import org.neiam.waxx.app.data.CardSummary
import org.neiam.waxx.app.data.PairPayload
import org.neiam.waxx.app.data.ThemeStore
import org.neiam.waxx.app.data.TokenStore
import org.neiam.waxx.app.data.Workflow
import org.neiam.waxx.app.data.extractMagicLinkToken
import org.neiam.waxx.app.ui.AppInvitesScreen
import org.neiam.waxx.app.ui.BoardScreen
import org.neiam.waxx.app.ui.BoardSettingsScreen
import org.neiam.waxx.app.ui.BoardsListScreen
import org.neiam.waxx.app.ui.CardSheet
import org.neiam.waxx.app.ui.HistoryScreen
import org.neiam.waxx.app.ui.TemplateEditorScreen
import org.neiam.waxx.app.ui.TemplatesListScreen
import org.neiam.waxx.app.ui.theme.ALL_THEMES
import org.neiam.waxx.app.ui.theme.AppTheme
import org.neiam.waxx.app.ui.theme.WaxxTheme
import org.neiam.waxx.app.ui.theme.appThemeByKey

/**
 * Single-activity host. Routes:
 *   - "login"   — two-button screen (email magic link / scan QR)
 *   - "magic"   — magic-link request + paste/wait
 *   - "pair"    — QR scan + manual base/token paste
 *   - "boards"  — post-auth stub
 *
 * Deep-link entry points:
 *   - waxx://pair?base=...&token=...   → prefilled "pair" route
 *   - https://<host>/m/<token>         → prefilled "magic" route (App Link)
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val tokens = TokenStore(this)
        val themeStore = ThemeStore(this)
        val initialDeepLink = parseIntent(intent)

        setContent {
            var theme by remember {
                mutableStateOf(themeStore.themeKey?.let(::appThemeByKey) ?: ALL_THEMES.first())
            }
            WaxxTheme(theme = theme) {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    WaxxApp(
                        tokens = tokens,
                        initialDeepLink = initialDeepLink,
                        currentTheme = theme,
                        onPickTheme = { picked ->
                            theme = picked
                            themeStore.themeKey = picked.key
                        },
                    )
                }
            }
        }
    }

    private fun parseIntent(intent: Intent?): DeepLink? {
        if (intent?.action != Intent.ACTION_VIEW) return null
        val url = intent.data?.toString() ?: return null
        PairPayload.parse(url)?.let { return DeepLink.Pair(it) }
        extractMagicLinkToken(url)?.let { return DeepLink.MagicLink(it) }
        return null
    }
}

sealed interface DeepLink {
    data class Pair(val payload: PairPayload) : DeepLink
    data class MagicLink(val token: String) : DeepLink
}

@androidx.compose.runtime.Composable
fun WaxxApp(
    tokens: TokenStore,
    initialDeepLink: DeepLink?,
    currentTheme: AppTheme,
    onPickTheme: (AppTheme) -> Unit,
) {
    val nav = rememberNavController()
    val startDestination = remember(tokens, initialDeepLink) {
        when {
            initialDeepLink is DeepLink.Pair -> "pair"
            initialDeepLink is DeepLink.MagicLink -> "magic"
            tokens.load() != null -> "boards"
            else -> "login"
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(navController = nav, startDestination = startDestination) {
            composable("login") {
                LoginScreen(
                    onPickMagicLink = { nav.navigate("magic") },
                    onPickQr = { nav.navigate("pair") },
                )
            }
            composable("magic") {
                val prefilledToken = (initialDeepLink as? DeepLink.MagicLink)?.token
                MagicLinkScreen(
                    prefilledToken = prefilledToken,
                    tokens = tokens,
                    onPaired = { nav.navigate("boards") { popUpTo(0) } },
                    onBack = { nav.popBackStack() },
                )
            }
            composable("pair") {
                val prefilled = (initialDeepLink as? DeepLink.Pair)?.payload
                PairScreen(
                    prefilled = prefilled,
                    tokens = tokens,
                    onPaired = { nav.navigate("boards") { popUpTo(0) } },
                    onBack = { nav.popBackStack() },
                )
            }
            composable("boards") {
                BoardsListScreen(
                    tokens = tokens,
                    currentTheme = currentTheme,
                    onPickTheme = onPickTheme,
                    onOpenBoard = { boardId -> nav.navigate("board/$boardId") },
                    onOpenAppInvites = { nav.navigate("app_invites") },
                    onOpenTemplates = { nav.navigate("templates") },
                    onUnpair = {
                        tokens.clear()
                        nav.navigate("login") { popUpTo(0) }
                    },
                )
            }
            composable("app_invites") {
                AppInvitesScreen(
                    tokens = tokens,
                    onBack = { nav.popBackStack() },
                )
            }
            composable("templates") {
                TemplatesListScreen(
                    tokens = tokens,
                    onBack = { nav.popBackStack() },
                    onOpenTemplate = { id -> nav.navigate("template/$id") },
                )
            }
            composable(
                route = "template/{id}",
                arguments = listOf(navArgument("id") { type = NavType.StringType }),
            ) { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                TemplateEditorScreen(
                    templateId = id,
                    tokens = tokens,
                    onBack = { nav.popBackStack() },
                )
            }
            composable(
                route = "settings/{id}",
                arguments = listOf(navArgument("id") { type = NavType.StringType }),
            ) { entry ->
                val boardId = entry.arguments?.getString("id") ?: return@composable
                BoardSettingsScreen(
                    boardId = boardId,
                    tokens = tokens,
                    onBack = { nav.popBackStack() },
                    onDeleted = { nav.navigate("boards") { popUpTo(0) } },
                )
            }
            composable(
                route = "board/{id}",
                arguments = listOf(navArgument("id") { type = NavType.StringType }),
            ) { entry ->
                val boardId = entry.arguments?.getString("id") ?: return@composable
                var selectedCard by remember { mutableStateOf<CardSummary?>(null) }
                // Workflow + members get stashed by BoardScreen so the sheet
                // has names/relations to render against without re-fetching.
                val workflowSlot = remember { MutableStateFlow<Workflow?>(null) }
                val membersSlot = remember { MutableStateFlow<List<BoardMembership>>(emptyList()) }

                BoardScreen(
                    boardId = boardId,
                    tokens = tokens,
                    onBack = { nav.popBackStack() },
                    onOpenHistory = { id -> nav.navigate("history/$id") },
                    onOpenCard = { selectedCard = it },
                    onOpenSettings = { id -> nav.navigate("settings/$id") },
                    onWorkflowLoaded = { workflowSlot.value = it },
                    onMembersLoaded = { membersSlot.value = it },
                )

                selectedCard?.let { c ->
                    CardSheet(
                        initialCard = c,
                        workflow = workflowSlot.value,
                        members = membersSlot.value,
                        creds = tokens.load(),
                        onDismiss = { selectedCard = null },
                    )
                }
            }
            composable(
                route = "history/{id}",
                arguments = listOf(navArgument("id") { type = NavType.StringType }),
            ) { entry ->
                val boardId = entry.arguments?.getString("id") ?: return@composable
                HistoryScreen(
                    boardId = boardId,
                    tokens = tokens,
                    onBack = { nav.popBackStack() },
                )
            }
        }
    }
}
