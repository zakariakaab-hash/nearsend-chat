package app.nearsend.chat

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.Base64
import java.util.UUID

/**
 * Bluetooth LE link layer, wire-compatible with the iOS app (same UUIDs, identity JSON {"id","name","pk"}).
 * Every phone advertises the service (GATT server) and scans for it (GATT client). It only moves bytes:
 * identities and packets go up to [MeshRouter] (see PROTOCOL.md).
 *
 * Two kinds of link, because discovery can be one-sided (e.g. an iPhone app in the background is invisible to Android scans):
 * - "out:<addr>": we connected to that phone's server. We write packets to its packet characteristic and receive its notifications.
 * - "in:<addr>":  that phone connected to our server and subscribed to our notify characteristic. We reply by notifying it.
 */
@SuppressLint("MissingPermission")
class BleTransport(private val ctx: Context, private val id: String, private var name: String, private val publicKey: ByteArray) {
    companion object {
        val SERVICE: UUID = UUID.fromString("7A3C5E10-9D2B-4F6A-8C1E-4E4541525345")
        val ID_CHAR: UUID = UUID.fromString("7A3C5E11-9D2B-4F6A-8C1E-4E4541525345")
        val MSG_CHAR: UUID = UUID.fromString("7A3C5E12-9D2B-4F6A-8C1E-4E4541525345")
        val NOTIFY_CHAR: UUID = UUID.fromString("7A3C5E13-9D2B-4F6A-8C1E-4E4541525345")
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    var onNeighbor: ((link: String, id: String, name: String, pk: ByteArray) -> Unit)? = null
    var onLost: ((link: String) -> Unit)? = null
    var onPacket: ((data: ByteArray, link: String) -> Unit)? = null
    var onRssi: ((link: String, rssi: Int) -> Unit)? = null
    var onState: ((String) -> Unit)? = null

    /** Our central connection to a neighbour's server (an "out" link). */
    private class Link(val gatt: BluetoothGatt) {
        var msgChar: BluetoothGattCharacteristic? = null
        var notifyChar: BluetoothGattCharacteristic? = null
        var identityChar: BluetoothGattCharacteristic? = null
        var identity: Triple<String, String, ByteArray>? = null
        var peerId: String? = null
        var notifyReady = false
        var announced = false
        var busy = false
        val queue = ArrayDeque<Pair<ByteArray, (Boolean) -> Unit>>()
        var inflight: ((Boolean) -> Unit)? = null
        val rx = Reassembler()
        fun failAll() { inflight?.invoke(false); inflight = null; queue.forEach { it.second(false) }; queue.clear() }
    }

    /** Fragments of one packet waiting to be notified to a subscribed phone. */
    private class OutNotify(val addr: String, val frags: ArrayDeque<ByteArray>, val done: (Boolean) -> Unit)

    private val main = Handler(Looper.getMainLooper())
    private val btManager = ctx.getSystemService(BluetoothManager::class.java)
    private var server: BluetoothGattServer? = null
    private var running = false
    private val links = HashMap<String, Link>()                 // key: device address (main thread only)
    private val pendingWrites = HashMap<String, ByteArrayOutputStream>()
    private val subscribers = HashMap<String, BluetoothDevice>()   // phones subscribed to our notify characteristic
    private val mtus = HashMap<String, Int>()
    private val notifySeq = HashMap<String, Int>()
    private val notifyQueue = ArrayDeque<OutNotify>()
    private var notifying = false
    private var notifyCharacteristic: BluetoothGattCharacteristic? = null

    private val rssiTick = object : Runnable {
        override fun run() {
            links.values.forEach { if (!it.busy && it.announced) it.gatt.readRemoteRssi() }
            if (running) main.postDelayed(this, 2000)
        }
    }

    fun start() {
        val adapter = btManager?.adapter
        if (adapter == null) { NLog.i("ble", "no Bluetooth adapter"); onState?.invoke("unsupported"); return }
        if (!adapter.isEnabled) { NLog.i("ble", "Bluetooth is off"); onState?.invoke("off"); return }
        if (running) return
        NLog.i("ble", "start: advertising + scanning, my id ${NLog.s(id)}")
        running = true
        server = btManager.openGattServer(ctx, serverCb)
        val svc = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        svc.addCharacteristic(BluetoothGattCharacteristic(ID_CHAR, BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ))
        svc.addCharacteristic(BluetoothGattCharacteristic(MSG_CHAR, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE))
        val nc = BluetoothGattCharacteristic(NOTIFY_CHAR, BluetoothGattCharacteristic.PROPERTY_NOTIFY, 0)
        nc.addDescriptor(BluetoothGattDescriptor(CCCD, BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
        notifyCharacteristic = nc
        svc.addCharacteristic(nc)
        server?.addService(svc)   // advertising starts in onServiceAdded
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_BALANCED).build()
        adapter.bluetoothLeScanner?.startScan(listOf(filter), settings, scanCb)
        main.postDelayed(rssiTick, 2000)
        onState?.invoke("ready")
    }

    fun stop() {
        NLog.i("ble", "stop")
        running = false
        main.removeCallbacks(rssiTick)
        val adapter = btManager?.adapter
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCb) }
        runCatching { adapter?.bluetoothLeAdvertiser?.stopAdvertising(advCb) }
        links.forEach { (addr, l) -> l.failAll(); runCatching { l.gatt.close() }; if (l.announced) onLost?.invoke("out:$addr") }
        links.clear()
        subscribers.keys.toList().forEach { onLost?.invoke("in:$it") }
        subscribers.clear(); mtus.clear(); notifySeq.clear(); pendingWrites.clear()
        notifyQueue.forEach { it.done(false) }; notifyQueue.clear(); notifying = false
        runCatching { server?.close() }
        server = null; notifyCharacteristic = null
    }

