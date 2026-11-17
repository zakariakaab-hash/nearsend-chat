package app.nearsend.chat

import org.junit.Assert.*
import org.junit.Test

/** Mirrors NearsendChatiOS/Tests/main.swift: same vectors, same relay scenarios. */
class ProtocolTest {
    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    private fun toHex(b: ByteArray) = b.joinToString("") { "%02x".format(it) }

    private val skA = hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
    private val skB = hex("65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384")
    private val combined = hex("c8c9cacbcccdcecfd0d1d2d3b7f7d3789adc70b46a831626878bc5809086ac2253d1ba553d06af4445a5b4c525")

    @Test fun cryptoMatchesPythonVector() {
        val a = MeshCrypto(skA); val b = MeshCrypto(skB)
        assertEquals("07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c", toHex(a.publicKey))
        assertEquals("Hej världen 👋", b.open(combined, a.publicKey, "bob", "alice", "m-1"))
        assertEquals("Hej världen 👋", a.open(combined, b.publicKey, "alice", "bob", "m-1"))
        assertEquals("AAA8 FFF7 03B5 0B22\n97F4 F6E1 3508 F724", a.fingerprint)
    }

    @Test fun cryptoRejectsTamperingAndWrongContext() {
        val a = MeshCrypto(skA); val b = MeshCrypto(skB)
        assertThrows(Exception::class.java) { b.open(combined, a.publicKey, "bob", "alice", "other") }
        val t = combined.copyOf(); t[20] = (t[20].toInt() xor 1).toByte()
        assertThrows(Exception::class.java) { b.open(t, a.publicKey, "bob", "alice", "m-1") }
    }

    @Test fun sealThenOpenRoundTrips() {
        val a = MeshCrypto.generate(); val b = MeshCrypto.generate()
        val ct = a.seal("hej", b.publicKey, "a", "b", "id")
        assertEquals("hej", b.open(ct, a.publicKey, "b", "a", "id"))
    }

    @Test fun clipsToUtf8Bytes() {
        assertTrue(MeshRouter.clip("å".repeat(200)).toByteArray().size <= 180)
        assertEquals("hej", MeshRouter.clip("hej"))
    }

    // ---- notification framing (must match the Swift implementation byte for byte)

    @Test fun framingMatchesSharedVector() {
        val data = ByteArray(10) { it.toByte() }
        val frags = Framing.fragments(data, 7, 4)
        assertEquals(listOf("07000300010203", "07010304050607", "07020308" + "09"), frags.map { toHex(it) })
        val r = Reassembler(); var out: ByteArray? = null
        frags.forEach { out = r.add(it) }
        assertArrayEquals(data, out)
        val r2 = Reassembler()
        assertNull(r2.add(frags[1])); assertNull(r2.add(frags[0])); assertNull(r2.add(frags[1]))
        assertArrayEquals(data, r2.add(frags[2]))
        assertTrue(Framing.fragments(ByteArray(300), 0, 1).isEmpty())
    }

    // ---- simulated networks. Link ids follow the app: "out:<peer>" = we connected to that peer (we can write to it),
    //      "in:<peer>" = that peer connected to us (we answer with notifications).

    private class Node(val id: String, net: Net) {
        val crypto = MeshCrypto.generate()
        val router = MeshRouter(id, id, crypto)
        val texts = mutableListOf<Triple<String, String, Int>>(); val pubs = mutableListOf<String>(); val delivered = mutableListOf<String>()
        var peers = listOf<Peer>()
        init {
            router.transmit = { link, data, done -> net.deliver(id, link, data); done(true) }
            router.onPeers = { peers = it }
            router.onText = { f, _, t, h, _ -> texts += Triple(f, t, h) }
            router.onPublic = { _, _, t, _ -> pubs += t }
            router.onDelivered = { delivered += it }
        }
    }

