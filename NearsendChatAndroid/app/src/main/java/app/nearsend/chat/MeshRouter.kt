package app.nearsend.chat

import org.json.JSONArray
import org.json.JSONObject
import java.util.Base64
import java.util.UUID

/** Carried: the recipient is away; a phone nearby took a copy to pass on. Held: nobody nearby yet; this phone keeps it. */
enum class SendOutcome { Sent, Unreachable, Failed, Carried, Held }

/** Wire packet (JSON). See PROTOCOL.md. Optional fields are omitted when null. */
class Packet(
    val t: String,               // "hi" | "ann" | "msg" | "gm" | "pub" | "post" | "ack" | "vfy" | "sos" | "sosx"
    val id: String,
    val src: String,
    val dst: String?,
    val ttl: Int,
    val ts: Long,
    val n: String? = null,       // sender nickname
    val pk: String? = null,      // ann: base64 X25519 public key
    val ct: String? = null,      // msg: base64 sealed text
    val tx: String? = null,      // pub: plain text
    val ref: String? = null,     // ack: id of the message being acknowledged; sos/sosx: alarm id (same on every repeat)
    val loc: String? = null,     // sos: "lat,lon,accuracyMetres" when the sender shared a position
    val exp: Long? = null,       // post: expiry, ms since epoch
    val av: String? = null,      // ann: avatar "<emoji>|<colour index>"
    val ix: Int? = null,         // img: index of this chunk
    val cnt: Int? = null,        // img: number of chunks in the photo
) {
    fun toBytes(): ByteArray {
        val o = JSONObject().put("v", 2).put("t", t).put("id", id).put("src", src)
        dst?.let { o.put("dst", it) }
        o.put("ttl", ttl).put("ts", ts)
        n?.let { o.put("n", it) }; pk?.let { o.put("pk", it) }; ct?.let { o.put("ct", it) }
        tx?.let { o.put("tx", it) }; ref?.let { o.put("ref", it) }; loc?.let { o.put("loc", it) }; exp?.let { o.put("exp", it) }; av?.let { o.put("av", it) }
        ix?.let { o.put("ix", it) }; cnt?.let { o.put("cnt", it) }
        return o.toString().toByteArray()
    }

    fun withTtl(newTtl: Int) = Packet(t, id, src, dst, newTtl, ts, n, pk, ct, tx, ref, loc, exp, av, ix, cnt)

    companion object {
        fun parse(bytes: ByteArray): Packet? = runCatching {
            val o = JSONObject(String(bytes))
            if (o.getInt("v") != 2) return null
            fun opt(k: String) = if (o.has(k)) o.getString(k) else null
            Packet(o.getString("t"), o.getString("id"), o.getString("src"), opt("dst"), o.getInt("ttl"), o.getLong("ts"),
                opt("n"), opt("pk"), opt("ct"), opt("tx"), opt("ref"), opt("loc"), if (o.has("exp")) o.getLong("exp") else null, opt("av"),
                if (o.has("ix")) o.getInt("ix") else null, if (o.has("cnt")) o.getInt("cnt") else null)
        }.getOrNull()
    }
}

/**
 * Multi-hop relay, identical in behaviour to the iOS router. Transport independent: the BLE layer (or a test harness)
 * feeds packets in and provides [transmit]. Peers announce themselves every few seconds; announcements, public messages and
 * direct messages are flooded with a hop limit and de-duplicated by packet id.
 */
class MeshRouter(val myId: String, var myName: String, private val crypto: MeshCrypto) {
    companion object {
        const val START_TTL = 5
        const val MAX_TEXT_BYTES = 180
        const val PEER_TIMEOUT_MS = 40_000L
        const val HOLD_MS = 24 * 3_600_000L    // store-and-forward copies and announcements live at most a day
        const val MAX_HELD = 200
        const val MAX_POSTS = 50
        const val PHOTO_CHUNK = 700          // bytes of sealed photo per packet (about 940 characters once base64 encoded)
        const val MAX_PHOTO_CHUNKS = 90      // about 60 KB sealed, the most we accept
        private val UPLINK_TYPES = setOf("msg", "gm", "ack", "vfy")

        fun clip(s: String): String {
            val sb = StringBuilder(); var n = 0
            var i = 0
            while (i < s.length) {
                val cp = s.codePointAt(i); val len = String(Character.toChars(cp)).toByteArray().size
                if (n + len > MAX_TEXT_BYTES) break
                sb.appendCodePoint(cp); n += len; i += Character.charCount(cp)
            }
            return sb.toString()
        }
    }

