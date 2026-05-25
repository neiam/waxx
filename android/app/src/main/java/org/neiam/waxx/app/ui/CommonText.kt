package org.neiam.waxx.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.text.font.FontWeight
import org.neiam.waxx.app.ui.theme.B612

/**
 * Title style for `TopAppBar` slots — accent color + B612 Bold. Picks
 * `MaterialTheme.colorScheme.secondary` since the theme palette maps the
 * bespoke `accent` color into the Material `secondary` slot
 * (`AppTheme.toColorScheme`).
 */
@Composable
fun AppBarTitle(text: String) {
    Text(
        text = text,
        color = MaterialTheme.colorScheme.secondary,
        fontFamily = B612,
        fontWeight = FontWeight.Bold,
        style = MaterialTheme.typography.titleLarge,
    )
}
