package app.nearsend.chat

/**
 * Profile "pictures" are an emoji plus one of a few colours, written "<emoji>|<colour index>" (PROTOCOL.md section 10).
 * Tiny enough to travel in every announcement. Anything that is not exactly one of ours is ignored on receipt.
 */
object Avatars {
    val EMOJIS = listOf(
        "\uD83D\uDE00", "\uD83D\uDE0E", "\uD83E\uDD20", "\uD83E\uDD73", "\uD83D\uDE3A", "\uD83D\uDC36",
        "\uD83E\uDD8A", "\uD83D\uDC3C", "\uD83D\uDC38", "\uD83E\uDD84", "\uD83D\uDC19", "\uD83E\uDD8B",
        "\uD83C\uDF35", "\uD83C\uDF3B", "\uD83C\uDF40", "\u2B50", "\uD83D\uDD25", "\u26A1",
        "\uD83C\uDF08", "\uD83C\uDF55", "\uD83C\uDFB8", "\u26BD", "\uD83D\uDE80", "\uD83E\uDDED",
        "\u26FA", "\uD83C\uDFA7", "\uD83D\uDCF7", "\uD83C\uDFC4", "\uD83D\uDEB2", "\uD83C\uDF0A",
    )
    const val COLORS = 8

    fun encode(emoji: String, color: Int) = "$emoji|$color"

    /** (emoji, colour) when [s] is exactly one of our emojis and a known colour, else null. */
    fun parse(s: String?): Pair<String, Int>? {
        val i = s?.lastIndexOf('|') ?: return null
        if (i < 1) return null
        val emoji = s.substring(0, i); val color = s.substring(i + 1).toIntOrNull() ?: return null
        return if (emoji in EMOJIS && color in 0 until COLORS) emoji to color else null
    }

    /** [s] itself when it is a valid avatar, otherwise null. */
    fun valid(s: String?): String? = if (parse(s) != null) s else null
}