    /** [via]: the neighbour a relayed peer's announcement came through (for the network view). */
    private class PeerInfo(val name: String, val pk: ByteArray, val hops: Int, val lastSeen: Long, val direct: Boolean, val via: String? = null, val avatar: String? = null)

    var now: () -> Long = { System.currentTimeMillis() }
    /** Link ids are "out:<id>" (we connected to that phone and can write to it) or "in:<id>" (it connected to us and we reply
     *  with notifications). A neighbour can have both; direct sends prefer "out:". */
    var transmit: ((link: String, data: ByteArray, done: (Boolean) -> Unit) -> Unit)? = null
    var onPeers: ((List<Peer>) -> Unit)? = null
    var onText: ((from: String, name: String, text: String, hops: Int, msgId: String) -> Unit)? = null
    var onPublic: ((from: String, name: String, text: String, id: String) -> Unit)? = null
    var onDelivered: ((msgId: String) -> Unit)? = null
    /** QR verification arrived: [from] proved it holds the key we know for it ([fingerprint]) and echoed [code]. */
    var onVerify: ((from: String, fingerprint: String, code: String) -> Unit)? = null
    /** SOS alarm [alarm] from [from] (repeats carry the same alarm id); [loc] is "lat,lon,acc" or null. */
    var onSos: ((from: String, name: String, alarm: String, note: String?, loc: String?, hops: Int) -> Unit)? = null
    var onSosEnd: ((from: String, alarm: String) -> Unit)? = null
    /** Group message [msgId] for group [group] ("g:" + uuid); [members] = (id, name) of everyone in it, sender included. */
    var onGroup: ((from: String, name: String, group: String, groupName: String, members: List<Pair<String, String>>, text: String, hops: Int, msgId: String) -> Unit)? = null
    /** Announcement [post] (stable id) from [from], shown until [exp]. Called once per post. */
    var onPost: ((from: String, name: String, post: String, text: String, exp: Long, hops: Int) -> Unit)? = null
    /** Keys of people met before who are not in range now (saved contacts): to seal to them and to open what they sent
     *  through a carrier. */
    var savedKey: ((id: String) -> ByteArray?)? = null
    /** A peer's key was seen (direct or announced); the app saves it for contacts. */
    var onKey: ((id: String, pk: ByteArray) -> Unit)? = null
    /** A photo from a contact arrived complete and was opened: (from, name, photoId, image bytes). */
    var onPhoto: ((from: String, name: String, photo: String, bytes: ByteArray) -> Unit)? = null
    /** Optional internet path: sends one of our own packets, sealed to [pk], to someone who is not in Bluetooth range. */
    var uplink: ((pk: ByteArray, data: ByteArray, done: (Boolean) -> Unit) -> Unit)? = null
    /** Privacy settings: pass on and carry other people's packets; confirm messages we receive. */
    var relay = true
    /** Our own picture (emoji and colour), announced to everyone nearby. */
    var myAvatar: String? = null
    var sendAcks = true

    private val links = LinkedHashMap<String, String>()      // link id -> peer id (direct neighbours; possibly two links per peer)
    private val peers = HashMap<String, PeerInfo>()
    private val rssi = HashMap<String, Int>()
    private val seen = HashSet<String>()
    private val seenOrder = ArrayDeque<String>()
    private val b64 = Base64.getEncoder()
    private val unb64 = Base64.getDecoder()
    private val held = LinkedHashMap<String, Pair<Packet, Long>>()   // packet id -> (packet for someone away, keep until)
    private val posts = LinkedHashMap<String, Packet>()               // post id -> announcement

