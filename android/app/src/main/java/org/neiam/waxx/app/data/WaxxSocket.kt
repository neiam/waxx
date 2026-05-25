package org.neiam.waxx.app.data

import android.util.Log
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import org.phoenixframework.Socket

/**
 * Wraps the JavaPhoenixClient `Socket` for a single board subscription.
 *
 * Each call to `subscribeBoard` constructs a dedicated `Socket`,
 * connects, joins `"board:<id>"`, and emits typed events until the
 * collector cancels — at which point the socket is disconnected.
 *
 * One socket per Flow keeps lifecycle simple: there's no shared-state
 * bookkeeping or per-callback deregistration to worry about (the
 * underlying lib doesn't expose `off()` on the socket-level listeners
 * in this version).
 *
 * Reconnect / backoff is handled by JavaPhoenixClient itself and
 * surfaces as `BoardEvent.Disconnected` / `Connected`.
 */
object WaxxSocket {
    fun subscribeBoard(creds: TokenStore.Credentials, boardId: String): Flow<BoardEvent> =
        callbackFlow {
            val wsUrl = creds.baseUrl
                .replaceFirst("http://", "ws://")
                .replaceFirst("https://", "wss://")
                .trimEnd('/') + "/socket/websocket"

            Log.i("WaxxSocket", "dialing $wsUrl (baseUrl=${creds.baseUrl})")
            val socket = Socket(wsUrl, mapOf("token" to creds.token))

            socket.onOpen { trySend(BoardEvent.Connected) }
            socket.onClose { trySend(BoardEvent.Disconnected) }
            socket.onError { throwable, _ ->
                trySend(BoardEvent.Error(throwable.message ?: "socket error"))
            }

            socket.connect()

            val channel = socket.channel("board:$boardId", emptyMap())
            channel.on("cards_changed") { trySend(BoardEvent.CardsChanged) }
            channel.on("workflow_changed") { trySend(BoardEvent.WorkflowChanged) }

            channel.join()
                .receive("ok") { trySend(BoardEvent.Joined) }
                .receive("error") { msg -> trySend(BoardEvent.Error("join failed: $msg")) }
                .receive("timeout") { trySend(BoardEvent.Error("join timed out")) }

            awaitClose {
                channel.leave()
                socket.disconnect()
            }
        }
}

sealed interface BoardEvent {
    data object Connected : BoardEvent
    data object Disconnected : BoardEvent
    data object Joined : BoardEvent
    data object CardsChanged : BoardEvent
    data object WorkflowChanged : BoardEvent
    data class Error(val message: String) : BoardEvent
}