    private class Net {
        val nodes = LinkedHashMap<String, Node>()
        var transmits = 0
        fun add(id: String) = Node(id, this).also { nodes[id] = it }
        fun deliver(from: String, link: String, data: ByteArray) {
            transmits++
            when {
                link.startsWith("out:") -> nodes[link.removePrefix("out:")]?.router?.receive(data, "in:$from")
                link.startsWith("in:") -> nodes[link.removePrefix("in:")]?.router?.receive(data, "out:$from")
            }
        }
        /** x discovered y and connected to it; y never discovered x (it only learns of x from x's hello). */
        fun connectOneWay(x: String, y: String) = nodes[x]!!.router.neighborConnected("out:$y", y, y, nodes[y]!!.crypto.publicKey)
        /** Both discovered each other: each has an out link and an in link to the other. */
        fun connect(x: String, y: String) { connectOneWay(x, y); connectOneWay(y, x) }
        fun settle() { repeat(3) { nodes.values.forEach { it.router.tick() } } }
    }

    @Test fun qrVerifyOnlyOpensWithTheRightKey() {
        val net = Net(); val n = listOf("A", "B", "C").map { net.add(it) }
        val got = mutableListOf<Pair<String, String>>()
        n[2].router.onVerify = { f, fp, code -> assertEquals(MeshCrypto.fingerprint(n[0].crypto.publicKey), fp); got += f to code }
        net.connect("A", "B"); net.connect("B", "C"); net.settle()
        n[0].router.sendVerify("c0de", "C", n[2].crypto.publicKey) { }
        assertEquals(listOf("A" to "c0de"), got)
        n[0].router.sendVerify("bad", "C", n[1].crypto.publicKey) { }   // sealed to the wrong key: C cannot open it
        assertEquals(1, got.size)
    }

    @Test fun lineOfFourDeliversEncryptedAcrossThreeHops() {
        val net = Net(); val n = listOf("A", "B", "C", "D").map { net.add(it) }
        net.connect("A", "B"); net.connect("B", "C"); net.connect("C", "D"); net.settle()
        assertEquals(3, n[0].peers.first { it.id == "D" }.hops)
        var outcome: SendOutcome? = null
        n[0].router.sendText("hello D", "D", "id-1") { outcome = it }
        assertEquals(SendOutcome.Sent, outcome)
        assertEquals(listOf(Triple("A", "hello D", 3)), n[3].texts)
        assertEquals(listOf("id-1"), n[0].delivered)
        assertTrue(n[1].texts.isEmpty() && n[2].texts.isEmpty())
        n[0].router.sendPublic("hi all", "pub-1") { }
        assertEquals(listOf("hi all"), n[1].pubs); assertEquals(listOf("hi all"), n[3].pubs)
    }

    @Test fun oneDirectionalDiscoveryStillWorksBothWays() {
        val net = Net(); val n = listOf("A", "B").map { net.add(it) }
        net.connectOneWay("A", "B"); net.settle()          // B never discovered A
        assertEquals(listOf("A"), n[1].peers.map { it.id })
        var o1: SendOutcome? = null; var o2: SendOutcome? = null
        n[0].router.sendText("A to B", "B", "ab") { o1 = it }
        n[1].router.sendText("B to A", "A", "ba") { o2 = it }
        assertEquals(SendOutcome.Sent, o1); assertEquals(SendOutcome.Sent, o2)
        assertEquals(listOf("A to B"), n[1].texts.map { it.second }); assertEquals(listOf("B to A"), n[0].texts.map { it.second })
        assertEquals(listOf("ab"), n[0].delivered); assertEquals(listOf("ba"), n[1].delivered)
    }

    @Test fun relayWorksOverInLinksOnly() {
        val net = Net(); val n = listOf("A", "B", "C").map { net.add(it) }
        net.connectOneWay("A", "B"); net.connectOneWay("C", "B"); net.settle()   // B discovered nobody
        assertEquals(2, n[0].peers.first { it.id == "C" }.hops)
        n[0].router.sendText("via B", "C", "acx") { }
        assertEquals(listOf("via B"), n[2].texts.map { it.second }); assertEquals(listOf("acx"), n[0].delivered)
        n[2].router.sendPublic("from C", "pc") { }
        assertEquals(listOf("from C"), n[0].pubs); assertEquals(listOf("from C"), n[1].pubs)
    }