    // ---- neighbours

    /** `sayHello`: when we opened the link ("out:") we tell the other phone who we are, so it can answer over the same
     *  connection even though it never discovered us (the one-directional link problem). */
    fun neighborConnected(link: String, id: String, name: String, pk: ByteArray, sayHello: Boolean = true) {
        if (id == myId || pk.size != 32) return
        links[link] = id
        peers[id] = PeerInfo(name, pk, 1, now(), true)
        onKey?.invoke(id, pk)
        emitPeers()
        if (sayHello) sendHello(link)
        sendAnnounce(listOf(link))
        shareStored(link, id)
    }

    /** A phone came into range: deliver what we carry for it, give it a copy of the rest to carry too, and show it the
     *  announcements it may have missed. */
    private fun shareStored(link: String, id: String) {
        expire()
        deliverHeld(id)
        for ((p, _) in held.values.toList()) if (p.dst != id && (relay || p.src == myId)) transmit?.invoke(link, p.withTtl(START_TTL).toBytes()) { }
        for (p in posts.values.toList()) if (relay || p.src == myId) {
            val copy = Packet("post", UUID.randomUUID().toString(), p.src, null, 1, p.ts, p.n, tx = p.tx, ref = p.ref, exp = p.exp)
            remember(copy.id)
            transmit?.invoke(link, copy.toBytes()) { }
        }
    }

    /** [id] became reachable: send what we hold for it. Copies handed straight to it are done; flooded ones stay until acked. */
    private fun deliverHeld(id: String) {
        for ((p, _) in held.values.toList()) if (p.dst == id) {
            val direct = bestLink(id) != null
            route(p.withTtl(START_TTL), null) { if (it == SendOutcome.Sent && direct) held.remove(p.id) }
        }
    }

    private fun hold(p: Packet) {
        if (p.dst == null || p.dst == myId) return
        held.remove(p.id)
        held[p.id] = p to minOf(p.ts, now()) + HOLD_MS     // a sender clock in the future cannot keep it longer
        while (held.size > MAX_HELD) held.remove(held.keys.first())
    }

    private fun expire() {
        val t = now()
        held.values.removeIf { it.second < t }
        posts.values.removeIf { (it.exp ?: 0) <= t }
    }

    private fun keyOf(id: String): ByteArray? = peers[id]?.pk ?: savedKey?.invoke(id)?.takeIf { it.size == 32 }

    // ---- photos: sealed, cut into chunks, sent one by one to a neighbour, never passed on (PROTOCOL.md section 11)

    private class Incoming(val src: String, val cnt: Int, val parts: Array<ByteArray?>, var last: Long)
    private val incoming = HashMap<String, Incoming>()
    private val donePhotos = LinkedHashSet<String>()

    /**
     * Sends [bytes] (an already compressed image) to [dst], which must be a direct Bluetooth neighbour we have the key of.
     * Completion: Sent when every chunk was handed to Bluetooth (the receipt comes later through onDelivered), Unreachable when
     * the person is not in direct range (or walked away), Failed on a write error.
     */
    fun sendPhoto(bytes: ByteArray, dst: String, photoId: String, progress: (Float) -> Unit, completion: (SendOutcome) -> Unit) {
        val pk = keyOf(dst) ?: return completion(SendOutcome.Unreachable)
        if (peers[dst]?.direct != true || bestLink(dst) == null) return completion(SendOutcome.Unreachable)
        val sealed = runCatching { crypto.sealData(bytes, pk, myId, dst, photoId) }.getOrNull() ?: return completion(SendOutcome.Failed)
        val cnt = (sealed.size + PHOTO_CHUNK - 1) / PHOTO_CHUNK
        if (cnt > MAX_PHOTO_CHUNKS) return completion(SendOutcome.Failed)
        fun next(i: Int) {
            if (i == cnt) return completion(SendOutcome.Sent)
            val link = bestLink(dst) ?: return completion(SendOutcome.Unreachable)
            val part = sealed.copyOfRange(i * PHOTO_CHUNK, minOf(sealed.size, (i + 1) * PHOTO_CHUNK))
            val p = Packet("img", UUID.randomUUID().toString(), myId, dst, 1, now(), n = myName, ct = b64.encodeToString(part), ref = photoId, ix = i, cnt = cnt)
            remember(p.id)
            val t = transmit ?: return completion(SendOutcome.Failed)
            t(link, p.toBytes()) { ok -> if (ok) { progress((i + 1f) / cnt); next(i + 1) } else completion(SendOutcome.Failed) }
        }
        next(0)
    }

