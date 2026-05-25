package org.neiam.waxx.app.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Persists the (base URL, API token) pair into EncryptedSharedPreferences
 * so other apps with shared-uid access can't sniff it. The pair is the
 * only authentication state the app holds.
 */
class TokenStore(context: Context) {
    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "waxx_secure",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun save(baseUrl: String, token: String) {
        prefs.edit()
            .putString(KEY_BASE_URL, coerceToHttps(baseUrl.trimEnd('/')))
            .putString(KEY_TOKEN, token)
            .apply()
    }

    fun load(): Credentials? {
        val storedBase = prefs.getString(KEY_BASE_URL, null) ?: return null
        val token = prefs.getString(KEY_TOKEN, null) ?: return null

        // Self-heal already-paired devices whose stored baseUrl predates
        // the coercion-on-save logic. If we mutate the value, persist the
        // upgraded form so we only do this once per install.
        val base = coerceToHttps(storedBase)
        if (base != storedBase) {
            prefs.edit().putString(KEY_BASE_URL, base).apply()
        }
        return Credentials(base, token)
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    data class Credentials(val baseUrl: String, val token: String)

    companion object {
        private const val KEY_BASE_URL = "base_url"
        private const val KEY_TOKEN = "token"

        /**
         * Upgrade `http://host` to `https://host` for FQDN hosts. Leaves
         * IPs, `localhost`, and bare hostnames alone — those are dev /
         * LAN setups (emulator on `10.0.2.2`, LAN-IP self-hosting, etc.)
         * where plaintext is the only thing that works.
         *
         * Reason: when an older QR was generated before the server's
         * `WaxxWeb.PublicUrl` knew how to read `X-Forwarded-Proto` on its
         * own, the encoded base could end up as `http://waxx.example.com`
         * behind a TLS-terminated proxy. The proxy then 301s the WebSocket
         * upgrade — fatal to phoenix-channels. Coercing here recovers
         * already-paired devices without re-pairing.
         */
        internal fun coerceToHttps(url: String): String {
            if (!url.startsWith("http://", ignoreCase = true)) return url
            val host = runCatching { android.net.Uri.parse(url).host }.getOrNull()
                ?: return url
            return if (looksLocal(host)) url else "https://" + url.substring("http://".length)
        }

        private fun looksLocal(host: String): Boolean {
            val h = host.lowercase()
            if (h == "localhost") return true
            // unqualified hostname (no dot) — bare devbox name
            if (!h.contains('.')) return true
            // IPv6 literal
            if (h.contains(':')) return true
            // IPv4 dotted-quad
            val octets = h.split('.')
            if (octets.size == 4 && octets.all { it.toIntOrNull() in 0..255 }) return true
            return false
        }
    }
}

