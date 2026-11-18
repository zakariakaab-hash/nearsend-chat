package app.nearsend.chat

import android.util.Log

/**
 * Debug log for real-phone tests: every line goes to logcat (tag "Nearsend") and to a small in-memory list of the last
 * [MAX] lines, so a log screen or "share log" button can show it later without a computer.
 *
 * Never put message text, photos or keys in here. Only short ids, packet types, sizes and results.
 * Safe in unit tests: the logcat call is skipped when there is no Android runtime.
 */
object NLog {
    private const val TAG = "Nearsend"
    private const val MAX = 500
    private val start = System.currentTimeMillis()
    private val lines = ArrayDeque<String>()

    /** Called for every line (default: logcat). Tests may replace it. */
    @Volatile var echo: (String) -> Unit = { runCatching { Log.i(TAG, it) } }

    fun i(area: String, msg: String) {
        val t = System.currentTimeMillis() - start
        val line = "+%d.%03d %s: %s".format(t / 1000, t % 1000, area, msg)
        synchronized(lines) { lines.addLast(line); while (lines.size > MAX) lines.removeFirst() }
        echo(line)
    }

    /** The saved lines, oldest first. */
    fun dump(): String = synchronized(lines) { lines.joinToString("\n") }

    /** Short form of a peer id for the log (first 6 characters). */
    fun s(id: String?): String = id?.take(6) ?: "-"

    /** Short form of a link id such as "out:AA:BB:CC:DD:EE:FF" (kind and last two bytes). */
    fun l(link: String?): String = if (link == null) "-" else link.take(3) + ".." + link.takeLast(5)
}