    @Test fun ttlLimitsReachToFiveHops() {
        val net = Net(); val ids = (0 until 8).map { "N$it" }; val n = ids.map { net.add(it) }
        for (i in 0 until 7) net.connect(ids[i], ids[i + 1]); net.settle()
        assertEquals(setOf("N1", "N2", "N3", "N4", "N5"), n[0].peers.map { it.id }.toSet())
        var outcome: SendOutcome? = null
        n[0].router.sendText("far", "N7", "id-far") { outcome = it }
        assertEquals(SendOutcome.Unreachable, outcome)
    }

    @Test fun loopsDoNotDuplicateAndUseOneLinkPerNeighbour() {
        val net = Net(); val n = listOf("A", "B", "C").map { net.add(it) }
        net.connect("A", "B"); net.connect("B", "C"); net.connect("C", "A"); net.settle()
        net.transmits = 0
        n[0].router.sendText("once", "C", "id-tri") { }
        n[0].router.sendPublic("loop", "pub-tri") { }
        assertEquals(1, n[2].texts.size)
        assertEquals(1, n[1].pubs.size); assertEquals(1, n[2].pubs.size)
        assertTrue("transmissions: ${net.transmits}", net.transmits <= 6)
    }

    @Test fun peersExpireAndNeighboursDropWhenAllLinksAreLost() {
        val net = Net(); val n = listOf("A", "B", "C").map { net.add(it) }
        net.connect("A", "B"); net.connect("B", "C"); net.settle()
        assertEquals(2, n[0].peers.size)
        var t = System.currentTimeMillis(); n[0].router.now = { t }; t += 60_000; n[0].router.tick()
        assertEquals(listOf("B"), n[0].peers.map { it.id })
        n[0].router.neighborLost("out:B")
        assertEquals(listOf("B"), n[0].peers.map { it.id })     // its in link is still alive
        n[0].router.neighborLost("in:B")
        assertTrue(n[0].peers.isEmpty())
    }

    @Test fun sosFloodsWithLocationAndEnds() {
        val net = Net(); val n = listOf("A", "B", "C").map { net.add(it) }
        val got = mutableListOf<String>(); val ended = mutableListOf<String>()
        n[2].router.onSos = { f, _, alarm, note, loc, hops -> got += "$f|$alarm|$note|$loc|$hops" }
        n[1].router.onSos = { _, _, _, _, _, _ -> got += "B" }
        n[2].router.onSosEnd = { f, alarm -> ended += "$f|$alarm" }
        net.connect("A", "B"); net.connect("B", "C"); net.settle()
        n[0].router.sendSos("al-1", "hurt leg", "59.3293,18.0686,8")
        n[0].router.sendSos("al-1", "hurt leg", "59.3293,18.0686,8")   // a repeat: new packet id, same alarm id
        assertEquals(listOf("B", "A|al-1|hurt leg|59.3293,18.0686,8|2", "B", "A|al-1|hurt leg|59.3293,18.0686,8|2"), got)
        n[0].router.sendSos("al-1", null, null, end = true)
        assertEquals(listOf("A|al-1"), ended)
        val p = Packet.parse(Packet("sos", "x", "A", null, 5, 1, n = "A", ref = "al-1", loc = "1,2,3").toBytes())!!
        assertEquals("1,2,3", p.loc); assertEquals("al-1", p.ref)
    }

