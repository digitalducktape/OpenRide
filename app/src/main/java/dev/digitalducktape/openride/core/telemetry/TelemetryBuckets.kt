package dev.digitalducktape.openride.core.telemetry

/** Maps raw numbers onto the coarse buckets telemetry is allowed to send. Half-open: [low, high). */
object TelemetryBuckets {
    fun rideDuration(seconds: Long): DurationBucket = when {
        seconds < 300 -> DurationBucket.LT_5M
        seconds < 900 -> DurationBucket.M5_15
        seconds < 1800 -> DurationBucket.M15_30
        seconds < 2700 -> DurationBucket.M30_45
        seconds < 3600 -> DurationBucket.M45_60
        else -> DurationBucket.M60_PLUS
    }

    fun gamePlayed(seconds: Long): GamePlayedBucket = when {
        seconds < 60 -> GamePlayedBucket.LT_1M
        seconds < 180 -> GamePlayedBucket.M1_3
        seconds < 300 -> GamePlayedBucket.M3_5
        seconds < 600 -> GamePlayedBucket.M5_10
        else -> GamePlayedBucket.M10_PLUS
    }

    fun profiles(n: Int): ProfilesBucket = when {
        n <= 1 -> ProfilesBucket.ONE
        n == 2 -> ProfilesBucket.TWO
        else -> ProfilesBucket.THREE_PLUS
    }

    fun hrDrops(n: Int): HrDropsBucket = when {
        n <= 0 -> HrDropsBucket.ZERO
        n == 1 -> HrDropsBucket.ONE
        n <= 5 -> HrDropsBucket.TWO_5
        else -> HrDropsBucket.SIX_PLUS
    }

    fun gamesPlayed(n: Int): GamesPlayedBucket = when {
        n <= 0 -> GamesPlayedBucket.ZERO
        n == 1 -> GamesPlayedBucket.ONE
        n == 2 -> GamesPlayedBucket.TWO
        n == 3 -> GamesPlayedBucket.THREE
        n == 4 -> GamesPlayedBucket.FOUR
        else -> GamesPlayedBucket.FIVE_PLUS
    }

    fun imported(n: Int): ImportedBucket = when {
        n <= 0 -> ImportedBucket.ZERO
        n <= 10 -> ImportedBucket.N1_10
        n <= 50 -> ImportedBucket.N11_50
        n <= 200 -> ImportedBucket.N51_200
        else -> ImportedBucket.N200_PLUS
    }

    fun gpxPoints(n: Int): GpxPointsBucket = when {
        n < 500 -> GpxPointsBucket.LT_500
        n < 2000 -> GpxPointsBucket.P500_2K
        n < 10000 -> GpxPointsBucket.K2_10K
        else -> GpxPointsBucket.K10_PLUS
    }
}
