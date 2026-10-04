package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.data.GameResult
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.ui.history.RideHistoryMapper
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GameLabelsTest {
    @Test
    fun `plan badges name the game and its length, or the circuit`() {
        assertEquals("Demo · 20 min", GameLabels.planBadge("just-ride:demo:minutes:20"))
        assertEquals("Demo · 5 rounds", GameLabels.planBadge("just-ride:demo:rounds:5"))
        assertEquals("Demo · 1 round", GameLabels.planBadge("just-ride:demo:rounds:1"))
        assertEquals("Demo · open", GameLabels.planBadge("just-ride:demo:open"))
        assertEquals("Tug of War · 10 min", GameLabels.planBadge("just-ride:tug_of_war:minutes:10"))
        // A game that isn't in the catalog yet gets a title made from its id.
        assertEquals("Safe Cracker · 10 min", GameLabels.planBadge("just-ride:safe_cracker:minutes:10"))
        assertEquals("Circuit · 45 min", GameLabels.planBadge("circuit-45"))
        assertEquals("Game", GameLabels.planBadge("something-new"))
        assertNull(GameLabels.planBadge(null))
    }

    @Test
    fun `history rows carry the game badge`() {
        val ride = Ride(
            profileId = 1, startEpochMs = 0, durationSec = 1210, avgCadence = 80, maxCadence = 90,
            avgPower = 150, maxPower = 200, avgResistance = 40, outputKj = 180.0, calories = 173,
        )

        assertNull(RideHistoryMapper.map(ride, ZoneOffset.UTC).gameBadge)
        assertEquals("Demo · 20 min", RideHistoryMapper.map(ride.copy(gamePlan = "just-ride:demo:minutes:20"), ZoneOffset.UTC).gameBadge)
    }

    @Test
    fun `result rows show each segment's role, difficulty, outcome and stars`() {
        fun result(index: Int, role: String, score: Double, stars: Int, won: Boolean? = null, skipped: Boolean = false) =
            GameResult(9, index, "demo", role, "hard", 0, 60, score, stars, won, skipped, "{}")

        val rows = GameLabels.resultRows(
            listOf(
                result(2, "recovery", 0.0, 0, skipped = true),
                result(0, "free", 1234.4, 2),
                result(1, "work", 1.0, 5, won = true),
            ),
        )

        assertEquals(
            listOf(
                GameLabels.ResultRow("1. Demo", "Just Ride · Hard · 1,234 points", 2, skipped = false),
                GameLabels.ResultRow("2. Demo", "Work · Hard · Won · 1 point", 3, skipped = false),
                GameLabels.ResultRow("3. Demo", "Recovery · Hard · Skipped", 0, skipped = true),
            ),
            rows,
        )
    }
}
