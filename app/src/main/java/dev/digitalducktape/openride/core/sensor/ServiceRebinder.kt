package dev.digitalducktape.openride.core.sensor

import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Schedules re-binds of an affernet service binding with capped exponential backoff.
 *
 * When the affernet process is force-stopped, crashes or is updated, Android reports
 * `onBindingDied` and — unlike after `onServiceDisconnected` — never reconnects that binding on
 * its own: the client has to `unbindService` and bind again. A service that hands back a null
 * binder (`onNullBinding`) is likewise stuck until rebound. Both sensor data sources use this to
 * retry at [initialDelayMs], doubling up to [maxDelayMs], so a service that is mid-restart is
 * not hammered and one that is down for a while is still picked up within [maxDelayMs].
 *
 * Retries run on [handler] (the main looper by default — the same thread `ServiceConnection`
 * callbacks arrive on).
 */
internal class ServiceRebinder(
    private val handler: Handler = Handler(Looper.getMainLooper()),
    private val initialDelayMs: Long = INITIAL_DELAY_MS,
    private val maxDelayMs: Long = MAX_DELAY_MS,
    private val rebind: () -> Unit,
) {
    private var nextDelayMs = initialDelayMs
    private val retry = Runnable { rebind() }

    /**
     * Schedules one rebind after the current backoff delay, replacing any retry still pending,
     * and doubles the delay for next time. Returns the delay used.
     */
    fun schedule(): Long {
        handler.removeCallbacks(retry)
        val delay = nextDelayMs
        handler.postDelayed(retry, delay)
        nextDelayMs = (delay * 2).coerceAtMost(maxDelayMs)
        return delay
    }

    /** Starts the next [schedule] from [initialDelayMs] again — call on a successful connect. */
    fun reset() {
        nextDelayMs = initialDelayMs
    }

    /** Drops any pending retry and resets the backoff. */
    fun cancel() {
        handler.removeCallbacks(retry)
        reset()
    }

    companion object {
        const val INITIAL_DELAY_MS = 1_000L
        const val MAX_DELAY_MS = 30_000L
    }
}

/**
 * Why an affernet binding is down, for [BoundBikeDataSource.bindFailure] — and the log for it.
 *
 * A board that refuses an interface refuses it on every retry (the g700 answers each
 * `IV1Interface` bind with a null binding, #63), so a warning per retry would bury the log. Each
 * distinct reason is logged once at WARN; repeats go to DEBUG. A successful connect clears it, so
 * the next real failure is reported again.
 */
internal class BindFailure(private val tag: String) {
    /** The current reason, or `null` while bound / not yet answered. */
    @Volatile
    var reason: String? = null
        private set

    private var lastLogged: String? = null

    fun record(reason: String, error: Throwable? = null) {
        this.reason = reason
        if (reason != lastLogged) {
            lastLogged = reason
            Log.w(tag, reason, error)
        } else {
            Log.d(tag, "$reason (again)")
        }
    }

    /** A new bind is under way: no verdict yet, but a repeat of the old reason stays quiet. */
    fun pending() {
        reason = null
    }

    /** Bound and registered: the next failure, whatever it is, gets logged. */
    fun clear() {
        reason = null
        lastLogged = null
    }
}
