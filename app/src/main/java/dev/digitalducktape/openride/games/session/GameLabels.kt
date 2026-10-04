package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.data.GameResult

/**
 * Display text for game rides and their results, for History's badge and the ride summary.
 * Pure, so it's plain-JUnit testable.
 */
object GameLabels {
    /**
     * A ride's badge from its [dev.digitalducktape.openride.core.data.Ride.gamePlan]:
     * "Demo · 20 min", "Demo · 5 rounds", "Demo · open", "Circuit · 20 min". Null for a ride
     * that isn't a game session.
     */
    fun planBadge(gamePlan: String?, catalog: GameCatalog = GameCatalog.DEFAULT): String? {
        if (gamePlan == null) return null
        CircuitPresets[gamePlan]?.let { return "Circuit · ${it.labelMinutes} min" }
        val parts = gamePlan.split(":")
        if (parts.firstOrNull() != "just-ride" || parts.size < 3) return "Game"
        val title = gameTitle(parts[1], catalog)
        val length = when (parts[2]) {
            "minutes" -> parts.getOrNull(3)?.let { "$it min" }
            "rounds" -> parts.getOrNull(3)?.let { if (it == "1") "1 round" else "$it rounds" }
            "open" -> "open"
            else -> null
        }
        return listOfNotNull(title, length).joinToString(" · ")
    }

    fun gameTitle(gameId: String, catalog: GameCatalog = GameCatalog.DEFAULT): String =
        catalog[gameId]?.title ?: gameId.split('_').joinToString(" ") { it.replaceFirstChar(Char::uppercase) }

    /** One summary line per segment result. */
    data class ResultRow(val title: String, val detail: String, val stars: Int, val skipped: Boolean)

    fun resultRows(results: List<GameResult>, catalog: GameCatalog = GameCatalog.DEFAULT): List<ResultRow> =
        results.sortedBy { it.segmentIndex }.map { r ->
            val role = when (r.role) {
                "warmup" -> "Warm-up"
                "work" -> "Work"
                "recovery" -> "Recovery"
                "cooldown" -> "Cool-down"
                else -> "Just Ride"
            }
            val outcome = when {
                r.skipped -> "Skipped"
                r.won == true -> "Won · ${points(r.score)}"
                r.won == false -> "Lost · ${points(r.score)}"
                else -> points(r.score)
            }
            ResultRow(
                title = "${r.segmentIndex + 1}. ${gameTitle(r.gameId, catalog)}",
                detail = "$role · ${r.difficulty.replaceFirstChar(Char::uppercase)} · $outcome",
                stars = if (r.skipped) 0 else r.stars.coerceIn(0, 3),
                skipped = r.skipped,
            )
        }

    private fun points(score: Double): String {
        val whole = Math.round(score)
        return if (whole == 1L) "1 point" else "%,d points".format(whole)
    }
}
