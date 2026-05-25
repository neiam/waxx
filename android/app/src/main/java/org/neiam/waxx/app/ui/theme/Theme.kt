package org.neiam.waxx.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider

/**
 * Wrap composables to apply the selected Waxx palette + B612 typography.
 * Pass `theme` down through `LocalAppTheme` so screen code can read the
 * bespoke colors (e.g. `liveGreen`) that don't fit cleanly into
 * Material's slot system.
 */
@Composable
fun WaxxTheme(theme: AppTheme, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalAppTheme provides theme) {
        MaterialTheme(
            colorScheme = theme.toColorScheme(),
            typography = WaxxTypography,
            content = content,
        )
    }
}
