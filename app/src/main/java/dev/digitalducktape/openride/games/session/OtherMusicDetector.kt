package dev.digitalducktape.openride.games.session

/**
 * Whether the rider's own music (another app's) is playing, for game music on "auto" (#35).
 *
 * `AudioManager.isMusicActive()` alone can't tell: once the Godot engine runs, its own media
 * player keeps it true, so game music was always off. And the public API can't name a player's
 * app: `AudioPlaybackConfiguration.getClientUid()` is a hidden system API, and for ordinary
 * apps the framework anonymizes the uid (API 29-34 expose only the attributes, the device, and
 * `equals`, which compares the player's id).
 *
 * So the players are told apart by identity. [engineStarting] (just before the engine's one
 * start in the process) records the players that already exist, which belong to other apps.
 * Every new player that appears in the next [claimWindowMs] belongs to the engine. After that,
 * music is someone else's when [musicActive] is true and a player that isn't the engine's
 * exists.
 *
 * Known limits: the playback list also holds another app's paused players, so a music app
 * paused in the background (with music playing nowhere but Godot) reads as "their music". A
 * music app started inside the claim window is taken for the engine's.
 *
 * @param players the active playback configurations with media usage; any objects whose
 *   `equals` identifies a player.
 */
class OtherMusicDetector(
    private val players: () -> List<Any>,
    private val musicActive: () -> Boolean,
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val claimWindowMs: Long = CLAIM_WINDOW_MS,
) {
    private var engineStarted = false
    private var baseline: Set<Any>? = null
    private var claimUntilMs = 0L
    private val enginePlayers = mutableSetOf<Any>()

    /** Before the Godot engine starts. Only the first call counts: the engine starts once per process. */
    @Synchronized
    fun engineStarting() {
        if (engineStarted) return
        engineStarted = true
        baseline = players().toSet()
        claimUntilMs = nowMs() + claimWindowMs
    }

    /** Claims the engine's new players while the window is open; call on playback changes. */
    @Synchronized
    fun observe() {
        val before = baseline ?: return
        if (nowMs() > claimUntilMs) {
            baseline = null
            return
        }
        enginePlayers.addAll(players().filterNot { it in before })
    }

    @Synchronized
    fun otherMusicActive(): Boolean {
        observe()
        if (!musicActive()) return false
        if (!engineStarted) return true
        return players().any { it !in enginePlayers }
    }

    companion object {
        /** Godot's player starts about 2 s after the host is created (seen on the bike). */
        const val CLAIM_WINDOW_MS = 10_000L
    }
}