    @Test fun groupMessageReachesEachMemberSealedAndAcked() {
        val net = Net(); val n = listOf("A", "B", "C", "D").map { net.add(it) }
        val got = mutableMapOf<String, String>()
        for (x in n) x.router.onGroup = { f, _, g, gn, m, t, _, id -> got[x.id] = "$f|$g|$gn|${m.joinToString(",") { it.first }}|$t|$id" }
        net.connect("A", "B"); net.connect("B", "C"); net.connect("C", "D"); net.settle()
        val members = listOf("A" to "A", "B" to "B", "D" to "D")
        for (dst in listOf("B", "D")) n[0].router.sendGroup("hej gruppen", "g:1", "Trip", members, dst, "m1") { assertEquals(SendOutcome.Sent, it) }
        assertEquals("A|g:1|Trip|A,B,D|hej gruppen|m1", got["B"]); assertEquals("A|g:1|Trip|A,B,D|hej gruppen|m1", got["D"])
        assertNull(got["C"])                                            // C relayed D's copy but could not open it
        assertEquals(setOf("m1.B", "m1.D"), n[0].delivered.toSet())     // one ack per member copy
    }

    @Test fun messageForSomeoneAwayIsCarriedAndDeliveredLater() {
        val net = Net(); val (a, b, c) = listOf("A", "B", "C").map { net.add(it) }
        // A and C met before (C is a saved contact of A, and A of C); C is away now.
        a.router.savedKey = { if (it == "C") c.crypto.publicKey else null }
        c.router.savedKey = { if (it == "A") a.crypto.publicKey else null }
        net.connect("A", "B"); net.settle()
        var outcome: SendOutcome? = null
        a.router.sendText("see you later", "C", "sf-1") { outcome = it }
        assertEquals(SendOutcome.Carried, outcome)
        assertTrue(c.texts.isEmpty())
        net.connect("B", "C")                                  // B walks over to C
        assertEquals(listOf("see you later"), c.texts.map { it.second })
        assertEquals(listOf("sf-1"), a.delivered)              // C's ack travelled back through B
        var none: SendOutcome? = null
        Net().add("X").router.sendText("hi", "nobody", "x-1") { none = it }
        assertEquals(SendOutcome.Unreachable, none)            // no key: nothing to carry
    }

    @Test fun heldMessageLeavesWithTheSenderWhenNobodyIsAround() {
        val net = Net(); val (a, b) = listOf("A", "B").map { net.add(it) }
        a.router.savedKey = { if (it == "B") b.crypto.publicKey else null }
        b.router.savedKey = { if (it == "A") a.crypto.publicKey else null }
        var outcome: SendOutcome? = null
        a.router.sendText("waiting", "B", "h-1") { outcome = it }
        assertEquals(SendOutcome.Held, outcome)
        net.connect("A", "B")
        assertEquals(listOf("waiting"), b.texts.map { it.second })
        assertEquals(listOf("h-1"), a.delivered)
    }

    @Test fun announcementsReachLateArrivalsAndExpire() {
        val net = Net(); val (a, b, c) = listOf("A", "B", "C").map { net.add(it) }
        val got = mutableMapOf<String, MutableList<String>>()
        listOf(a, b, c).forEach { n -> n.router.onPost = { _, _, _, text, _, _ -> got.getOrPut(n.id) { mutableListOf() } += text } }
        net.connect("A", "B"); net.settle()
        var t = System.currentTimeMillis(); listOf(a, b, c).forEach { n -> n.router.now = { t } }
        a.router.sendPost("Lost dog near gate 3", "post-1", t + 3_600_000)
        assertEquals(listOf("Lost dog near gate 3"), got["B"])
        net.connect("B", "C")                                  // C arrives later and is shown it once
        assertEquals(listOf("Lost dog near gate 3"), got["C"])
        net.connect("C", "A")
        assertEquals(1, got["C"]!!.size)
        t += 2 * 3_600_000; b.router.tick()
        val d = net.add("D"); d.router.onPost = { _, _, _, text, _, _ -> got.getOrPut("D") { mutableListOf() } += text }
        net.connect("B", "D")
        assertTrue(got["D"] == null)                           // expired posts are not shared
    }