    fun setName(n: String) { name = n }   // identity is read on demand, so nothing to rebuild

    /** Sends one packet to a neighbour over "out:" (write) or "in:" (notify). `done(true)` once it was handed over / acknowledged. */
    fun write(linkId: String, data: ByteArray, done: (Boolean) -> Unit) {
        when {
            linkId.startsWith("out:") -> {
                val link = links[linkId.removePrefix("out:")]
                if (link == null || link.msgChar == null) { done(false); return }
                link.queue.addLast(data to done)
                pump(link)
            }
            linkId.startsWith("in:") -> {
                val addr = linkId.removePrefix("in:")
                if (subscribers[addr] == null) { done(false); return }
                val seq = notifySeq[addr] ?: 0
                notifySeq[addr] = (seq + 1) and 0xFF
                val frags = Framing.fragments(data, seq, (mtus[addr] ?: 23) - 3 - 3)
                if (frags.isEmpty()) { done(false); return }
                notifyQueue.addLast(OutNotify(addr, ArrayDeque(frags), done))
                pumpNotify()
            }
            else -> done(false)
        }
    }

    // ---- writing to a neighbour's server ("out" links)

    /** GATT allows one operation at a time, so packets are written one after another. */
    private fun pump(link: Link) {
        val ch = link.msgChar ?: return
        if (link.busy) return
        val (data, done) = link.queue.removeFirstOrNull() ?: return
        link.busy = true
        link.inflight = done
        val ok = if (Build.VERSION.SDK_INT >= 33) {
            link.gatt.writeCharacteristic(ch, data, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION") run {
                ch.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                ch.value = data
                link.gatt.writeCharacteristic(ch)
            }
        }
        if (!ok) { NLog.i("ble", "write refused by the phone (${data.size} bytes)"); link.busy = false; link.inflight = null; done(false); pump(link) }
    }

    // ---- notifying a phone that connected to us ("in" links)

    private fun pumpNotify() {
        if (notifying) return
        val out = notifyQueue.firstOrNull() ?: return
        val device = subscribers[out.addr]
        val ch = notifyCharacteristic
        val frag = out.frags.firstOrNull()
        if (device == null || ch == null || frag == null) {
            notifyQueue.removeFirst()
            out.done(device != null && frag == null)     // all fragments sent -> true
            pumpNotify()
            return
        }
        notifying = true
        val ok = if (Build.VERSION.SDK_INT >= 33) {
            server?.notifyCharacteristicChanged(device, ch, false, frag) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION") run { ch.value = frag; server?.notifyCharacteristicChanged(device, ch, false) == true }
        }
        if (!ok) { NLog.i("ble", "notify refused for ${NLog.l("in:" + out.addr)}"); notifying = false; notifyQueue.removeFirst(); out.done(false); pumpNotify() }
    }

    private fun removeSubscriber(addr: String) {
        if (subscribers.remove(addr) == null) return
        NLog.i("ble", "subscriber left ${NLog.l("in:$addr")}")
        mtus.remove(addr); notifySeq.remove(addr)
        if (notifying && notifyQueue.firstOrNull()?.addr == addr) notifying = false   // its completion callback will never come
        val it = notifyQueue.iterator()
        while (it.hasNext()) { val o = it.next(); if (o.addr == addr) { it.remove(); o.done(false) } }
        onLost?.invoke("in:$addr")
        pumpNotify()
    }

    // ---- discovery of neighbours ("out" links)

