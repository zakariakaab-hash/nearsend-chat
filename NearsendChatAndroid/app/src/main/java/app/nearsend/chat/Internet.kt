package app.nearsend.chat

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import java.math.BigInteger
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

private fun sha256(vararg parts: ByteArray): ByteArray =
    MessageDigest.getInstance("SHA-256").apply { parts.forEach(::update) }.digest()

internal fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

/**
 * BIP-340 Schnorr signatures over secp256k1. Public relays only store events that carry one.
 * ponytail: plain BigInteger maths, not constant-time. Fine here because every key is random, used for one event and
 * protects nothing (the message is sealed separately). Swap in a real secp256k1 library before signing with a lasting key.
 */
internal object Schnorr {
    private val P = BigInteger("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F", 16)
    private val N = BigInteger("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141", 16)
    private val G = BigInteger("79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", 16) to
        BigInteger("483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8", 16)
    private val TWO = BigInteger.valueOf(2); private val THREE = BigInteger.valueOf(3)

    private fun add(a: Pair<BigInteger, BigInteger>?, b: Pair<BigInteger, BigInteger>?): Pair<BigInteger, BigInteger>? {
        if (a == null) return b
        if (b == null) return a
        if (a.first == b.first && a.second != b.second) return null
        val l = if (a == b) (THREE * a.first * a.first * (TWO * a.second).modInverse(P)).mod(P)
                else ((b.second - a.second) * (b.first - a.first).mod(P).modInverse(P)).mod(P)
        val x = (l * l - a.first - b.first).mod(P)
        return x to (l * (a.first - x) - a.second).mod(P)
    }

    private fun mul(k: BigInteger): Pair<BigInteger, BigInteger> {
        var r: Pair<BigInteger, BigInteger>? = null; var q: Pair<BigInteger, BigInteger>? = G
        for (i in 0 until k.bitLength()) { if (k.testBit(i)) r = add(r, q); q = add(q, q) }
        return r!!
    }

    private fun b32(x: BigInteger): ByteArray = x.toByteArray().let { b ->
        if (b.size >= 32) b.copyOfRange(b.size - 32, b.size) else ByteArray(32 - b.size) + b
    }
    private fun tagged(tag: String, vararg parts: ByteArray): ByteArray = sha256(tag.toByteArray()).let { t -> sha256(t, t, *parts) }

    /** A fresh secret key (32 bytes, valid scalar). */
    fun newKey(): ByteArray {
        while (true) {
            val k = ByteArray(32).also { SecureRandom().nextBytes(it) }
            val d = BigInteger(1, k)
            if (d.signum() > 0 && d < N) return k
        }
    }

    /** The 32-byte x-only public key. */
    fun publicKey(sk: ByteArray): ByteArray = b32(mul(BigInteger(1, sk)).first)

    fun sign(sk: ByteArray, msg: ByteArray, aux: ByteArray = ByteArray(32).also { SecureRandom().nextBytes(it) }): ByteArray {
        val d0 = BigInteger(1, sk)
        require(d0.signum() > 0 && d0 < N && msg.size == 32 && aux.size == 32)
        val p = mul(d0)
        val d = if (p.second.testBit(0)) N - d0 else d0
        val t = b32(d).zip(tagged("BIP0340/aux", aux)) { a, b -> (a.toInt() xor b.toInt()).toByte() }.toByteArray()
        val k0 = BigInteger(1, tagged("BIP0340/nonce", t, b32(p.first), msg)).mod(N)
        require(k0.signum() > 0)
        val r = mul(k0)
        val k = if (r.second.testBit(0)) N - k0 else k0
        val e = BigInteger(1, tagged("BIP0340/challenge", b32(r.first), b32(p.first), msg)).mod(N)
        return b32(r.first) + b32((k + e * d).mod(N))
    }
}

/** One relay event (Nostr NIP-01): a sealed packet, tagged with the receiver's topic, signed by a throwaway key. */
internal class RelayEvent(val id: String, val json: String) {
    companion object {
        const val KIND = 4243          // our own "regular" kind: relays store it, clients of other apps ignore it
        const val KEEP_S = 86_400L     // asks relays to delete it after a day (NIP-40), like the Bluetooth carry time

        fun build(topic: String, content: String, nowS: Long, sk: ByteArray = Schnorr.newKey()): RelayEvent {
            val pub = Schnorr.publicKey(sk).hex()
            val tags = """[["t","$topic"],["expiration","${nowS + KEEP_S}"]]"""
            // topic is hex and content is base64, so nothing here needs JSON escaping
            val id = sha256("""[0,"$pub",$nowS,$KIND,$tags,"$content"]""".toByteArray())
            val sig = Schnorr.sign(sk, id).hex()
            return RelayEvent(id.hex(), """{"id":"${id.hex()}","pubkey":"$pub","created_at":$nowS,"kind":$KIND,"tags":$tags,"content":"$content","sig":"$sig"}""")
        }
    }
}

