package pl.table.car

import android.content.Context
import org.json.JSONObject

/**
 * Bieżący kurs dla ekranu samochodu. Trzymany w pamięci i w SharedPreferences, żeby Android Auto
 * pokazał go od razu, także gdy aplikacja na telefonie jest w tle albo dopiero się uruchamia.
 */
object CourseStore {
    private const val PREFS = "table_car"
    private const val KEY = "state"

    @Volatile
    var state: JSONObject? = null
        private set

    private val listeners = mutableSetOf<() -> Unit>()

    fun load(context: Context): JSONObject? {
        if (state == null) {
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
            state = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
        }
        return state
    }

    fun update(context: Context, value: JSONObject) {
        state = value
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, value.toString()).apply()
        val current = synchronized(listeners) { listeners.toList() }
        current.forEach { it() }
    }

    fun listen(listener: () -> Unit) {
        synchronized(listeners) { listeners.add(listener) }
    }

    fun unlisten(listener: () -> Unit) {
        synchronized(listeners) { listeners.remove(listener) }
    }
}
