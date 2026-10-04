package dev.digitalducktape.openride.core.sensor

import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.ServiceConnection

/**
 * A [Context] that records `bindService` / `unbindService` instead of performing them, and hands
 * back the [ServiceConnection] so a test can play the system's part — connecting, killing the
 * binding, or returning a null binder.
 */
internal class RecordingBindContext(base: Context) : ContextWrapper(base) {
    var bindCount = 0
        private set
    var unbindCount = 0
        private set

    /** What the next `bindService` returns. */
    var bindResult = true

    private var lastConnection: ServiceConnection? = null

    /** The connection from the most recent bind. */
    val connection: ServiceConnection get() = checkNotNull(lastConnection) { "never bound" }

    override fun bindService(service: Intent, conn: ServiceConnection, flags: Int): Boolean {
        bindCount++
        lastConnection = conn
        return bindResult
    }

    override fun unbindService(conn: ServiceConnection) {
        unbindCount++
    }

    companion object {
        val AFFERNET = ComponentName("com.onepeloton.affernetservice", "AffernetService")
    }
}
