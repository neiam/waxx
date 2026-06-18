# Waxx Android client

Native Android client for [Waxx](../). Talks to the JSON API at
`/api/v1/...` and the realtime channel at `/socket`. Sister app to
`../dms/android` — shares the same Compose / OKLCh palette / B612-mono
shell so they feel like one product family.

Every phase (0–6 plus 5b) of the rollout in [docs/android.md](../docs/android.md)
is shipped: auth (QR pair + magic link), read-only boards, real-time
updates, card writes, labels/fields/assignees/notes, drag-and-drop
(with within-column reorder + auto-scroll), board settings + invites +
app invites, subboards (2-D grid view with reordering), board-label
management (add/recolor/delete, optionally scoped to specific rows), the
workflow template editor, the 9-theme picker, and the IconKitchen launcher
icon.

## Stack

| Layer | Choice |
|---|---|
| Language / UI | Kotlin 2.0 · Jetpack Compose · Material 3 |
| HTTP | Retrofit · OkHttp · kotlinx.serialization |
| Realtime | `com.github.dsrees:JavaPhoenixClient` (0.3.4, via jitpack) |
| Storage | EncryptedSharedPreferences (AES via the Android Keystore) |
| Scanner | `com.journeyapps:zxing-android-embedded` (`ScanContract`) |
| Build | Gradle 9.0 · AGP 8.5.2 · JDK 17 |
| minSdk | 26 (Android 8) · targetSdk 34 |

Single-activity, single-module, no DI framework — dependencies are
constructed inline. Adding Hilt when the screen count justifies it is
a fine follow-up.

## Layout

```
android/
  app/
    build.gradle.kts
    proguard-rules.pro
    src/main/
      AndroidManifest.xml
      java/org/neiam/waxx/app/
        MainActivity.kt              # nav host, deep-link dispatch, theme provider
        data/
          TokenStore.kt              # bearer + base URL (https-coerced)
          ThemeStore.kt              # selected theme key
          WaxxClient.kt              # Retrofit interfaces + factories
          WaxxSocket.kt              # Phoenix channels wrapper → Flow<BoardEvent>
          PairPayload.kt             # waxx://pair URI parser
          Models.kt                  # all the JSON DTOs
        auth/
          LoginScreen.kt             # two-button picker
          PairScreen.kt              # QR scan + paste fallback
          MagicLinkScreen.kt         # request → wait-for-link → redeem
        ui/
          BoardsScreen.kt            # boards list + theme picker dropdown
          BoardScreen.kt             # kanban view (1-D or 2-D grid) + DnD + FAB
          BoardSettingsScreen.kt     # 5-tab: Settings / Members / Invites / Rows / Labels
          AppInvitesScreen.kt        # registration invites
          CardSheet.kt               # bottom sheet: title/move/labels/fields/notes
          HistoryScreen.kt           # activity log
          CommonText.kt              # AppBarTitle (accent + B612 Bold)
          DragState.kt               # cell-based DnD state (stage × subboard)
          theme/
            AppTheme.kt              # 9 themes (Light, Blueprint, 7 OKLCh)
            Theme.kt                 # WaxxTheme wrapper
            Typography.kt            # B612 mono on every Material slot
      res/
        font/                        # B612 regular + bold
        mipmap-*/                    # IconKitchen launcher icon
        values/, xml/
  build.gradle.kts, settings.gradle.kts, gradle.properties, gradlew
  gradle/{wrapper, libs.versions.toml}
```

## Building

```sh
cd android
./gradlew :app:assembleDebug
```

Produces `app/build/outputs/apk/debug/app-debug.apk`. First-run
downloads Gradle and ~200 MB of dependency jars; subsequent builds are
~5 s incremental.

Install on a running emulator / device:

```sh
./gradlew :app:installDebug
# or:
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

## Running against a local Phoenix dev server

1. Start the Phoenix dev server (`mix phx.server` in the repo root).
   It binds to `http://localhost:4000` by default.
2. From the Android emulator, the host machine is reachable as
   `http://10.0.2.2:4000`. From a physical device on the same LAN,
   use the host's LAN IP (e.g. `http://192.168.1.50:4000`).
3. Pair the device using one of:
   - **QR**: log in on the web, go to Settings → Connected devices →
     Generate. The QR encodes `waxx://pair?base=<derived url>&token=<...>`.
     The server uses `WAXX_PUBLIC_URL` / `X-Forwarded-*` / `Host` to
     pick the URL — for emulator testing, set
     `WAXX_PUBLIC_URL=http://10.0.2.2:4000` before starting Phoenix so
     the QR points at the right host.
   - **Magic link**: enter the same server URL and your email. Tap the
     link in the dev mailbox (`/dev/mailbox`) and paste it into the
     second step.

`TokenStore` coerces `http://<fqdn>` to `https://<fqdn>` on save and
load — IPs, `localhost`, and unqualified hostnames are left alone so
the LAN / emulator paths still work.

## Themes

`Settings` → ⋮ (top-right of Boards list) → **Theme** offers 9 palettes:

