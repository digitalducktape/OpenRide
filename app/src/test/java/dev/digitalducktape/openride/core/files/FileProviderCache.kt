package dev.digitalducktape.openride.core.files

import androidx.core.content.FileProvider

/**
 * androidx [FileProvider] caches each authority's path roots in a static map, resolved against
 * the context at first use. Robolectric gives every test a fresh data directory but reuses the
 * class, so a second test in the same JVM would resolve against the first test's cache dir.
 * Tests that build provider URIs call [clear] first.
 */
object FileProviderCache {
    fun clear() {
        val field = FileProvider::class.java.getDeclaredField("sCache").apply { isAccessible = true }
        (field.get(null) as MutableMap<*, *>).clear()
    }
}
