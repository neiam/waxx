package org.neiam.waxx.app.ui

import androidx.compose.ui.graphics.Color

/**
 * Parses a stage color stored as a hex string (`#RGB`, `#RRGGBB`,
 * `#AARRGGBB`) into a Compose [Color]. Returns null on null / blank /
 * unparseable input so callers can fall back to a Material default.
 */
fun parseStageColor(hex: String?): Color? {
    if (hex.isNullOrBlank()) return null
    val s = hex.trim().removePrefix("#")
    return runCatching {
        when (s.length) {
            6 -> Color(android.graphics.Color.parseColor("#FF$s"))
            8 -> Color(android.graphics.Color.parseColor("#$s"))
            3 -> {
                val r = s[0]; val g = s[1]; val b = s[2]
                Color(android.graphics.Color.parseColor("#FF$r$r$g$g$b$b"))
            }
            else -> null
        }
    }.getOrNull()
}