    private fun receiveImg(p: Packet) {
        val ref = p.ref ?: return; val ix = p.ix ?: return; val cnt = p.cnt ?: return
        if (cnt !in 1..MAX_PHOTO_CHUNKS || ix !in 0 until cnt || ref in donePhotos) return
        val pk = keyOf(p.src) ?: return                      // only from people whose key we have
        val part = runCatching { unb64.decode(p.ct ?: return) }.getOrNull() ?: return
        if (part.isEmpty() || part.size > PHOTO_CHUNK + 16) return
        val inc = incoming.getOrPut(ref) { if (incoming.size >= 4) return; Incoming(p.src, cnt, arrayOfNulls(cnt), now()) }
        if (inc.src != p.src || inc.cnt != cnt) return
        inc.parts[ix] = part; inc.last = now()
        if (inc.parts.any { it == null }) return
        incoming.remove(ref)
        val sealed = inc.parts.fold(ByteArray(0)) { a, b -> a + b!! }
        val bytes = runCatching { crypto.openData(sealed, pk, myId, p.src, ref) }.getOrNull() ?: return
        donePhotos += ref; if (donePhotos.size > 100) donePhotos.remove(donePhotos.first())
        onPhoto?.invoke(p.src, p.n ?: peers[p.src]?.name ?: "?", ref, bytes)
        // A photo is confirmed even when delivery receipts are off: without it the sender cannot tell a lost chunk from success.
        val ack = Packet("ack", UUID.randomUUID().toString(), myId, p.src, START_TTL, now(), ref = ref)
        remember(ack.id)
        sendOrCarry(ack) { }
    }

    private fun sendHello(link: String) {
        val p = Packet("hi", UUID.randomUUID().toString(), myId, null, 1, now(), n = myName, pk = b64.encodeToString(crypto.publicKey))
        remember(p.id)
        transmit?.invoke(link, p.toBytes()) { }
    }

    fun neighborLost(link: String) {
        val id = links.remove(link) ?: return
        if (!links.containsValue(id)) { peers.remove(id); rssi.remove(id) }
        emitPeers()
    }

    fun updateRssi(link: String, value: Int) {
        val id = links[link] ?: return
        rssi[id] = value
        emitPeers()
    }

    // ---- periodic

    /** Call every ~8 seconds: floods our announcement and forgets relayed peers we stopped hearing about. */
    fun tick() {
        val cutoff = now() - PEER_TIMEOUT_MS
        val before = peers.size
        peers.entries.removeIf { !it.value.direct && it.value.lastSeen <= cutoff }
        if (peers.size != before) emitPeers()
        expire()
        incoming.values.removeIf { now() - it.last > 120_000 }
        sendAnnounce(allBestLinks(null))
    }

    private fun sendAnnounce(targets: List<String>) {
        val p = Packet("ann", UUID.randomUUID().toString(), myId, null, START_TTL, now(), n = myName, pk = b64.encodeToString(crypto.publicKey), av = myAvatar)
        remember(p.id)
        val data = p.toBytes()
        targets.forEach { transmit?.invoke(it, data) { } }
    }

    // ---- sending

