package org.neiam.waxx.app.data

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Persists the chosen theme key (an entry in `ALL_THEMES`). Stored in a
 * separate EncryptedSharedPreferences file from credentials so a token
 * reset doesn't clobber the theme.
 */
class ThemeStore(context: Context) {
    private val prefs by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "waxx_prefs",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    var themeKey: String?
        get() = prefs.getString(KEY_THEME, null)
        set(value) {
            prefs.edit().also { e ->
                if (value == null) e.remove(KEY_THEME) else e.putString(KEY_THEME, value)
            }.apply()
        }

    companion object { private const val KEY_THEME = "theme_key" }
}
