package dev.digitalducktape.openride.core.data

import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.test.core.app.ApplicationProvider
import org.junit.rules.ExternalResource

/**
 * A fresh in-memory [OpenRideDatabase] for each test, closed afterwards. Rules run before `@Before`
 * and finish after `@After`, so set-up and tear-down code can use [db] freely.
 *
 * ```
 * @get:Rule val database = InMemoryDatabaseRule()
 * private val db get() = database.db
 * ```
 *
 * [configure] tweaks the builder (executors, main-thread queries) for the tests that need it.
 * Needs a Robolectric runner for the application context.
 */
class InMemoryDatabaseRule(
    private val configure: RoomDatabase.Builder<OpenRideDatabase>.() -> RoomDatabase.Builder<OpenRideDatabase> = { this },
) : ExternalResource() {
    private var database: OpenRideDatabase? = null

    val db: OpenRideDatabase
        get() = checkNotNull(database) { "the database exists only while a test runs" }

    override fun before() {
        database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), OpenRideDatabase::class.java)
            .configure()
            .build()
    }

    override fun after() {
        database?.close()
        database = null
    }
}