    /** Sends now if [dst] is reachable. If not, but we know its key (a contact), the message is stored and carried:
     *  Carried when a phone nearby took a copy, Held when nobody is around yet. Unreachable only without a key. */
    fun sendText(text: String, dst: String, msgId: String, completion: (SendOutcome) -> Unit) {
        val pk = keyOf(dst) ?: return completion(SendOutcome.Unreachable)
        val ct = runCatching { crypto.seal(clip(text), pk, myId, dst, msgId) }.getOrNull() ?: return completion(SendOutcome.Failed)
        sendOrCarry(Packet("msg", msgId, myId, dst, START_TTL, now(), n = myName, ct = b64.encodeToString(ct)), completion)
    }

    private fun sendOrCarry(p: Packet, completion: (SendOutcome) -> Unit) {
        remember(p.id)
        if (p.dst in peers) return route(p, null, completion)
        hold(p)
        route(p, null) { r ->
            // A phone nearby took a copy, the internet relays took one, or (neither) we keep carrying it ourselves.
            val up = uplink; val pk = p.dst?.let(::keyOf)
            if (r == SendOutcome.Sent) completion(SendOutcome.Carried)
            if (up != null && pk != null) up(pk, p.toBytes()) { ok -> if (r != SendOutcome.Sent) completion(if (ok) SendOutcome.Carried else SendOutcome.Held) }
            else if (r != SendOutcome.Sent) completion(SendOutcome.Held)
        }
    }

    /** The internet just came up: give it our own waiting packets. [onCarried] gets the id of each one a relay stored. */
    fun uplinkHeld(onCarried: (id: String) -> Unit) {
        val up = uplink ?: return
        expire()
        for ((p, _) in held.values.toList()) {
            if (p.src != myId || p.dst in peers) continue
            up(keyOf(p.dst ?: continue) ?: continue, p.toBytes()) { ok -> if (ok) onCarried(p.id) }
        }
    }

    /** A packet that came over the internet. Only private packets addressed to us are taken; nothing is passed on. */
    fun receiveUplink(data: ByteArray) {
        val p = Packet.parse(data) ?: return
        if (p.dst == myId && p.t in UPLINK_TYPES) receive(data, null)
    }

    /** Public announcement, kept by every phone until [exp] (at most a day) and shown to phones that arrive later. */
    fun sendPost(text: String, postId: String, exp: Long) {
        val p = Packet("post", UUID.randomUUID().toString(), myId, null, START_TTL, now(), n = myName, tx = clip(text), ref = postId,
            exp = minOf(exp, now() + HOLD_MS))
        remember(p.id); keepPost(p)
        route(p, null, null)
    }

    private fun keepPost(p: Packet) {
        posts[p.ref ?: return] = p
        while (posts.size > MAX_POSTS) posts.remove(posts.values.minByOrNull { it.exp ?: 0 }!!.ref)
    }

    fun sendPublic(text: String, msgId: String, completion: (SendOutcome) -> Unit) {
        val p = Packet("pub", msgId, myId, null, START_TTL, now(), n = myName, tx = clip(text))
        remember(msgId)
        route(p, null, completion)
    }

    /** After scanning [dst]'s QR code: send back its one-time [code], sealed to the key [pk] taken from the QR. */
    fun sendVerify(code: String, dst: String, pk: ByteArray, completion: (SendOutcome) -> Unit) {
        val id = UUID.randomUUID().toString()
        val ct = runCatching { crypto.seal(code, pk, myId, dst, id) }.getOrNull() ?: return completion(SendOutcome.Failed)
        val p = Packet("vfy", id, myId, dst, START_TTL, now(), n = myName, ct = b64.encodeToString(ct))
        remember(id)
        route(p, null, completion)
    }

