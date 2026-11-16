package app.nearsend.chat

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID

/**
 * UI-facing state. On a real phone it is driven by [BleTransport] + [MeshRouter]; emulators have no Bluetooth,
 * so there it shows demo data instead. Conversations are saved on the device.
 */
class ChatStore private constructor(private val app: Application) {
    companion object {
        @Volatile private var instance: ChatStore? = null
        /** One store per process, owned by the app (not by a screen), so the mesh keeps running when the UI is closed. */
        fun get(ctx: Context): ChatStore = instance ?: synchronized(this) {
            instance ?: ChatStore(ctx.applicationContext as Application).also { instance = it }
        }
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val prefs = app.getSharedPreferences("nearsend", Context.MODE_PRIVATE)
    private val file = File(app.filesDir, "chat.json")
    private val main = Handler(Looper.getMainLooper())
    private val keys = KeyStore(app)

    var peers by mutableStateOf(listOf<Peer>()); private set
    var conversations by mutableStateOf(listOf<Conversation>()); private set
    var nickname by mutableStateOf(prefs.getString("nickname", null) ?: "anon-${(1000..9999).random()}")
    var meshActive by mutableStateOf(prefs.getBoolean("mesh", true)); private set
    var bluetoothState by mutableStateOf("starting"); private set   // starting | ready | off | unauthorized | unsupported
    var myFingerprint by mutableStateOf("A3F1 9C02 7BD4 E58A\n11C0 4F6E 92AB 3D77"); private set
    var verified by mutableStateOf(setOf<String>()); private set
    var nicknames by mutableStateOf(mapOf<String, String>()); private set   // fingerprint -> name you gave them
    var blocked by mutableStateOf(setOf<String>()); private set             // peer ids whose messages are dropped
    var lastVerified by mutableStateOf<String?>(null)                       // who just confirmed our QR (shown on the QR screen)
    private val myCodes = HashSet<String>()                                  // one-time codes shown in our QR this session
    private val pendingVerify = HashMap<String, Pair<String, ByteArray>>()   // peer id -> (their code, their key), sent when reachable
    var activeConversation: String? = null
    var wipeCount by mutableStateOf(0); private set   // UI returns to onboarding when this changes
    var backgroundEnabled by mutableStateOf(prefs.getBoolean("background", true)); private set
    var peerCountListener: ((Int) -> Unit)? = null   // the foreground service keeps its notification up to date

    val simulated = isEmulator()
    private var deviceId = prefs.getString("deviceID", null) ?: newDeviceId()
    private var transport: BleTransport? = null
    private var router: MeshRouter? = null
    private val inflight = HashSet<String>()
    private val tick = object : Runnable { override fun run() { router?.tick(); main.postDelayed(this, 8000) } }

    val relayedCount get() = peers.count { it.hops > 1 }
    val unreadTotal get() = conversations.sumOf { it.unread }

    init {
        if (simulated) { seed(); drift() } else load()
        ensurePublicChannel()
    }

    private fun newDeviceId() = UUID.randomUUID().toString().also { prefs.edit().putString("deviceID", it).apply() }

    private fun isEmulator() = Build.FINGERPRINT.startsWith("generic") || Build.FINGERPRINT.contains("emulator") ||
        Build.HARDWARE.contains("ranchu") || Build.HARDWARE.contains("goldfish") || Build.PRODUCT.contains("sdk")

    // ---- lifecycle

    fun blePermissions(): List<String> =
        if (Build.VERSION.SDK_INT >= 31) listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
        else listOf(Manifest.permission.ACCESS_FINE_LOCATION)

    fun hasBlePermissions(): Boolean = blePermissions().all {
        ContextCompat.checkSelfPermission(app, it) == PackageManager.PERMISSION_GRANTED
    }

    /** Safe to call repeatedly (after onboarding, after the permission prompt, on resume). */
    fun startIfNeeded() {
        if (simulated || !meshActive) return
        if (!hasBlePermissions()) { bluetoothState = "unauthorized"; return }
        if (router == null) {
            val crypto = keys.loadOrCreate()
            myFingerprint = crypto.fingerprint
            val r = MeshRouter(deviceId, nickname, crypto)
            val t = BleTransport(app, deviceId, nickname, crypto.publicKey)
            r.transmit = { link, data, done -> t.write(link, data, done) }
            r.onPeers = { applyPeers(it) }
            r.onText = { from, name, text, hops, id -> receiveText(from, name, text, hops, id) }
            r.onPublic = { from, name, text, id -> receivePublic(from, name, text, id) }
            r.onVerify = { from, fp, code -> confirmVerify(from, fp, code) }
            r.onDelivered = { markDelivered(it) }
            t.onNeighbor = { link, id, name, pk -> r.neighborConnected(link, id, name, pk) }
            t.onLost = { r.neighborLost(it) }
            t.onPacket = { data, link -> r.receive(data, link) }
            t.onRssi = { link, rssi -> r.updateRssi(link, rssi) }
            t.onState = { bluetoothState = it }
            router = r; transport = t
            main.postDelayed(tick, 8000)
        }
        transport?.start()
        if (backgroundEnabled && !MeshService.running) MeshService.start(app)
    }

    /** "Keep running in the background": a foreground service keeps Bluetooth alive while the app is closed. */
    fun setBackground(on: Boolean) {
        backgroundEnabled = on
        prefs.edit().putBoolean("background", on).apply()
        if (on && !simulated && meshActive && hasBlePermissions()) MeshService.start(app) else MeshService.stop(app)
    }

    /** Used after a reboot or app update to decide whether to bring the service back. */
    fun shouldRunInBackground(): Boolean =
        prefs.getBoolean("onboarded", false) && backgroundEnabled && meshActive && (simulated || hasBlePermissions())

    /** Bluetooth was switched on/off while we were running: tear the links down, or start fresh when it comes back. */
    fun onBluetoothChanged(enabled: Boolean) {
        if (simulated || !meshActive) return
        transport?.stop()
        if (enabled) startIfNeeded() else { peers = emptyList(); peerCountListener?.invoke(0); bluetoothState = "off" }
    }

    fun setMesh(on: Boolean) {
        meshActive = on
        prefs.edit().putBoolean("mesh", on).apply()
        if (simulated) return
        if (on) startIfNeeded() else { transport?.stop(); peers = emptyList(); peerCountListener?.invoke(0); MeshService.stop(app) }
    }

    fun updateNickname(n: String) { nickname = n }

    fun applyNickname() {
        prefs.edit().putString("nickname", nickname).apply()
        router?.myName = nickname
        transport?.setName(nickname)
        save()
    }

    /** Panic wipe: forget every message, key and setting. The phone gets a brand-new identity. */
    fun wipeAll() {
        main.removeCallbacks(tick)
        transport?.stop(); transport = null; router = null; inflight.clear()
        keys.wipe(); file.delete()
        prefs.edit().clear().apply()
        deviceId = newDeviceId()
        verified = emptySet(); peers = emptyList(); conversations = emptyList()
        nicknames = emptyMap(); blocked = emptySet(); myCodes.clear(); pendingVerify.clear(); lastVerified = null
        nickname = "anon-${(1000..9999).random()}"
        if (!simulated) myFingerprint = ""
        ensurePublicChannel()
        wipeCount++
        if (simulated) seed() else startIfNeeded()
    }

    // ---- conversations

    fun ensureConversation(peer: Peer) {
        if (conversations.none { it.id == peer.id }) conversations = conversations + Conversation(peer.id, peer, emptyList())
    }

    fun markRead(id: String) {
        if (conversations.any { it.id == id && it.unread > 0 }) {
            conversations = conversations.map { if (it.id == id) it.copy(unread = 0) else it }; save()
        }
    }

    fun toggleVerified(peer: Peer) {
        if (peer.fingerprint.isEmpty()) return
        verified = if (peer.fingerprint in verified) verified - peer.fingerprint else verified + peer.fingerprint
        peers = peers.map { it.copy(verified = it.fingerprint in verified) }
        save()
    }

    // ---- QR verification and contacts

    enum class ScanResult { Verified, Mismatch, Invalid, Added }

    /** Our contact card to send as text. No one-time code: a code that can be forwarded must never verify anyone. */
    fun myTextCode(): String = JSONObject().put("nearsend", 1).put("id", deviceId).put("n", nickname)
        .put("pk", Base64.getEncoder().encodeToString(keys.loadOrCreate().publicKey)).toString()

    /** A pasted contact card (from a message, or a QR copied as text): adds an UNVERIFIED contact, ignoring any one-time code. */
    fun applyText(text: String?): Pair<ScanResult, String> {
        val s = text.orEmpty(); val start = s.indexOf('{'); val end = s.lastIndexOf('}')
        if (start < 0 || end < start) return ScanResult.Invalid to ""
        val o = runCatching { JSONObject(s.substring(start, end + 1)) }.getOrNull() ?: return ScanResult.Invalid to ""
        val id = o.optString("id"); val name = o.optString("n").ifEmpty { "?" }
        val pk = runCatching { Base64.getDecoder().decode(o.optString("pk")) }.getOrNull()
        if (o.optInt("nearsend") != 1 || id.isEmpty() || id == deviceId || pk?.size != 32) return ScanResult.Invalid to ""
        val fp = MeshCrypto.fingerprint(pk)
        val seen = peers.firstOrNull { it.id == id }
        if (seen != null && seen.fingerprint != fp) return ScanResult.Mismatch to seen.name
        ensureConversation(seen ?: Peer(id, name, 1, -80, fp in verified, fp)); save()
        return ScanResult.Added to (seen?.name ?: name)
    }

    /** Contents of our QR code. The one-time code proves to us that the scanner really saw this screen. */
    fun myQr(): String {
        val code = ByteArray(8).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        myCodes += code
        return JSONObject().put("nearsend", 1).put("id", deviceId).put("n", nickname)
            .put("pk", Base64.getEncoder().encodeToString(keys.loadOrCreate().publicKey)).put("c", code).toString()
    }

    /** We scanned someone's QR: their key is verified, and they get our proof so they can verify us too. */
    fun applyScan(text: String?): Pair<ScanResult, String> {
        val o = runCatching { JSONObject(text ?: "") }.getOrNull() ?: return ScanResult.Invalid to ""
        val id = o.optString("id"); val code = o.optString("c"); val name = o.optString("n").ifEmpty { "?" }
        val pk = runCatching { Base64.getDecoder().decode(o.optString("pk")) }.getOrNull()
        if (o.optInt("nearsend") != 1 || id.isEmpty() || id == deviceId || code.isEmpty() || pk?.size != 32) return ScanResult.Invalid to ""
        val fp = MeshCrypto.fingerprint(pk)
        val seen = peers.firstOrNull { it.id == id }
        verified = verified + fp
        peers = peers.map { it.copy(verified = it.fingerprint in verified) }
        ensureConversation(seen ?: Peer(id, name, 1, -80, true, fp))
        pendingVerify[id] = code to pk
        flushVerify(); save()
        return (if (seen != null && seen.fingerprint != fp) ScanResult.Mismatch else ScanResult.Verified) to (seen?.name ?: name)
    }

    private fun flushVerify() {
        val r = router ?: return
        for ((id, v) in pendingVerify.toList()) if (peers.any { it.id == id }) {
            pendingVerify.remove(id)
            r.sendVerify(v.first, id, v.second) { if (it == SendOutcome.Unreachable) pendingVerify[id] = v }
        }
    }

    /** Someone scanned our QR and proved it with the key we already know for them. */
    private fun confirmVerify(from: String, fp: String, code: String) {
        if (code !in myCodes) return
        verified = verified + fp
        peers = peers.map { it.copy(verified = it.fingerprint in verified) }
        peers.firstOrNull { it.id == from }?.let { ensureConversation(it); lastVerified = it.name }
        Notifier.tap(app); save()
    }

    fun setNickname(peer: Peer, name: String) {
        if (peer.fingerprint.isEmpty()) return
        nicknames = if (name.isBlank()) nicknames - peer.fingerprint else nicknames + (peer.fingerprint to name.trim())
        if (name.isNotBlank()) {
            peers = peers.map { if (it.fingerprint == peer.fingerprint) it.copy(name = name.trim()) else it }
            conversations = conversations.map { if (it.peer.fingerprint == peer.fingerprint) it.copy(peer = it.peer.copy(name = name.trim())) else it }
        }
        save()
    }

    fun toggleBlocked(id: String) { blocked = if (id in blocked) blocked - id else blocked + id; save() }

    /** Deletes the chat, nickname and verification. Blocking (if any) stays. */
    fun removeContact(peer: Peer) {
        conversations = conversations.filter { it.id != peer.id }
        verified = verified - peer.fingerprint; nicknames = nicknames - peer.fingerprint
        peers = peers.map { it.copy(verified = it.fingerprint in verified) }
        save()
    }

    fun send(text: String, id: String) {
        val m = Message(text, System.currentTimeMillis(), true, Delivery.Sending)
        conversations = conversations.map { if (it.id == id) it.copy(messages = it.messages + m) else it }
        save()
        when {
            simulated -> scope.launch {
                delay(600); update(m.id, id, Delivery.Sent)
                delay(900); update(m.id, id, Delivery.Delivered)
            }
            id == PUBLIC_CHANNEL_ID -> router?.sendPublic(text, m.id) { update(m.id, id, if (it == SendOutcome.Sent) Delivery.Sent else Delivery.Failed) }
                ?: update(m.id, id, Delivery.Failed)
            else -> trySend(m, id)
        }
    }

    fun retry(messageId: String, id: String) {
        conversations = conversations.map { c ->
            if (c.id != id) c else c.copy(messages = c.messages.map {
                if (it.id == messageId) it.copy(state = Delivery.Sending, timeMs = System.currentTimeMillis()) else it
            })
        }
        flushOutbox()
    }

    private fun trySend(m: Message, id: String) {
        val r = router ?: return
        if (!inflight.add(m.id)) return
        r.sendText(m.text, id, m.id) { outcome ->
            inflight.remove(m.id)
            when (outcome) {
                SendOutcome.Sent -> update(m.id, id, Delivery.Sent)
                SendOutcome.Failed -> update(m.id, id, Delivery.Failed)
                SendOutcome.Unreachable -> {}      // stays queued until the person comes into range
            }
        }
    }

    /** Sends queued messages whose recipient is now reachable; gives up after 10 minutes. */
    private fun flushOutbox() {
        if (simulated) return
        for (c in conversations) {
            if (c.id == PUBLIC_CHANNEL_ID) continue
            for (m in c.messages) {
                if (!m.mine || m.state != Delivery.Sending) continue
                if (System.currentTimeMillis() - m.timeMs > 600_000) update(m.id, c.id, Delivery.Failed)
                else if (peers.any { it.id == c.id }) trySend(m, c.id)
            }
        }
    }

    private fun applyPeers(list: List<Peer>) {
        val known = peers.map { it.id }.toSet()
        val mapped = list.map { it.copy(verified = it.fingerprint in verified, name = nicknames[it.fingerprint] ?: it.name) }.sortedWith(compareBy<Peer> { it.hops }.thenByDescending { it.rssi })
        if (mapped.any { it.id !in known }) Notifier.tap(app, 15)
        peers = mapped
        peerCountListener?.invoke(mapped.size)
        conversations = conversations.map { c -> mapped.firstOrNull { it.id == c.id }?.let { c.copy(peer = it) } ?: c }
        flushOutbox(); flushVerify()
    }

    private fun receiveText(from: String, sentName: String, text: String, hops: Int, id: String) {
        if (from in blocked) return
        val name = peers.firstOrNull { it.id == from }?.name ?: sentName
        ensureConversation(peers.firstOrNull { it.id == from } ?: Peer(from, name, hops, -80))
        if (conversations.firstOrNull { it.id == from }?.messages?.any { it.id == id } == true) return
        val m = Message(text, System.currentTimeMillis(), false, id = id, hops = hops)
        conversations = conversations.map {
            if (it.id == from) it.copy(messages = it.messages + m, unread = if (activeConversation == from) it.unread else it.unread + 1) else it
        }
        Notifier.notify(app, name, text)
        Notifier.tap(app)
        save()
    }

    private fun receivePublic(from: String, sentName: String, text: String, id: String) {
        if (from in blocked) return
        val name = peers.firstOrNull { it.id == from }?.name ?: sentName
        if (conversations.firstOrNull { it.id == PUBLIC_CHANNEL_ID }?.messages?.any { it.id == id } == true) return
        val m = Message(text, System.currentTimeMillis(), false, id = id, sender = name)
        conversations = conversations.map {
            if (it.id == PUBLIC_CHANNEL_ID) it.copy(messages = it.messages + m, unread = if (activeConversation == PUBLIC_CHANNEL_ID) it.unread else it.unread + 1) else it
        }
        Notifier.notify(app, "#nearby · $name", text)
        save()
    }

    private fun markDelivered(id: String) {
        conversations.filter { c -> c.messages.any { it.id == id } }.forEach { update(id, it.id, Delivery.Delivered) }
    }

    private fun update(mid: String, id: String, s: Delivery) {
        conversations = conversations.map { c ->
            if (c.id != id) c else c.copy(messages = c.messages.map {
                if (it.id != mid || (it.state == Delivery.Delivered && s != Delivery.Delivered)) it else it.copy(state = s)   // never downgrade
            })
        }
        save()
    }

    private fun ensurePublicChannel() {
        if (conversations.none { it.id == PUBLIC_CHANNEL_ID }) {
            conversations = listOf(Conversation(PUBLIC_CHANNEL_ID, Peer(PUBLIC_CHANNEL_ID, "Nearby", 1, -50), emptyList())) + conversations
        }
    }

    // ---- persistence

    private fun save() {
        if (simulated) return
        val o = JSONObject().put("verified", JSONArray(verified.toList())).put("nicknames", JSONObject(nicknames)).put("blocked", JSONArray(blocked.toList()))
        o.put("conversations", JSONArray(conversations.map { c ->
            JSONObject().put("id", c.id).put("unread", c.unread)
                .put("peer", JSONObject().put("id", c.peer.id).put("name", c.peer.name).put("hops", c.peer.hops).put("rssi", c.peer.rssi).put("fp", c.peer.fingerprint))
                .put("messages", JSONArray(c.messages.map { m ->
                    JSONObject().put("id", m.id).put("text", m.text).put("t", m.timeMs).put("mine", m.mine)
                        .put("state", m.state.name).put("hops", m.hops).apply { m.sender?.let { put("sender", it) } }
                }))
        }))
        runCatching { file.writeText(o.toString()) }
    }

    private fun load() {
        runCatching {
            val o = JSONObject(file.readText())
            verified = (0 until o.getJSONArray("verified").length()).map { o.getJSONArray("verified").getString(it) }.toSet()
            o.optJSONObject("nicknames")?.let { n -> nicknames = n.keys().asSequence().associateWith { n.getString(it) } }
            o.optJSONArray("blocked")?.let { b -> blocked = (0 until b.length()).map { b.getString(it) }.toSet() }
            val cs = o.getJSONArray("conversations")
            conversations = (0 until cs.length()).map { i ->
                val c = cs.getJSONObject(i); val p = c.getJSONObject("peer"); val ms = c.getJSONArray("messages")
                Conversation(c.getString("id"), Peer(p.getString("id"), p.getString("name"), p.getInt("hops"), p.getInt("rssi"), false, p.optString("fp")),
                    (0 until ms.length()).map { j ->
                        val m = ms.getJSONObject(j)
                        Message(m.getString("text"), m.getLong("t"), m.getBoolean("mine"), Delivery.valueOf(m.getString("state")),
                            m.getString("id"), m.getInt("hops"), if (m.has("sender")) m.getString("sender") else null)
                    }, c.getInt("unread"))
            }
        }
        // Messages still marked "sending" stay queued; they are retried when the person is next in range.
    }

    // ---- demo data (emulator)

    private fun seed() {
        peers = listOf(
            Peer("a", "Maja", 1, -48, true, "DEMO"), Peer("b", "Erik", 1, -66), Peer("c", "Noor", 2, -78),
            Peer("d", "Luca", 3, -88), Peer("e", "Sofia", 2, -72, true),
        )
        val now = System.currentTimeMillis()
        conversations = listOf(
            Conversation(PUBLIC_CHANNEL_ID, Peer(PUBLIC_CHANNEL_ID, "Nearby", 1, -50), listOf(
                Message("Anyone near the main stage?", now - 300_000, false, sender = "Luca"),
                Message("Yes, by the left speaker", now - 240_000, true, Delivery.Sent))),
            Conversation("a", peers[0], listOf(
                Message("Are you at the north gate?", now - 900_000, false),
                Message("Yes, by the water stand", now - 840_000, true),
                Message("Coming now 👋", now - 60_000, false)), unread = 1),
            Conversation("c", peers[2], listOf(Message("Relayed through Erik, nice range", now - 7_200_000, false, hops = 2))),
        )
    }

    private fun drift() {
        scope.launch {
            while (true) {
                delay(2500)
                peers = peers.map { it.copy(rssi = (it.rssi + (-3..3).random()).coerceIn(-95, -40)) }
            }
        }
    }
}