    @Test fun relayOffNeitherForwardsNorCarries() {
        val net = Net(); val (a, b, c) = listOf("A", "B", "C").map { net.add(it) }
        b.router.relay = false
        net.connect("A", "B"); net.connect("B", "C"); net.settle()
        assertTrue(a.peers.none { it.id == "C" })
        a.router.sendPublic("anyone?", "p-1") { }
        assertEquals(listOf("anyone?"), b.pubs)
        assertTrue(c.pubs.isEmpty())
    }

    @Test fun relayedPeersKnowWhichNeighbourTheyCameThrough() {
        val net = Net(); val n = listOf("A", "B", "C").map { net.add(it) }
        net.connect("A", "B"); net.connect("B", "C"); net.settle()
        assertEquals("B", n[0].peers.first { it.id == "C" }.via)
        assertEquals(null, n[0].peers.first { it.id == "B" }.via)
    }

    // ---- internet relays (PROTOCOL.md section 9)

    @Test fun schnorrMatchesBip340Vectors() {
        val sk = hex("0000000000000000000000000000000000000000000000000000000000000003")
        assertEquals("f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9", toHex(Schnorr.publicKey(sk)))
        assertEquals("e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215" +
            "25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0", toHex(Schnorr.sign(sk, ByteArray(32), ByteArray(32))))
        val sk1 = hex("b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef")
        assertEquals("dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659", toHex(Schnorr.publicKey(sk1)))
        assertEquals("6896bd60eeae296db48a229ff71dfe071bde413e6d43f917dc8dcf8c78de3341" +
            "8906d11ac976abccb20b091292bff4ea897efcb639ea871cfa95f6de339e4b0a",
            toHex(Schnorr.sign(sk1, hex("243f6a8885a308d313198a2e03707344a4093822299f31d0082efa98ec4e6c89"),
                hex("0000000000000000000000000000000000000000000000000000000000000001"))))
    }

    @Test fun relayEventIdIsTheHashOfItsCanonicalForm() {
        val ev = RelayEvent.build("ab", "QUJD", 1_700_000_000, hex("0000000000000000000000000000000000000000000000000000000000000003"))
        val canon = """[0,"f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",1700000000,4243,[["t","ab"],["expiration","1700086400"]],"QUJD"]"""
        assertEquals(toHex(java.security.MessageDigest.getInstance("SHA-256").digest(canon.toByteArray())), ev.id)
        val o = org.json.JSONObject(ev.json)
        assertEquals(ev.id, o.getString("id")); assertEquals(128, o.getString("sig").length); assertEquals("QUJD", o.getString("content"))
    }

    @Test fun internetEnvelopeOnlyOpensForItsOwner() {
        val a = MeshCrypto.generate(); val b = MeshCrypto.generate()
        val topic = MeshCrypto.inetTopic(b.publicKey)
        assertEquals(64, topic.length); assertNotEquals(topic, MeshCrypto.inetTopic(a.publicKey))
        val blob = MeshCrypto.sealTo(b.publicKey, "packet".toByteArray(), topic.toByteArray())
        assertEquals("packet", String(b.openSealed(blob, topic.toByteArray())!!))
        assertNull(a.openSealed(blob, topic.toByteArray()))            // someone else's key
        assertNull(b.openSealed(blob, "other".toByteArray()))          // moved to another topic
        assertNull(b.openSealed(blob.copyOf().also { it[40] = (it[40] + 1).toByte() }, topic.toByteArray()))
        assertNull(b.openSealed(ByteArray(10), topic.toByteArray()))   // junk
    }

    /** A stand-in for the relays: what one phone seals to a key is opened by that key's phone and given to its router. */
    private fun wire(from: Node, to: Node) {
        from.router.uplink = { pk, data, done ->
            val topic = MeshCrypto.inetTopic(pk).toByteArray()
            to.crypto.openSealed(MeshCrypto.sealTo(pk, data, topic), topic)?.let { to.router.receiveUplink(it) }
            done(true)
        }
    }