    /** One copy of a group message for member [dst], sealed like a direct message. Packet id = "<msgId>.<dst>", so each
     *  copy has its own aad and its own ack. Returns Unreachable while [dst] is not known (the app queues it). */
    fun sendGroup(text: String, group: String, groupName: String, members: List<Pair<String, String>>, dst: String, msgId: String,
                  completion: (SendOutcome) -> Unit) {
        val pk = keyOf(dst) ?: return completion(SendOutcome.Unreachable)
        val id = "$msgId.$dst"
        val json = JSONObject().put("g", group).put("gn", groupName).put("tx", clip(text))
            .put("m", JSONArray(members.map { JSONObject().put("id", it.first).put("n", it.second) })).toString()
        val ct = runCatching { crypto.seal(json, pk, myId, dst, id) }.getOrNull() ?: return completion(SendOutcome.Failed)
        sendOrCarry(Packet("gm", id, myId, dst, START_TTL, now(), n = myName, ct = b64.encodeToString(ct)), completion)
    }

    /** SOS goes to everyone, unencrypted, like "pub". The app repeats it while the alarm is on; [alarm] ties repeats together. */
    fun sendSos(alarm: String, note: String?, loc: String?, end: Boolean = false) {
        val p = Packet(if (end) "sosx" else "sos", UUID.randomUUID().toString(), myId, null, START_TTL, now(), n = myName,
            tx = note?.takeIf { it.isNotBlank() && !end }?.let { clip(it) }, ref = alarm, loc = loc.takeIf { !end })
        remember(p.id)
        route(p, null, null)
    }

    // ---- receiving

    fun receive(data: ByteArray, from: String?) {
        val p = Packet.parse(data) ?: return
        if (p.src == myId || p.id in seen) return
        remember(p.id)
        val hops = maxOf(1, START_TTL + 1 - p.ttl)
        when (p.t) {
            "hi" -> {            // a phone that connected to us introduces itself; we can now reply over that connection
                val link = from ?: return
                val pk = runCatching { unb64.decode(p.pk ?: return) }.getOrNull() ?: return
                if (pk.size == 32) neighborConnected(link, p.src, p.n ?: "?", pk, sayHello = false)
            }
            "ann" -> {
                val pk = runCatching { unb64.decode(p.pk ?: return) }.getOrNull() ?: return
                if (pk.size != 32) return
                val direct = peers[p.src]?.direct ?: false
                val wasKnown = p.src in peers
                peers[p.src] = PeerInfo(p.n ?: "?", pk, if (direct) 1 else hops, now(), direct, if (direct) null else from?.let { links[it] }, Avatars.valid(p.av))
                onKey?.invoke(p.src, pk)
                emitPeers()
                if (!wasKnown) deliverHeld(p.src)
                forward(p, from)
            }
            "msg" -> if (p.dst == myId) {
                val pk = keyOf(p.src) ?: return
                val ct = runCatching { unb64.decode(p.ct ?: return) }.getOrNull() ?: return
                val text = runCatching { crypto.open(ct, pk, myId, p.src, p.id) }.getOrNull() ?: return
                onText?.invoke(p.src, p.n ?: peers[p.src]?.name ?: "?", text, hops, p.id)
                ack(p)
            } else passOn(p, from)
            "img" -> if (p.dst == myId) receiveImg(p)      // photos only ever go to one neighbour: never forwarded
            "pub" -> { p.tx?.let { onPublic?.invoke(p.src, p.n ?: "?", it, p.id) }; forward(p, from) }
            "post" -> {
                val ref = p.ref ?: return; val tx = p.tx ?: return; val exp = minOf(p.exp ?: return, now() + HOLD_MS)
                if (exp <= now()) return
                val fresh = ref !in posts
                keepPost(Packet(p.t, p.id, p.src, null, p.ttl, p.ts, p.n, tx = tx, ref = ref, exp = exp))
                if (fresh) onPost?.invoke(p.src, p.n ?: "?", ref, tx, exp, hops)
                forward(p, from)
            }
            "gm" -> if (p.dst == myId) {
                val pk = keyOf(p.src) ?: return
                val ct = runCatching { unb64.decode(p.ct ?: return) }.getOrNull() ?: return
                val o = runCatching { JSONObject(crypto.open(ct, pk, myId, p.src, p.id)) }.getOrNull() ?: return
                val group = o.optString("g"); val text = o.optString("tx")
                if (!group.startsWith("g:") || text.isEmpty()) return
                val ms = o.optJSONArray("m") ?: JSONArray()
                val members = (0 until ms.length()).mapNotNull { ms.optJSONObject(it) }.map { it.optString("id") to it.optString("n") }.filter { it.first.isNotEmpty() }
                onGroup?.invoke(p.src, p.n ?: peers[p.src]?.name ?: "?", group, o.optString("gn").ifEmpty { "?" }, members, text, hops, p.id.substringBefore('.'))
                ack(p)
            } else passOn(p, from)
            "sos" -> { p.ref?.let { onSos?.invoke(p.src, p.n ?: "?", it, p.tx, p.loc, hops) }; forward(p, from) }
            "sosx" -> { p.ref?.let { onSosEnd?.invoke(p.src, it) }; forward(p, from) }
            "ack" -> {
                p.ref?.let { held.remove(it) }            // delivered: carriers drop their copy as the ack passes
                if (p.dst == myId && p.ref != null) onDelivered?.invoke(p.ref) else passOn(p, from)
            }
            "vfy" -> if (p.dst == myId) {
                val info = peers[p.src] ?: return
                val ct = runCatching { unb64.decode(p.ct ?: return) }.getOrNull() ?: return
                val code = runCatching { crypto.open(ct, info.pk, myId, p.src, p.id) }.getOrNull() ?: return
                onVerify?.invoke(p.src, MeshCrypto.fingerprint(info.pk), code)
            } else passOn(p, from)
        }
    }

