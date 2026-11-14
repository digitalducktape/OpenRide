package dev.digitalducktape.openride.core.sensor

/**
 * A [BikeDataSource] backed by a binder connection that must be explicitly opened and closed.
 *
 * Exists so [AffernetBikeDataSource] can race and release its candidate paths without depending
 * on the concrete AIDL-bound classes — which in turn is what makes the arbitration unit-testable
 * on a plain JVM, with no device and no Robolectric.
 */
interface BoundBikeDataSource : BikeDataSource {
    /** Frames decoded since [start], pushed or polled: the heartbeat [watchFrames] checks. */
    val framesReceived: Long

    /**
     * Why this path is not bound right now, or `null` while it is bound or before its first bind
     * has answered. Set when the bind is refused (`bindService` false), denied (it threw, e.g.
     * `SecurityException`), answered with a null binding (how the g700 refuses `IV1Interface`,
     * #63), the binding dies, or `registerCallback` fails. A failed path keeps retrying on its
     * own; [AffernetBikeDataSource] reads this only to log it and carry on with the other
     * interface.
     */
    val bindFailure: String? get() = null

    /** Opens the binding. Must never throw, on any device. */
    fun start()

    /** Closes the binding. Must be safe to call even if [start] never ran. */
    fun stop()
}

/**
 * A [BoundBikeDataSource] that can also be read synchronously, rather than only pushed to.
 *
 * Only the `IBikeInterface` path offers this (`getBikeData`, transaction 14). It matters because
 * "the bind succeeded, the callback registered, and nothing was ever pushed" is real observed
 * hardware behaviour, and a synchronous read still works in that state.
 */
interface PollableBikeDataSource : BoundBikeDataSource {
    /**
     * Reads one frame synchronously and publishes it as if it had been pushed. Returns the
     * decoded metrics, or `null` if not bound or the read failed.
     */
    fun pollBikeData(): BikeMetrics?
}