    @Test fun internetCarriesPrivatePacketsBetweenContacts() {
        val net = Net(); val (a, b) = listOf("A", "B").map { net.add(it) }
        a.router.savedKey = { if (it == "B") b.crypto.publicKey else null }
        b.router.savedKey = { if (it == "A") a.crypto.publicKey else null }
        var first: SendOutcome? = null
        a.router.sendText("before the internet", "B", "in-0") { first = it }
        assertEquals(SendOutcome.Held, first)                              // no Bluetooth neighbour, no internet yet
        wire(a, b); wire(b, a)
        val carried = mutableListOf<String>()
        a.router.uplinkHeld { carried += it }                               // the internet comes up: waiting packets go out
        assertEquals(listOf("in-0"), carried)
        var outcome: SendOutcome? = null
        a.router.sendText("over the internet", "B", "in-1") { outcome = it }
        assertEquals(SendOutcome.Carried, outcome)
        assertEquals(listOf("before the internet", "over the internet"), b.texts.map { it.second })
        assertEquals(listOf("in-0", "in-1"), a.delivered)                   // B's receipts came back the same way
    }

    @Test fun internetOnlyAcceptsPrivatePacketsForMe() {
        val net = Net(); val (a, b, c) = listOf("A", "B", "C").map { net.add(it) }
        net.connect("B", "C")
        val before = net.transmits
        b.router.receiveUplink(Packet("pub", "x-1", "A", null, 5, 0, n = "A", tx = "spam").toBytes())
        b.router.receiveUplink(Packet("ann", "x-2", "A", null, 5, 0, n = "A", pk = java.util.Base64.getEncoder().encodeToString(a.crypto.publicKey)).toBytes())
        b.router.receiveUplink(Packet("msg", "x-3", "A", "C", 5, 0, n = "A", ct = "AAAA").toBytes())
        assertTrue(b.pubs.isEmpty()); assertTrue(c.pubs.isEmpty())
        assertTrue(b.peers.none { it.id == "A" })                           // nobody appears "nearby" from the internet
        assertEquals(before, net.transmits)                                 // and nothing is passed on into the mesh
    }

    @Test fun pictureTravelsWithAnnouncementsAndOnlyOurEmojisAreAccepted() {
        val net = Net(); val (a, b, c) = listOf("A", "B", "C").map { net.add(it) }
        val fox = Avatars.encode(Avatars.EMOJIS[6], 3)
        a.router.myAvatar = fox
        net.connect("A", "B"); net.connect("B", "C"); net.settle()
        assertEquals(fox, b.peers.first { it.id == "A" }.avatar)          // direct neighbour
        assertEquals(fox, c.peers.first { it.id == "A" }.avatar)          // two hops, carried by the announcement
        a.router.myAvatar = "evil text|1"; net.settle()
        assertNull(b.peers.first { it.id == "A" }.avatar)                 // not one of our emojis: ignored
        a.router.myAvatar = Avatars.EMOJIS[0] + "|99"; net.settle()
        assertNull(b.peers.first { it.id == "A" }.avatar)                 // unknown colour: ignored
        a.router.myAvatar = null; net.settle()
        assertNull(c.peers.first { it.id == "A" }.avatar)
        assertNull(Avatars.valid(null)); assertNull(Avatars.valid("|1")); assertNull(Avatars.valid(Avatars.EMOJIS[0]))
        assertEquals(fox, Avatars.valid(fox))
    }

    @Test fun packetsInteroperateWithIosJson() {
        // A packet exactly as the iOS JSONEncoder writes it (keys in a different order, optional fields absent).
        val json = """{"ts":1700000000000,"ttl":4,"t":"pub","src":"IOS-1","v":2,"id":"p-1","tx":"hej","n":"Ios"}"""
        val p = Packet.parse(json.toByteArray())!!
        assertEquals("pub", p.t); assertEquals("hej", p.tx); assertNull(p.dst); assertEquals(4, p.ttl)
    }
}