    // ---- internals

    private fun ack(p: Packet) {
        if (!sendAcks) return
        val ack = Packet("ack", UUID.randomUUID().toString(), myId, p.src, START_TTL, now(), ref = p.id)
        remember(ack.id)
        sendOrCarry(ack) { }
    }

    /** A packet for someone else: pass it on, and keep a copy to carry if that person is not reachable now. */
    private fun passOn(p: Packet, from: String?) {
        if (!relay) return
        if (p.dst !in peers) hold(p)
        forward(p, from)
    }

    private fun forward(p: Packet, from: String?) {
        if (!relay || p.ttl <= 1) return
        route(p.withTtl(p.ttl - 1), from, null)
    }

    private fun bestLink(peer: String): String? {
        val ls = links.filterValues { it == peer }.keys.sorted()
        return ls.firstOrNull { it.startsWith("out:") } ?: ls.firstOrNull()
    }

    /** One link per neighbouring phone (never both of its links), skipping the phone a packet came from. */
    private fun allBestLinks(exceptPeer: String?): List<String> =
        links.values.toSet().filter { it != exceptPeer }.sorted().mapNotNull { bestLink(it) }

    /** Sends straight to the destination if it is a neighbour, otherwise floods to all other neighbours. */
    private fun route(p: Packet, except: String?, completion: ((SendOutcome) -> Unit)?) {
        var targets = allBestLinks(except?.let { links[it] })
        p.dst?.let { dst -> bestLink(dst)?.let { targets = listOf(it) } }
        if (targets.isEmpty()) { completion?.invoke(SendOutcome.Unreachable); return }
        val data = p.toBytes()
        var pending = targets.size; var ok = false
        for (l in targets) {
            transmit?.invoke(l, data) { success ->
                if (success) ok = true
                pending--
                if (pending == 0) completion?.invoke(if (ok) SendOutcome.Sent else SendOutcome.Failed)
            } ?: run { pending--; if (pending == 0) completion?.invoke(SendOutcome.Failed) }
        }
    }

    private fun emitPeers() {
        onPeers?.invoke(peers.map { (id, i) ->
            val r = if (i.direct) (rssi[id] ?: -80) else -70 - 8 * i.hops
            Peer(id, i.name, i.hops, r.coerceIn(-95, -40), false, MeshCrypto.fingerprint(i.pk), i.via, i.avatar)
        }.sortedBy { it.id })
    }

    private fun remember(id: String) {
        seen.add(id); seenOrder.addLast(id)
        if (seenOrder.size > 1500) seen.remove(seenOrder.removeFirst())
    }
}
