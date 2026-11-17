package app.nearsend.chat

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
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
import java.util.Locale
import java.util.UUID
import androidx.compose.ui.graphics.asImageBitmap
import kotlin.math.roundToInt

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
    private var leftGroups = setOf<String>()                                 // group ids we left: their messages are dropped
    private val groupPending = HashMap<String, MutableSet<String>>()         // group message id -> members not sent to yet (memory only)
    private val groupAcks = HashMap<String, MutableSet<String>>()            // group message id -> members who confirmed
    private var contactKeys = mapOf<String, String>()                       // contact / group member id -> base64 key (saved)
    private val seenKeys = HashMap<String, ByteArray>()                      // every key seen this session
    private val handed = HashSet<String>()                                   // message ids the router stores/carries this session
    var posts by mutableStateOf(listOf<Post>()); private set                 // announcements, newest first (not saved)
    // Internet (optional, off by default): contacts out of Bluetooth range are reached through public relays
    var internetOn by mutableStateOf(prefs.getBoolean("internet", false)); private set
    var internetRelays by mutableStateOf(0); private set                     // relays connected right now
    private var inet: InternetRelay? = null
    private var inetSaved = 0L
    var batterySaver by mutableStateOf(prefs.getBoolean("saver", false)); private set   // black background, no animations
    var myAvatar by mutableStateOf(prefs.getString("avatar", null)?.let { Avatars.valid(it) }); private set   // our emoji + colour picture
    // Privacy settings
    var relayOthers by mutableStateOf(prefs.getBoolean("relay", true)); private set
    var receipts by mutableStateOf(prefs.getBoolean("receipts", true)); private set
    var hidePreviews by mutableStateOf(prefs.getBoolean("hidePreviews", false)); private set
    var autoDeleteDays by mutableStateOf(prefs.getInt("autoDelete", 0)); private set   // 0 = never
    var lastVerified by mutableStateOf<String?>(null)                       // who just confirmed our QR (shown on the QR screen)
    private val myCodes = HashSet<String>()                                  // one-time codes shown in our QR this session
    private val pendingVerify = HashMap<String, Pair<String, ByteArray>>()   // peer id -> (their code, their key), sent when reachable
    var activeConversation: String? = null
    var wipeCount by mutableStateOf(0); private set   // UI returns to onboarding when this changes
    var backgroundEnabled by mutableStateOf(prefs.getBoolean("background", true)); private set
    var peerCountListener: ((Int) -> Unit)? = null   // the foreground service keeps its notification up to date

    val simulated = isEmulator()
    var deviceId = prefs.getString("deviceID", null) ?: newDeviceId(); private set
    private var transport: BleTransport? = null
    private var router: MeshRouter? = null
    private val inflight = HashSet<String>()
    private val photoSentAt = HashMap<String, Long>()     // photo message id -> when all chunks last went out (waiting for the receipt)
    private val photoTries = HashMap<String, Int>()
    var photoProgress by mutableStateOf(mapOf<String, Float>()); private set   // photo message id -> 0..1 while sending
    private val photoDir get() = java.io.File(app.filesDir, "photos")
    private fun photoFile(id: String) = java.io.File(photoDir, "$id.webp")
    private val tick = object : Runnable { override fun run() { router?.tick(); prune(); noteInternet(); main.postDelayed(this, 8000) } }

    // SOS (declared before init: the emulator demo data fills [alerts])
    var alerts by mutableStateOf(listOf<SosAlert>()); private set     // received alarms, newest first (not saved)
    var mySos by mutableStateOf<String?>(null); private set              // our alarm id while SOS is on
    var sosNote by mutableStateOf("")
    var shareLocation by mutableStateOf(prefs.getBoolean("sosLocation", false)); private set
    var myLocation by mutableStateOf<Location?>(null); private set
    private var locationUsers = 0
    private val locationListener = LocationListener { myLocation = it }
    private val sosRepeat = object : Runnable {
        override fun run() { mySos?.let { router?.sendSos(it, sosNote, sharedLocation()) }; main.postDelayed(this, 15_000) }
    }

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
            r.onGroup = { from, name, g, gn, members, text, hops, id -> receiveGroup(from, name, g, gn, members, text, hops, id) }
            r.onSos = { from, name, alarm, note, loc, hops -> receiveSos(from, name, alarm, note, loc, hops) }
            r.onSosEnd = { from, alarm -> alerts = alerts.map { if (it.alarm == alarm && it.from == from) it.copy(active = false) else it } }
            r.onPost = { from, name, post, text, exp, hops -> receivePost(from, name, post, text, exp, hops) }
            r.onKey = { id, pk -> learnKey(id, pk) }
            r.onPhoto = { from, name, photo, bytes -> receivePhoto(from, name, photo, bytes) }
            r.savedKey = { id -> keyFor(id) }
            r.relay = relayOthers; r.sendAcks = receipts; r.myAvatar = myAvatar
            t.onNeighbor = { link, id, name, pk -> r.neighborConnected(link, id, name, pk) }
            t.onLost = { r.neighborLost(it) }
            t.onPacket = { data, link -> r.receive(data, link) }
            t.onRssi = { link, rssi -> r.updateRssi(link, rssi) }
            t.onState = { bluetoothState = it }
            router = r; transport = t
            if (internetOn) startInternet()
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
        stopSos()
        main.removeCallbacks(tick)
        stopInternet(); internetOn = false
        transport?.stop(); transport = null; router = null; inflight.clear()
        keys.wipe(); file.delete(); runCatching { photoDir.deleteRecursively() }
        prefs.edit().clear().apply()
        deviceId = newDeviceId()
        verified = emptySet(); peers = emptyList(); conversations = emptyList()
        nicknames = emptyMap(); blocked = emptySet(); leftGroups = emptySet(); groupPending.clear(); groupAcks.clear(); myCodes.clear(); pendingVerify.clear(); lastVerified = null; alerts = emptyList()
        contactKeys = emptyMap(); seenKeys.clear(); handed.clear(); posts = emptyList()
        relayOthers = true; receipts = true; hidePreviews = false; autoDeleteDays = 0; batterySaver = false; myAvatar = null
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
        ensureConversation(seen ?: Peer(id, name, 1, -80, fp in verified, fp))
        contactKeys = contactKeys + (id to Base64.getEncoder().encodeToString(pk)); save()
        return ScanResult.Added to (seen?.name ?: name)
    }

    /** Contents of our QR code. The one-time code proves to us that the scanner really saw this screen. */
    fun myQr(): String {
        val code = ByteArray(8).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
        myCodes += code
        return JSONObject().put("nearsend", 1).put("id", deviceId).put("n", nickname)
            .put("pk", Base64.getEncoder().encodeToString(keys.loadOrCreate().publicKey)).put("c", code).toString()
    }

    /** Our contact card as a chat message. Tapping it in a chat adds us as an UNVERIFIED contact (no one-time code). */
    fun myCard(): String = JSONObject().put("nearsend", 1).put("id", deviceId).put("n", nickname)
        .put("pk", Base64.getEncoder().encodeToString(keys.loadOrCreate().publicKey)).toString()

    /** Sends our last known position as a map link. False when there is no permission or no position yet. */
    @android.annotation.SuppressLint("MissingPermission")
    fun sendLocation(id: String): Boolean {
        if (!hasLocationPermission()) return false
        val lm = app.getSystemService(LocationManager::class.java)
        val fix = (listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).mapNotNull { runCatching { lm?.getLastKnownLocation(it) }.getOrNull() } +
            listOfNotNull(myLocation)).minByOrNull { it.accuracy } ?: return false
        send("\uD83D\uDCCD https://www.openstreetmap.org/?mlat=%.5f&mlon=%.5f".format(Locale.US, fix.latitude, fix.longitude), id)
        return true
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
        contactKeys = contactKeys + (id to Base64.getEncoder().encodeToString(pk))
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
        contactKeys = contactKeys - peer.id
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
            id.startsWith("g:") -> {
                groupPending[m.id] = groupTargets(id).toMutableSet()
                flushGroup(m, id)
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
        if (id.startsWith("g:")) groupPending[messageId] = groupTargets(id).toMutableSet()
        photoTries.remove(messageId); photoSentAt.remove(messageId)
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
                SendOutcome.Carried -> { handed += m.id; update(m.id, id, Delivery.Relayed) }   // a phone nearby carries it
                SendOutcome.Held -> handed += m.id                                               // we carry it ourselves
                SendOutcome.Unreachable -> {}      // no key: stays queued until the person comes into range
            }
        }
    }

    // ---- photos (direct chats, Bluetooth, someone in direct range)

    /** Shrinks the picture, keeps it on this phone and sends it as soon as the contact is in direct range. */
    fun sendPhoto(uri: android.net.Uri, id: String) {
        if (id == PUBLIC_CHANNEL_ID || id.startsWith("g:")) return
        Thread {
            val bytes = Photos.compress(app, uri)
            main.post {
                if (bytes == null) { android.widget.Toast.makeText(app, app.getString(R.string.photo_error), android.widget.Toast.LENGTH_SHORT).show(); return@post }
                val m = Message("", System.currentTimeMillis(), true, Delivery.Sending, photo = UUID.randomUUID().toString())
                runCatching { photoDir.mkdirs(); photoFile(m.photo!!).writeBytes(bytes) }
                conversations = conversations.map { if (it.id == id) it.copy(messages = it.messages + m) else it }
                save()
                if (simulated) scope.launch { delay(900); update(m.id, id, Delivery.Sent); delay(900); update(m.id, id, Delivery.Delivered) }
                else flushPhoto(m, id)
            }
        }.start()
    }

    fun loadPhoto(photo: String): androidx.compose.ui.graphics.ImageBitmap? =
        runCatching { android.graphics.BitmapFactory.decodeFile(photoFile(photo).path)?.asImageBitmap() }.getOrNull()

    /** Sends a waiting photo when its person is a direct neighbour; sends it again if no receipt came, then gives up. */
    private fun flushPhoto(m: Message, cid: String) {
        val r = router ?: return
        if (System.currentTimeMillis() - m.timeMs > MeshRouter.HOLD_MS) { update(m.id, cid, Delivery.Failed); return }
        if (peers.none { it.id == cid && it.hops == 1 }) return
        val last = photoSentAt[m.id]
        if (last != null && System.currentTimeMillis() - last < 30_000) return             // chunks are out, waiting for the receipt
        if ((photoTries[m.id] ?: 0) >= 4) { update(m.id, cid, Delivery.Failed); return }
        val bytes = runCatching { photoFile(m.photo!!).readBytes() }.getOrNull() ?: run { update(m.id, cid, Delivery.Failed); return }
        if (!inflight.add("photo." + m.id)) return
        photoTries[m.id] = (photoTries[m.id] ?: 0) + 1
        r.sendPhoto(bytes, cid, m.id, { f -> photoProgress = photoProgress + (m.id to f) }) { outcome ->
            inflight.remove("photo." + m.id)
            photoProgress = photoProgress - m.id
            when (outcome) {
                SendOutcome.Sent -> photoSentAt[m.id] = System.currentTimeMillis()
                SendOutcome.Failed -> photoSentAt[m.id] = System.currentTimeMillis() - 20_000      // try again soon
                else -> photoTries[m.id] = (photoTries[m.id] ?: 1) - 1                              // person walked away: not a try
            }
        }
    }

    private fun receivePhoto(from: String, sentName: String, photo: String, bytes: ByteArray) {
        if (from in blocked) return
        val name = peers.firstOrNull { it.id == from }?.name ?: sentName
        ensureConversation(peers.firstOrNull { it.id == from } ?: Peer(from, name, 1, -80))
        runCatching { photoDir.mkdirs(); photoFile(photo).writeBytes(bytes) }.onFailure { return }
        val m = Message("", System.currentTimeMillis(), false, id = photo, photo = photo)
        conversations = conversations.map {
            if (it.id == from) it.copy(messages = it.messages + m, unread = if (activeConversation == from) it.unread else it.unread + 1) else it
        }
        Notifier.notify(app, name, if (hidePreviews) app.getString(R.string.notif_hidden) else "\uD83D\uDCF7 " + app.getString(R.string.attach_photo))
        Notifier.tap(app)
        save()
    }

    private fun deletePhotos(messages: List<Message>) = messages.forEach { m -> m.photo?.let { runCatching { photoFile(it).delete() } } }

    // ---- groups

    fun createGroup(name: String, people: List<Peer>): String {
        val id = "g:" + UUID.randomUUID()
        val members = listOf(deviceId to nickname) + people.map { it.id to it.name }
        conversations = conversations + Conversation(id, Peer(id, name.trim(), 1, -50), emptyList(), members = members)
        save()
        return id
    }

    fun leaveGroup(id: String) {
        conversations = conversations.filter { it.id != id }
        leftGroups = leftGroups + id
        save()
    }

    private fun groupTargets(id: String) = conversations.firstOrNull { it.id == id }?.members.orEmpty().map { it.first }.filter { it != deviceId }

    /** Sends the copies of [m] whose member is reachable now; the rest wait in [groupPending]. */
    private fun flushGroup(m: Message, gid: String) {
        val r = router ?: return
        val c = conversations.firstOrNull { it.id == gid } ?: return
        val pending = groupPending[m.id] ?: return
        val members = c.members.orEmpty().map { if (it.first == deviceId) it.first to nickname else it }
        for (member in pending.toList()) {
            if ((peers.none { it.id == member } && keyFor(member) == null) || !inflight.add("${m.id}.$member")) continue
            r.sendGroup(m.text, gid, c.peer.name, members, member, m.id) { outcome ->
                inflight.remove("${m.id}.$member")
                if (outcome != SendOutcome.Unreachable) pending.remove(member)
                if (outcome == SendOutcome.Sent) update(m.id, gid, Delivery.Sent)
                else if (outcome == SendOutcome.Carried && m.state == Delivery.Sending) update(m.id, gid, Delivery.Relayed)
                else if (outcome == SendOutcome.Failed && pending.isEmpty() && m.state == Delivery.Sending) update(m.id, gid, Delivery.Failed)
            }
        }
    }

    private fun receiveGroup(from: String, sentName: String, gid: String, gname: String, members: List<Pair<String, String>>, text: String, hops: Int, id: String) {
        if (from in blocked || gid in leftGroups || members.none { it.first == deviceId }) return
        val name = peers.firstOrNull { it.id == from }?.name ?: sentName
        if (conversations.none { it.id == gid }) conversations = conversations + Conversation(gid, Peer(gid, gname, 1, -50), emptyList(), members = members)
        if (conversations.first { it.id == gid }.messages.any { it.id == id }) return
        val m = Message(text, System.currentTimeMillis(), false, id = id, hops = hops, sender = name)
        conversations = conversations.map {
            if (it.id == gid) it.copy(peer = it.peer.copy(name = gname), members = members, messages = it.messages + m,
                unread = if (activeConversation == gid) it.unread else it.unread + 1) else it
        }
        Notifier.notify(app, "$gname · $name", preview(text))
        Notifier.tap(app)
        save()
    }

    /** Sends queued messages whose recipient is now reachable. Contacts whose key we have get a day (phones nearby carry
     *  the message); others 10 minutes. */
    private fun flushOutbox() {
        if (simulated) return
        for (c in conversations) {
            if (c.id == PUBLIC_CHANNEL_ID) continue
            if (c.isGroup) {
                for (m in c.messages) if (m.mine && groupPending[m.id]?.isNotEmpty() == true) {
                    if (System.currentTimeMillis() - m.timeMs > 600_000) {
                        groupPending.remove(m.id)
                        if (m.state == Delivery.Sending) update(m.id, c.id, Delivery.Failed)
                    } else flushGroup(m, c.id)
                }
                continue
            }
            for (m in c.messages) {
                if (!m.mine || m.state != Delivery.Sending) continue
                if (m.photo != null) { flushPhoto(m, c.id); continue }
                val carried = keyFor(c.id) != null
                if (System.currentTimeMillis() - m.timeMs > if (carried) MeshRouter.HOLD_MS else 600_000) update(m.id, c.id, Delivery.Failed)
                else if (peers.any { it.id == c.id } || (carried && m.id !in handed)) trySend(m, c.id)
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
        Notifier.notify(app, name, preview(text))
        Notifier.tap(app)
        save()
    }

    private fun preview(text: String) = if (hidePreviews) app.getString(R.string.notif_hidden) else text

    // ---- saved keys (store-and-forward needs the key of someone who is away)

    private fun learnKey(id: String, pk: ByteArray) {
        seenKeys[id] = pk
        if (id in keepKeysFor() && contactKeys[id] == null) { contactKeys = contactKeys + (id to Base64.getEncoder().encodeToString(pk)); save() }
    }

    private fun keepKeysFor(): Set<String> = conversations.flatMap { c -> listOf(c.id) + c.members.orEmpty().map { it.first } }.toSet()

    /** True when phones nearby can carry messages to this person while they are away. */
    fun canCarryTo(id: String) = keyFor(id) != null

    private fun keyFor(id: String): ByteArray? =
        seenKeys[id] ?: contactKeys[id]?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }

    // ---- internet

    /** Contacts who are out of Bluetooth range but can be written to over the internet (shown on the radar). */
    val awayContacts: List<Peer> get() = if (!internetOn) emptyList() else conversations
        .filter { c -> !c.isGroup && c.id != PUBLIC_CHANNEL_ID && c.id !in blocked && peers.none { it.id == c.id } && keyFor(c.id) != null }
        .map { it.peer }

    fun changeInternet(on: Boolean) {
        internetOn = on; prefs.edit().putBoolean("internet", on).apply()
        if (simulated) { internetRelays = if (on) 3 else 0; return }
        if (on) startInternet() else stopInternet()
    }

    private fun startInternet() {
        val r = router ?: return        // started together with the mesh
        if (inet != null) return
        val relay = InternetRelay(keys.loadOrCreate()) { f -> main.post { f() } }
        // Ask for what arrived since we were last connected (with some slack for clocks), at most the day relays keep it.
        relay.since = maxOf(prefs.getLong("inetSeen", 0) - 900, System.currentTimeMillis() / 1000 - RelayEvent.KEEP_S)
        relay.onPacket = { if (inet === relay) router?.receiveUplink(it) }
        relay.onState = { n ->
            if (inet === relay) {
                val cameUp = internetRelays == 0 && n > 0
                internetRelays = n
                if (cameUp) router?.uplinkHeld { markCarried(it) }      // messages that were waiting go out now
            }
        }
        r.uplink = { pk, data, done -> relay.publish(pk, data, done) }
        inet = relay; relay.start()
    }

    private fun stopInternet() { inet?.stop(); inet = null; router?.uplink = null; internetRelays = 0 }

    /** Remembers when we were last connected, so the next start only asks the relays for newer messages. */
    private fun noteInternet() {
        val s = System.currentTimeMillis() / 1000
        if (inet == null || internetRelays == 0 || s - inetSaved < 60) return
        inetSaved = s; prefs.edit().putLong("inetSeen", s).apply()
    }

    /** A relay stored one of our waiting packets ("<message id>" or "<message id>.<group member>"). */
    private fun markCarried(packetId: String) {
        val mid = packetId.substringBefore('.')
        val c = conversations.firstOrNull { cv -> cv.messages.any { it.id == mid && it.mine && it.state == Delivery.Sending } } ?: return
        handed += mid; update(mid, c.id, Delivery.Relayed)
    }

    // ---- announcements

    fun post(text: String, hours: Int) {
        val id = UUID.randomUUID().toString(); val exp = System.currentTimeMillis() + hours * 3_600_000L
        router?.sendPost(text.trim(), id, exp)
        posts = listOf(Post(id, deviceId, nickname, MeshRouter.clip(text.trim()), exp, true)) + posts
    }

    private fun receivePost(from: String, sentName: String, id: String, text: String, exp: Long, hops: Int) {
        if (from in blocked || posts.any { it.id == id }) return
        val name = peers.firstOrNull { it.id == from }?.name ?: sentName
        posts = listOf(Post(id, from, name, text, exp, false, hops)) + posts
        Notifier.notify(app, "📢 $name", preview(text))
    }

    // ---- privacy

    /** Sets our picture ("<emoji>|<colour>", see Avatars) or clears it (null = show the initial). Goes out with the next announcement. */
    fun changeAvatar(a: String?) {
        myAvatar = a; router?.myAvatar = a
        prefs.edit().apply { if (a == null) remove("avatar") else putString("avatar", a) }.apply()
    }
    fun changeBatterySaver(on: Boolean) { batterySaver = on; prefs.edit().putBoolean("saver", on).apply() }
    fun changeRelay(on: Boolean) { relayOthers = on; router?.relay = on; prefs.edit().putBoolean("relay", on).apply() }
    fun changeReceipts(on: Boolean) { receipts = on; router?.sendAcks = on; prefs.edit().putBoolean("receipts", on).apply() }
    fun changeHidePreviews(on: Boolean) { hidePreviews = on; prefs.edit().putBoolean("hidePreviews", on).apply() }
    fun changeAutoDelete(days: Int) { autoDeleteDays = days; prefs.edit().putInt("autoDelete", days).apply(); prune() }

    /** Drops expired announcements and, if auto-delete is on, messages older than the chosen number of days. */
    private fun prune() {
        val now = System.currentTimeMillis()
        if (posts.any { it.expMs <= now }) posts = posts.filter { it.expMs > now }
        if (autoDeleteDays <= 0) return
        val cutoff = now - autoDeleteDays * 86_400_000L
        if (conversations.none { c -> c.messages.any { it.timeMs < cutoff } }) return
        conversations.forEach { c -> deletePhotos(c.messages.filter { it.timeMs < cutoff }) }
        conversations = conversations.map { c -> c.copy(messages = c.messages.filter { it.timeMs >= cutoff }) }
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
        Notifier.notify(app, "#nearby · $name", preview(text))
        save()
    }

    // ---- SOS

    val activeAlerts get() = alerts.count { it.active }

    fun shareLocationOn(on: Boolean) { shareLocation = on; prefs.edit().putBoolean("sosLocation", on).apply() }

    fun hasLocationPermission() = ContextCompat.checkSelfPermission(app, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ContextCompat.checkSelfPermission(app, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** Repeats every 15 s while on, so phones that come into range later still get it (the mesh keeps nothing). */
    fun startSos() {
        if (mySos != null) return
        mySos = UUID.randomUUID().toString()
        useLocation(true)
        Notifier.tap(app, 300)
        main.post(sosRepeat)
    }

    fun stopSos() {
        val alarm = mySos ?: return
        mySos = null
        main.removeCallbacks(sosRepeat)
        router?.sendSos(alarm, null, null, end = true)
        useLocation(false)
    }

    private fun sharedLocation(): String? = myLocation?.takeIf { shareLocation }
        ?.let { "%.5f,%.5f,%d".format(Locale.US, it.latitude, it.longitude, it.accuracy.roundToInt()) }

    /** The SOS screen (for distances) and an active alarm each hold a "use"; GPS runs only while someone needs it. */
    @android.annotation.SuppressLint("MissingPermission")
    fun useLocation(on: Boolean) {
        locationUsers = (locationUsers + if (on) 1 else -1).coerceAtLeast(0)
        val lm = app.getSystemService(LocationManager::class.java) ?: return
        lm.removeUpdates(locationListener)
        if (locationUsers == 0 || !hasLocationPermission()) return
        for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            if (!lm.isProviderEnabled(provider)) continue
            lm.getLastKnownLocation(provider)?.let { if (myLocation == null || it.accuracy < myLocation!!.accuracy) myLocation = it }
            lm.requestLocationUpdates(provider, 5_000L, 0f, locationListener, Looper.getMainLooper())
        }
    }

    private fun receiveSos(from: String, sentName: String, alarm: String, note: String?, loc: String?, hops: Int) {
        if (from in blocked) return
        val parts = loc?.split(",")?.mapNotNull { it.trim().toDoubleOrNull() }?.takeIf { it.size == 3 }
        val name = peers.firstOrNull { it.id == from }?.name ?: sentName
        val old = alerts.firstOrNull { it.alarm == alarm && it.from == from }
        val a = SosAlert(alarm, from, name, note, parts?.get(0), parts?.get(1), parts?.get(2)?.roundToInt(), hops, System.currentTimeMillis())
        alerts = if (old == null) listOf(a) + alerts else alerts.map { if (it === old) a else it }
        if (old == null || !old.active) Notifier.alarm(app, "SOS · $name", note ?: "")
    }

    private fun markDelivered(id: String) {
        if ('.' in id) {   // a group copy: "<message id>.<member>"; delivered once every member confirmed
            val mid = id.substringBefore('.')
            val c = conversations.firstOrNull { cv -> cv.messages.any { it.id == mid } } ?: return
            val acks = groupAcks.getOrPut(mid) { mutableSetOf() }.apply { add(id.substringAfter('.')) }
            if (acks.containsAll(groupTargets(c.id))) { update(mid, c.id, Delivery.Delivered); groupAcks.remove(mid) }
            return
        }
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
            .put("leftGroups", JSONArray(leftGroups.toList()))
            .put("keys", JSONObject(contactKeys.filterKeys { it in keepKeysFor() }))
        o.put("conversations", JSONArray(conversations.map { c ->
            JSONObject().put("id", c.id).put("unread", c.unread)
                .put("peer", JSONObject().put("id", c.peer.id).put("name", c.peer.name).put("hops", c.peer.hops).put("rssi", c.peer.rssi).put("fp", c.peer.fingerprint).put("av", c.peer.avatar ?: ""))
                .apply { c.members?.let { ms -> put("members", JSONArray(ms.map { JSONObject().put("id", it.first).put("n", it.second) })) } }
                .put("messages", JSONArray(c.messages.map { m ->
                    JSONObject().put("id", m.id).put("text", m.text).put("t", m.timeMs).put("mine", m.mine)
                        .put("state", m.state.name).put("hops", m.hops).apply { m.sender?.let { put("sender", it) }; m.photo?.let { put("photo", it) } }
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
            o.optJSONArray("leftGroups")?.let { b -> leftGroups = (0 until b.length()).map { b.getString(it) }.toSet() }
            o.optJSONObject("keys")?.let { k -> contactKeys = k.keys().asSequence().associateWith { k.getString(it) } }
            val cs = o.getJSONArray("conversations")
            conversations = (0 until cs.length()).map { i ->
                val c = cs.getJSONObject(i); val p = c.getJSONObject("peer"); val ms = c.getJSONArray("messages")
                Conversation(c.getString("id"), Peer(p.getString("id"), p.getString("name"), p.getInt("hops"), p.getInt("rssi"), false, p.optString("fp"), avatar = Avatars.valid(p.optString("av"))),
                    (0 until ms.length()).map { j ->
                        val m = ms.getJSONObject(j)
                        Message(m.getString("text"), m.getLong("t"), m.getBoolean("mine"), Delivery.valueOf(m.getString("state")),
                            m.getString("id"), m.getInt("hops"), if (m.has("sender")) m.getString("sender") else null, if (m.has("photo")) m.getString("photo") else null)
                    }, c.getInt("unread"),
                    c.optJSONArray("members")?.let { ms -> (0 until ms.length()).map { ms.getJSONObject(it).let { m -> m.getString("id") to m.getString("n") } } })
            }
        }
        // Messages still marked "sending" stay queued; they are retried when the person is next in range.
        prune()
    }

    // ---- demo data (emulator)

    private fun seed() {
        peers = listOf(
            Peer("a", "Maja", 1, -48, true, "DEMO", avatar = Avatars.encode(Avatars.EMOJIS[6], 1)), Peer("b", "Erik", 1, -66, avatar = Avatars.encode(Avatars.EMOJIS[21], 3)),
            Peer("c", "Noor", 2, -78, via = "b", avatar = Avatars.encode(Avatars.EMOJIS[13], 2)),
            Peer("d", "Luca", 3, -88, via = "c"), Peer("e", "Sofia", 2, -72, true, via = "a", avatar = Avatars.encode(Avatars.EMOJIS[9], 5)),
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
            Conversation("f", Peer("f", "Ines", 1, -80, true), listOf(Message("Train is late, save me a spot!", now - 3_000_000, false))),
            Conversation("g:demo", Peer("g:demo", "Festival crew", 1, -50), listOf(
                Message("Meet at the food trucks at 8?", now - 1_500_000, false, sender = "Maja"),
                Message("Works for me", now - 1_400_000, false, sender = "Erik", hops = 2),
                Message("See you there", now - 1_300_000, true)),
                members = listOf(deviceId to nickname, "a" to "Maja", "b" to "Erik")),
        )
        // Near the emulator's default position, so the SOS tab shows a distance and direction.
        alerts = listOf(SosAlert("demo-sos", "c", "Noor", "Twisted ankle by the lake path", 37.4252, -122.0815, 9, 2, now - 120_000))
        contactKeys = mapOf("f" to Base64.getEncoder().encodeToString(ByteArray(32)))   // Ines is a saved contact, out of range
        if (internetOn) internetRelays = 3
        posts = listOf(
            Post("demo-p1", "e", "Sofia", "Free water refills at the info tent until 18:00", now + 5 * 3_600_000L, false, 2),
            Post("demo-p2", "d", "Luca", "Found: blue backpack near stage B. Ask at the info tent.", now + 40 * 60_000L, false, 3))
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