/**
 * Optional internet path (PROTOCOL.md section 9). Keeps a WebSocket to a few public relays, listens for sealed packets
 * addressed to our key and publishes sealed packets for contacts who are out of Bluetooth range.
 * [deliver] runs callbacks on the caller's thread (the app passes its main thread).
 */
class InternetRelay(private val crypto: MeshCrypto, private val urls: List<String> = RELAYS, private val deliver: (() -> Unit) -> Unit) {
    companion object {
        val RELAYS = listOf("wss://relay.damus.io", "wss://nos.lol", "wss://relay.primal.net", "wss://offchain.pub")
        private const val MAX_CONTENT = 16_000
    }

    var onPacket: ((ByteArray) -> Unit)? = null
    var onState: ((connected: Int) -> Unit)? = null
    /** Only events newer than this (unix seconds) are asked for when a relay connects. */
    @Volatile var since = 0L

    private val topic = MeshCrypto.inetTopic(crypto.publicKey)
    private val client by lazy { OkHttpClient.Builder().pingInterval(30, TimeUnit.SECONDS).build() }
    // Everything below is touched only on this one thread.
    private val worker = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "nearsend-inet").apply { isDaemon = true } }
    private val sockets = HashMap<String, WebSocket>()      // url -> socket (connecting or open)
    private val open = HashSet<String>()
    private val waiting = HashMap<String, Pair<(Boolean) -> Unit, IntArray>>()   // event id -> (callback, answers still expected)
    private val seen = LinkedHashSet<String>()
    private val fails = HashMap<String, Int>()             // url -> failed attempts in a row (retry less and less often)
    private var running = false

    fun start() = worker.execute { if (!running) { running = true; urls.forEach(::connect) } }

    fun stop() = worker.execute {
        running = false
        sockets.values.forEach { it.cancel() }
        sockets.clear(); open.clear(); report()
        waiting.values.forEach { (done, _) -> deliver { done(false) } }
        waiting.clear()
    }

    /** Seals [packet] for the owner of [recipientPk] and gives it to every connected relay. [done]: at least one stored it. */
    fun publish(recipientPk: ByteArray, packet: ByteArray, done: (Boolean) -> Unit) = worker.execute {
        val targets = open.mapNotNull { sockets[it] }
        if (targets.isEmpty()) { deliver { done(false) }; return@execute }
        val to = MeshCrypto.inetTopic(recipientPk)
        val ev = RelayEvent.build(to, Base64.getEncoder().encodeToString(MeshCrypto.sealTo(recipientPk, packet, to.toByteArray())), System.currentTimeMillis() / 1000)
        waiting[ev.id] = done to intArrayOf(targets.size)
        targets.forEach { it.send("""["EVENT",${ev.json}]""") }
        worker.schedule({ waiting.remove(ev.id)?.let { (d, _) -> deliver { d(false) } } }, 10, TimeUnit.SECONDS)
    }

    private fun report() { val n = open.size; deliver { onState?.invoke(n) } }

    private fun connect(url: String) {
        if (!running || url in sockets) return
        sockets[url] = client.newWebSocket(Request.Builder().url(url).build(), object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) = worker.execute {
                if (sockets[url] !== webSocket) return@execute
                open += url; fails.remove(url)
                webSocket.send("""["REQ","ns",{"kinds":[${RelayEvent.KIND}],"#t":["$topic"],"since":$since}]""")
                report()
            }
            override fun onMessage(webSocket: WebSocket, text: String) = worker.execute { handle(text) }
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) { webSocket.close(1000, null) }
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = worker.execute { lost(url, webSocket) }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = worker.execute { lost(url, webSocket) }
        })
    }

    private fun lost(url: String, ws: WebSocket) {
        if (sockets[url] !== ws) return
        sockets.remove(url); open -= url; report()
        val n = fails.merge(url, 1, Int::plus)!!
        if (running) worker.schedule({ connect(url) }, minOf(300L, 15L shl minOf(n - 1, 5)), TimeUnit.SECONDS)   // 15 s, 30 s … 5 min
    }

    private fun handle(text: String) {
        val a = runCatching { JSONArray(text) }.getOrNull() ?: return
        when (a.optString(0)) {
            "EVENT" -> {
                val ev = a.optJSONObject(2) ?: return
                val content = ev.optString("content")
                if (content.length > MAX_CONTENT || !seen.add(ev.optString("id"))) return
                if (seen.size > 500) seen.remove(seen.first())
                val blob = runCatching { Base64.getDecoder().decode(content) }.getOrNull() ?: return
                val packet = crypto.openSealed(blob, topic.toByteArray()) ?: return     // not for us, or junk
                deliver { onPacket?.invoke(packet) }
            }
            "OK" -> {
                val id = a.optString(1); val (done, left) = waiting[id] ?: return
                if (a.optBoolean(2)) { waiting.remove(id); deliver { done(true) } }
                else if (--left[0] == 0) { waiting.remove(id); deliver { done(false) } }
            }
        }
    }
}