- **Light** — Material 3 baseline (light scheme).
- **Blueprint** — navy + cyan, mirrors the daisyUI `blueprint` web
  theme.
- **Her / After Dark / Forest / Sky / Clays / Stones / Dark** — the
  shared OKLCh palette set used across the Casabeza Android apps.

Selection persists in a dedicated `waxx_prefs` EncryptedSharedPreferences
file (separate from credentials so signing out doesn't clobber it).
TopAppBar titles render in the theme's accent color with B612 Bold.

## Realtime

`WaxxSocket.subscribeBoard(creds, boardId)` returns a `Flow<BoardEvent>`
(`Connected | Joined | Disconnected | CardsChanged | WorkflowChanged |
Error`). `BoardScreen` runs a `DisposableEffect` that subscribes on
enter, refetches the affected resource on each push, and disposes on
exit. A top banner shows "Connecting…" / "Offline — changes won't sync
until reconnect." outside the Live state.

The Phoenix channels client (JavaPhoenixClient 0.3.4) handles reconnect
backoff itself. One socket per Flow keeps the lifecycle simple — the
0.3.x API doesn't expose `off()` on socket-level listeners.

## Drag and drop

`DragState` tracks cells by `(stageId, subboardId?)`, so the same code
covers the 1-D layout (subboardId always null) and the 2-D grid
(subboards present). Long-press a card chip to start dragging; columns
paint a translucent overlay during the drag:

- grey for the source column,
- green for valid targets (transition exists),
- red for forbidden.

Dropping into a cross-subboard cell calls `moveCardWithSubboard`, which
moves stage and re-assigns the row in one server call. The server is
still authoritative — an apparently-valid drop with stale workflow
data still gets `422 invalid_transition` and the chip snaps back on
the next refresh.

## Production behind a reverse proxy

If you serve Phoenix behind Traefik / nginx / similar with TLS
termination at the edge, the proxy MUST forward `X-Forwarded-Proto:
https`. `WaxxWeb.PublicUrl.derive/1` uses this to encode the right
scheme in the pairing QR (and everywhere else).

Phoenix's `force_ssl` is **off** in `config/prod.exs` — the comment
there explains the trade-off. The edge proxy handles the http→https
redirect at L7; if Phoenix did it too, any request whose
`X-Forwarded-Proto` got lost would 301 the WebSocket upgrade and
break realtime. If you need HSTS, add the headers via
`put_secure_browser_headers` instead.

## Keystores

Two keystores need to exist for App Links to work:

- **Debug** — auto-generated by AGP at `~/.android/debug.keystore`.
  Its SHA-256 fingerprint goes in `assetlinks.json`'s first slot.
- **Release** — generated manually and stored externally (not
  committed). Its fingerprint goes in `assetlinks.json`'s second
  slot.

Generate a release keystore:

```sh
keytool -genkeypair -v \
  -keystore waxx-release.jks \
  -alias waxx-release \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass <strong-password> -keypass <strong-password> \
  -dname "CN=Waxx, OU=Waxx, O=neiam, L=, S=, C=US"
```

Read both fingerprints:

```sh
keytool -list -v -keystore waxx-release.jks -alias waxx-release | grep SHA256
keytool -list -v -keystore ~/.android/debug.keystore \
  -storepass android -alias androiddebugkey | grep SHA256
```

Paste them into `../priv/static/.well-known/assetlinks.json` (replacing
the placeholders) and redeploy. The file is then served at
`https://<host>/.well-known/assetlinks.json`. The Android `autoVerify`
intent filter validates this on first install — if it fails, App Links
silently fall back to the default-handler chooser, and the QR /
paste-the-link paths in the app still work.

## App Links domain

The manifest's App Links intent filter is configured via the
`appLinksHost` placeholder in `app/build.gradle.kts`, defaulting to
`waxx.example.com`. Edit when the production domain is finalized.

## Launcher icon

The icon is an [IconKitchen](https://icon.kitchen) adaptive set
sourced from `../icons/kitchen/IconKitchen-Output/android/res/`. To
regenerate: re-export from IconKitchen, drop `android/res/mipmap-*`
into `app/src/main/res/`, and rebuild. The `mipmap-anydpi-v26/ic_launcher.xml`
references three layers (background / foreground / monochrome) so the
launcher renders the masked + themed-icon-style versions correctly on
modern Android.

## What's not shipped yet

- **User preferences sync** — the theme picker stores the chosen
  palette in local-only `EncryptedSharedPreferences`. A
  `PATCH /api/v1/users/me/preferences` endpoint would let it
  round-trip with the web's `users.preferences` jsonb so the same
  theme follows a user across devices. Waiting for an ask.
- **Per-token socket id** — `Accounts.delete_api_token/2` broadcasts
  on the user's socket topic, which kicks *all* of that user's live
  channels. The revoked token's reconnect 401s, the others reconnect
  cleanly — brief disruption is the trade-off. Threading per-token
  socket ids through `UserSocket.id/1` would localize the revoke.
- **Default invite role / note suggestions** — bare form today.