    private fun identityBytes() = JSONObject().put("id", id).put("name", name)
        .put("pk", Base64.getEncoder().encodeToString(publicKey)).toString().toByteArray()

    private fun readIdentity(link: Link) {
        val ic = link.identityChar ?: return
        link.busy = true
        if (!link.gatt.readCharacteristic(ic)) link.busy = false
    }

    private fun handleIdentity(gatt: BluetoothGatt, bytes: ByteArray?) {
        val addr = gatt.device.address
        val link = links[addr] ?: return
        link.busy = false
        val o = runCatching { JSONObject(String(bytes ?: return)) }.getOrNull() ?: return NLog.i("ble", "identity from ${NLog.l("out:$addr")} is not valid JSON")
        val pid = o.optString("id")
        val pk = runCatching { Base64.getDecoder().decode(o.optString("pk")) }.getOrNull() ?: return NLog.i("ble", "identity from ${NLog.l("out:$addr")} has a bad key")
        if (pid.isEmpty() || pid == id || pk.size != 32) return
        link.identity = Triple(pid, o.optString("name"), pk)
        maybeAnnounce(addr, link)
        pump(link)
    }

    /** A link becomes a neighbour once we have subscribed to its notifications AND read its identity. */
    private fun maybeAnnounce(addr: String, link: Link) {
        val ident = link.identity ?: return
        if (link.announced || !link.notifyReady) return
        // Same phone seen under a new address: drop the stale link.
        links.entries.filter { it.value !== link && it.value.peerId == ident.first }.forEach { e ->
            links.remove(e.key); e.value.failAll(); runCatching { e.value.gatt.close() }; onLost?.invoke("out:${e.key}")
        }
        link.announced = true
        NLog.i("ble", "link ready out:${NLog.s(ident.first)} ${NLog.l("out:$addr")} (notifications on, identity read)")
        link.peerId = ident.first
        onNeighbor?.invoke("out:$addr", ident.first, ident.second, ident.third)
        link.gatt.readRemoteRssi()
    }

    private fun drop(gatt: BluetoothGatt) {
        val addr = gatt.device.address
        val link = links.remove(addr)
        NLog.i("ble", "drop ${NLog.l("out:$addr")} announced=${link?.announced}")
        link?.failAll()
        runCatching { gatt.close() }
        if (link?.announced == true) onLost?.invoke("out:$addr")
    }

    private fun incoming(gatt: BluetoothGatt, bytes: ByteArray?) {
        val link = links[gatt.device.address] ?: return
        val packet = link.rx.add(bytes ?: return) ?: return
        onPacket?.invoke(packet, "out:${gatt.device.address}")
    }

    private val scanCb = object : ScanCallback() {
        override fun onScanFailed(errorCode: Int) { NLog.i("ble", "scan FAILED, error $errorCode") }

        override fun onScanResult(callbackType: Int, result: ScanResult) {
            main.post {
                if (!running) return@post
                val addr = result.device.address
                if (links.containsKey(addr)) return@post
                NLog.i("ble", "found ${NLog.l("out:$addr")} rssi=${result.rssi}, connecting")
                links[addr] = Link(result.device.connectGatt(ctx, false, gattCb, BluetoothDevice.TRANSPORT_LE))
            }
        }
    }

