package org.neiam.waxx.app.data

import android.net.Uri

/**
 * Parses the `waxx://pair?base=<server>&token=<api-token>` URI emitted by
 * the web /users/settings page. Returns null on any malformed input so the
 * caller can show a friendly error rather than crashing.
 */
data class PairPayload(val baseUrl: String, val token: String) {
    companion object {
        fun parse(raw: String?): PairPayload? {
            raw ?: return null
            val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return null
            if (!uri.scheme.equals("waxx", ignoreCase = true)) return null
            if (!uri.host.equals("pair", ignoreCase = true)) return null
            val base = uri.getQueryParameter("base")?.takeIf { it.isNotBlank() } ?: return null
            val token = uri.getQueryParameter("token")?.takeIf { it.isNotBlank() } ?: return null
            val baseUri = runCatching { Uri.parse(base) }.getOrNull() ?: return null
            if (baseUri.scheme != "http" && baseUri.scheme != "https") return null
            return PairPayload(base.trimEnd('/'), token)
        }
    }
}
