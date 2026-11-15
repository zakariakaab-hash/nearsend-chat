package app.nearsend.chat

import java.io.ByteArrayOutputStream

/**
 * A notification carries at most (MTU − 3) bytes, so packets sent from a phone's GATT server to a connected phone are
 * split into fragments: [seq][index][count][chunk…]. Identical to the iOS implementation. See PROTOCOL.md.
 */
object Framing {
    fun fragments(data: ByteArray, seq: Int, payload: Int): List<ByteArray> {
        if (payload <= 0 || data.isEmpty()) return emptyList()
        val count = (data.size + payload - 1) / payload
        if (count > 255) return emptyList()
        return (0 until count).map { i ->
            byteArrayOf(seq.toByte(), i.toByte(), count.toByte()) + data.copyOfRange(i * payload, minOf(data.size, (i + 1) * payload))
        }
    }
}

/** Puts fragments back together (they arrive in order on one connection). Returns the packet when the last fragment arrives. */
class Reassembler {
    private var seq = 0
    private var count = 0
    private var next = 0
    private var active = false
    private val buf = ByteArrayOutputStream()

    fun add(frag: ByteArray): ByteArray? {
        if (frag.size < 4) { reset(); return null }
        val s = frag[0].toInt() and 0xFF; val i = frag[1].toInt() and 0xFF; val c = frag[2].toInt() and 0xFF
        if (i == 0) { reset(); active = true; seq = s; count = c; next = 0 }
        if (!active || s != seq || i != next || c != count || c == 0) { reset(); return null }
        buf.write(frag, 3, frag.size - 3)
        next++
        if (next == count) { val out = buf.toByteArray(); reset(); return out }
        return null
    }

    private fun reset() { active = false; buf.reset(); next = 0; count = 0 }
}