    private val advCb = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) { NLog.i("ble", "advertising started") }
        override fun onStartFailure(errorCode: Int) { NLog.i("ble", "advertising FAILED, error $errorCode (1=too large 2=too many advertisers 3=already started 4=internal 5=unsupported)") }
    }

    private val gattCb = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            NLog.i("ble", "out ${NLog.l("out:" + gatt.device.address)} state=$newState status=$status")
            main.post {
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    if (!gatt.requestMtu(247)) gatt.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED || status != BluetoothGatt.GATT_SUCCESS) {
                    drop(gatt)
                }
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            NLog.i("ble", "out ${NLog.l("out:" + gatt.device.address)} mtu=$mtu status=$status")
            main.post { gatt.discoverServices() }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            main.post {
                val link = links[gatt.device.address] ?: return@post
                val svc = gatt.getService(SERVICE) ?: return@post NLog.i("ble", "out ${NLog.l("out:" + gatt.device.address)} has no Nearsend service (status $status)")
                link.msgChar = svc.getCharacteristic(MSG_CHAR)
                link.identityChar = svc.getCharacteristic(ID_CHAR)
                link.notifyChar = svc.getCharacteristic(NOTIFY_CHAR)
                // Step 1: subscribe to the phone's notifications (so it can answer us). Step 2 (after it completes): read its identity.
                val nc = link.notifyChar
                val cccd = nc?.getDescriptor(CCCD)
                if (nc != null && cccd != null && gatt.setCharacteristicNotification(nc, true)) {
                    link.busy = true
                    val ok = if (Build.VERSION.SDK_INT >= 33) {
                        gatt.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS
                    } else {
                        @Suppress("DEPRECATION") run { cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE; gatt.writeDescriptor(cccd) }
                    }
                    if (!ok) { link.busy = false; link.notifyReady = true; readIdentity(link) }
                } else {                                   // older peers have no notify characteristic
                    link.notifyReady = true
                    readIdentity(link)
                }
            }
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            main.post {
                val link = links[gatt.device.address] ?: return@post
                link.busy = false
                link.notifyReady = true
                readIdentity(link)
            }
        }

        @Deprecated("Used on API < 33")
        override fun onCharacteristicRead(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT < 33 && ch.uuid == ID_CHAR) {
                @Suppress("DEPRECATION") val v = ch.value
                main.post { handleIdentity(gatt, v) }
            }
        }

        override fun onCharacteristicRead(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            if (ch.uuid == ID_CHAR) main.post { handleIdentity(gatt, value) }
        }

        @Deprecated("Used on API < 33")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33 && ch.uuid == NOTIFY_CHAR) {
                @Suppress("DEPRECATION") val v = ch.value
                main.post { incoming(gatt, v) }
            }
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, value: ByteArray) {
            if (ch.uuid == NOTIFY_CHAR) main.post { incoming(gatt, value) }
        }

        override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
            main.post {
                val link = links[gatt.device.address] ?: return@post
                if (status == BluetoothGatt.GATT_SUCCESS && link.announced) onRssi?.invoke("out:${gatt.device.address}", rssi)
            }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, ch: BluetoothGattCharacteristic, status: Int) {
            main.post {
                val link = links[gatt.device.address] ?: return@post
                link.busy = false
                if (status != BluetoothGatt.GATT_SUCCESS) NLog.i("ble", "write to ${NLog.l("out:" + gatt.device.address)} failed, status $status")
                val cb = link.inflight; link.inflight = null
                cb?.invoke(status == BluetoothGatt.GATT_SUCCESS)
                pump(link)
            }
        }
    }

    private val serverCb = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (status != BluetoothGatt.GATT_SUCCESS) { NLog.i("ble", "adding the GATT service FAILED, status $status"); return }
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(true).build()
            val data = AdvertiseData.Builder().setIncludeDeviceName(false).addServiceUuid(ParcelUuid(SERVICE)).build()
            btManager?.adapter?.bluetoothLeAdvertiser?.startAdvertising(settings, data, advCb)
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            NLog.i("ble", "in ${NLog.l("in:" + device.address)} state=$newState status=$status")
            if (newState == BluetoothProfile.STATE_DISCONNECTED) main.post { removeSubscriber(device.address) }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) { main.post { mtus[device.address] = mtu } }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (descriptor.uuid == CCCD && descriptor.characteristic.uuid == NOTIFY_CHAR) {
                val on = value != null && value.isNotEmpty() && value[0].toInt() != 0
                main.post { if (on) { subscribers[device.address] = device; NLog.i("ble", "subscriber joined ${NLog.l("in:" + device.address)}") } else removeSubscriber(device.address) }
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            main.post {
                notifying = false
                val out = notifyQueue.firstOrNull()
                if (out != null) {
                    if (status != BluetoothGatt.GATT_SUCCESS) { NLog.i("ble", "notify to ${NLog.l("in:" + out.addr)} failed, status $status"); notifyQueue.removeFirst(); out.done(false) } else out.frags.removeFirstOrNull()
                }
                pumpNotify()
            }
        }

        override fun onCharacteristicReadRequest(device: BluetoothDevice, requestId: Int, offset: Int, characteristic: BluetoothGattCharacteristic) {
            val data = identityBytes()
            val slice = if (offset <= data.size) data.copyOfRange(offset, data.size) else ByteArray(0)
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, slice)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (characteristic.uuid == MSG_CHAR && value != null) {
                if (preparedWrite) pendingWrites.getOrPut(device.address) { ByteArrayOutputStream() }.write(value)
                else main.post { onPacket?.invoke(value, "in:${device.address}") }
            }
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
        }

        override fun onExecuteWrite(device: BluetoothDevice, requestId: Int, execute: Boolean) {
            val buf = pendingWrites.remove(device.address)
            if (execute && buf != null) { val bytes = buf.toByteArray(); main.post { onPacket?.invoke(bytes, "in:${device.address}") } }
            server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }
    }
}
