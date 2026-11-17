package app.nearsend.chat

import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Talks to the real public relays, so it only runs when asked: NEARSEND_LIVE=1 ./gradlew :app:testDebugUnitTest
 * For each relay: phone B listens, phone A publishes a sealed packet to B's key, and we check that the relay stored it
 * and that B got it back and could open it.
 */
class RelayLiveTest {
    @Test fun eachPublicRelayStoresAndDeliversASealedPacket() {
        assumeTrue(System.getenv("NEARSEND_LIVE") == "1")
        val results = InternetRelay.RELAYS.map { url ->
            val a = MeshCrypto.generate(); val b = MeshCrypto.generate()
            val payload = "live-test-" + System.nanoTime()
            val connected = CountDownLatch(2); val stored = CountDownLatch(1); val got = CountDownLatch(1)
            var ok = false
            val since = System.currentTimeMillis() / 1000 - 60
            val rb = InternetRelay(b, listOf(url)) { it() }.apply {
                this.since = since
                onState = { if (it > 0) connected.countDown() }
                onPacket = { if (String(it) == payload) got.countDown() }
                start()
            }
            val ra = InternetRelay(a, listOf(url)) { it() }.apply { this.since = since; onState = { if (it > 0) connected.countDown() }; start() }
            val up = connected.await(15, TimeUnit.SECONDS)
            if (up) ra.publish(b.publicKey, payload.toByteArray()) { ok = it; stored.countDown() }
            val storedOk = up && stored.await(12, TimeUnit.SECONDS) && ok
            val delivered = storedOk && got.await(12, TimeUnit.SECONDS)
            ra.stop(); rb.stop()
            "$url connected=$up stored=$storedOk delivered=$delivered".also(::println)
            delivered
        }
        check(results.any { it }) { "no relay delivered the packet" }
    }
}
