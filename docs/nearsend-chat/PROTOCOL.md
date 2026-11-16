# Nearsend Chat protocol v2

Implemented identically by `NearsendChatiOS` (Swift) and `NearsendChatAndroid` (Kotlin). Both are tested against the
vectors below and against the same relay scenarios (`NearsendChatiOS/Tests/main.swift`,
`NearsendChatAndroid/app/src/test/.../ProtocolTest.kt`; both run in CI).
Not related to the Bitchat protocol.

## 1. Link layer (Bluetooth LE)

Every phone is both a **GATT server** (advertises the service) and a **GATT client** (scans, connects to everyone it finds). No pairing.

Discovery can be **one-sided**: for example an iPhone app in the background advertises its service UUID in the "overflow area",
which Android scan filters cannot see, so only the iPhone discovers the Android phone. A phone must therefore be able to answer over a
connection the *other* phone opened. There are two kinds of link, named by prefix:

- `out:<id>` — **we** connected to that phone's server. We send by *writing* to its packet characteristic and we receive what it *notifies*.
- `in:<id>` — **that phone** connected to *our* server and subscribed to our notify characteristic. We send by *notifying* it and receive what it writes.

A client first subscribes to the server's notify characteristic, then reads its identity, and only then counts the server as a neighbour.
Right after that it writes a `hi` packet (section 2), which is how the server learns who the subscriber is and can start sending to it.
A pair of phones that discovered each other has both an `out` and an `in` link to each other; sends use `out` and fall back to `in`,
and floods use **one link per neighbouring phone**.

| | UUID | Access |
|---|---|---|
| Service | `7A3C5E10-9D2B-4F6A-8C1E-4E4541525345` | advertised |
| Identity characteristic | `7A3C5E11-9D2B-4F6A-8C1E-4E4541525345` | read |
| Packet characteristic | `7A3C5E12-9D2B-4F6A-8C1E-4E4541525345` | write (with response) |
| Notify characteristic | `7A3C5E13-9D2B-4F6A-8C1E-4E4541525345` | notify (with the standard CCCD descriptor) |

Identity value (JSON): `{"id": "<device id>", "name": "<nickname>", "pk": "<base64 X25519 public key, 32 bytes>"}`.
A phone is a *neighbour* once its identity has been read. Signal strength (RSSI) of the link is polled every 2 s.
Packets are limited to 512 bytes (one ATT long write). Notifications carry at most MTU−3 bytes, so server→client packets are fragmented (below).

## 2. Packets

JSON object, optional fields omitted when absent.

| field | meaning |
|---|---|
| `v` | protocol version, `2` |
| `t` | `hi` (link hello, never forwarded: `ttl` 1, carries `n` and `pk`) · `ann` (announce) · `msg` (direct message) · `pub` (public channel) · `ack` (delivery receipt) · `vfy` (QR verification proof, section 4) · `gm` (group message, section 5) · `sos` / `sosx` (SOS alarm on / off, section 6) |
| `id` | unique packet id (for `msg`: the message id) |
| `src` | sender device id |
| `dst` | destination device id (`msg`, `ack`, `vfy`, `gm`); absent for broadcasts |
| `ttl` | remaining hops; the sender starts at **5** |
| `ts` | sender clock, ms since epoch (informational) |
| `n` | sender nickname |
| `pk` | `ann`: base64 public key |
| `ct` | `msg`: base64 sealed text · `vfy`: base64 sealed one-time code (section 4) · `gm`: base64 sealed group JSON (section 5) |
| `tx` | `pub`: plain text · `sos`: optional plain note |
| `ref` | `ack`: id of the acknowledged packet · `sos`/`sosx`: alarm id (the same on every repeat) |
| `loc` | `sos`: `"lat,lon,accuracyMetres"` (decimal degrees, WGS84) when the sender shares a position; absent otherwise |

Text is limited to **180 UTF-8 bytes** (cut on a character boundary).

### Notification fragments
Each notification is `[seq][index][count][chunk…]` (one byte each; `seq` increments per packet per subscriber; chunk size is
MTU−3−3, using the central's maximum update length on iOS and the negotiated MTU on Android). The receiver appends chunks while
`seq` is unchanged and `index` is the next expected one; a mismatch drops the packet; the last chunk (`index = count−1`) completes it.
At most 255 fragments. Shared test vector: the bytes `00 01 … 09` with `seq` 7 and 4-byte chunks give
`07 00 03 00010203`, `07 01 03 04050607`, `07 02 03 0809`.

## 3. Relaying

- Every phone sends an `ann` (ttl 5) to its neighbours when a neighbour connects and then every **8 s**.
- A receiver ignores packets it has seen (`id` cache of the last 1500) or that it sent itself.
- `hops = 6 - ttl` as received (a direct neighbour's packet arrives with ttl 5, so hops = 1).
- Otherwise it handles the packet and, if `ttl > 1`, forwards it with `ttl - 1` to all neighbours except the one it came from.
  Packets with a `dst` that is a direct neighbour go only to that neighbour.
- `ann` creates/refreshes a peer entry (name, key, hops). Relayed peers not heard from for **40 s** are dropped; direct
  neighbours are dropped when the link is lost. Reach is therefore at most **5 hops**.
- `msg` for me: decrypt, show, reply with an `ack`. `pub`: show. `ack` for me: mark the message delivered.
  `vfy` for me: handled as in section 4 (no `ack`). `gm` for me: section 5 (with `ack`). `sos`/`sosx`: section 6.
  `msg`, `ack`, `vfy` and `gm` for someone else are forwarded like any packet. Unknown types are ignored (not forwarded).
- Messages to a peer that is not currently known stay queued in the app and are sent when the peer appears (give up after 10 min).

## 4. Direct-message encryption

```
shared = X25519(my private key, peer public key)
key    = HKDF-SHA256(ikm = shared, salt = "nearsend-chat-v2", info = sorted([myId, peerId]).join("|"), 32 bytes)
sealed = nonce(12 random bytes) || ChaCha20-Poly1305(key, nonce, plaintext = UTF-8 text, aad = message id) || tag(16)
```
`ct` is `base64(sealed)`. The message id is authenticated, so a ciphertext cannot be replayed under another id.

**Fingerprint** = first 16 bytes of `SHA-256(public key)`, shown as 8 groups of 4 hex digits in two lines
(`AAA8 FFF7 03B5 0B22` / `97F4 F6E1 3508 F724`). People compare fingerprints in person and tap "Mark as verified",
or scan each other's QR code (below).

### QR verification (`vfy`)

The QR code is the JSON `{"nearsend":1,"id":<device id>,"n":<nickname>,"pk":<base64 public key>,"c":<one-time code>}`.
`c` is 8 random bytes as 16 hex digits, freshly made each time the QR is shown and kept in memory only (forgotten on restart).

1. **B scans A's QR.** B marks the fingerprint of the `pk` *from the QR* as verified (it saw it in person). If B already
   knows a different key for that id, B shows a warning instead.
2. B sends A a `vfy` packet: `dst` = A, `ct` = `base64(seal(c))` using the normal sealing above with **the key from the QR**
   and the `vfy` packet id as aad. If A is not reachable yet, B keeps it queued until A appears.
3. **A** opens it with the key it already knows for B (from `ann`/`hi`). A accepts only if it decrypts *and* `c` is one of
   the codes A itself showed; then A marks B's fingerprint as verified. One scan therefore verifies both directions.

A `vfy` sealed to any other key does not open at A and is dropped, so a relay or an impostor cannot fake it.

### Contact codes sent as text

"Share as text" sends the same JSON **without `c`**. Pasting it only adds an **unverified** contact (a name and id to
write to; encryption still uses the key learned over Bluetooth). Any `c` in pasted text is ignored, because text can be
forwarded and must never verify anyone.

### Test vector (generated with Python `cryptography`)

```
private key A  0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20
private key B  65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384
public key A   07a37cbc142093c8b755dc1b10e86cb426374ad16aa853ed0bdfc0b2b86d1c7c
public key B   5714769d116bf76436ae74bc793d2c30ad1903c59ac5273805c7e2698b410c36
ids            alice (A), bob (B)         message id (aad)  m-1
derived key    ed8ca2aba1397ffeb4c22c4c2eeb86de13003eb87640dc3749cdd1bc58b4d756
nonce          c8c9cacbcccdcecfd0d1d2d3
sealed         c8c9cacbcccdcecfd0d1d2d3b7f7d3789adc70b46a831626878bc5809086ac2253d1ba553d06af4445a5b4c525
plaintext      "Hej världen 👋"
fingerprint A  AAA8 FFF7 03B5 0B22 / 97F4 F6E1 3508 F724
```

## 5. Groups (`gm`)

A group is an id (`g:` + UUID), a name and a member list chosen by whoever created it. There is no group key: every group
message is **sealed separately for each member**, exactly like a direct message (section 4), and sent as its own `gm` packet:

- `dst` = the member, `id` = `<message id>.<member id>` (unique per copy; the aad), `ct` = `base64(seal(json))` where
  `json` = `{"g":<group id>,"gn":<group name>,"m":[{"id":<device id>,"n":<name>}, ...all members incl. sender],"tx":<text>}`.
- The receiver opens it with the sender's known key, creates the group if it is new (taking the name and member list from
  the message), shows the text under the sender's name and answers with a normal `ack` whose `ref` is the packet id.
- Replies go to every member in `m` except yourself. Copies for members out of range stay queued (10 min, like direct messages).
- Leaving a group is local: the phone forgets it and ignores later `gm` packets for that group id.

## 6. SOS (`sos`, `sosx`)

An SOS alarm is a **public, unencrypted broadcast**, flooded like `pub` (ttl 5) so it reaches every phone around, including
phones that are not contacts.

- `sos`: `ref` = alarm id (random, fixed for the whole alarm), optional `tx` note (clipped to 180 bytes), optional `loc`.
- While the alarm is on, the sender repeats `sos` every **15 s** with a fresh packet `id` (so it passes the id cache and
  reaches phones that arrive later) and the latest position.
- `sosx`: same `ref`, sent once when the sender taps "I'm safe". Receivers mark that alarm as ended.
- Receivers group repeats by (`src`, `ref`), notify only on the first packet of an alarm, and show distance and compass
  direction from their own position when both phones have one.

## 7. What this does **not** protect against (read before relying on it)

- **Not audited.** Custom protocol built from standard primitives; no third-party review.
- **Announcements are unauthenticated.** Anyone can claim any id/name/key. A person in the middle could substitute a key
  until the two people compare fingerprints in person. Unverified chats are encrypted but not authenticated.
- **No forward secrecy:** keys are long-lived; stealing a phone's key exposes recorded traffic to/from it.
- **Metadata is visible** to anyone in range and to relays: sender id/nickname, destination id, packet sizes and timing.
- **Public channel** messages are plain text and can be spoofed (no signatures).
- **QR codes can be photographed.** Someone who films your QR (with its one-time code) and gets their `vfy` to you before
  your friend does could be marked verified. Show the QR only to the person in front of you; codes die when the app restarts.
- No replay protection beyond the id cache; no rate limiting or spam control; relays can drop or delay packets.
- Bluetooth advertising reveals that a phone runs Nearsend Chat.
- **SOS alarms are public and unauthenticated.** Anyone nearby can read the note and position, and anyone can send a fake
  alarm under any name. The alarm only reaches phones within 5 hops; it does not contact emergency services.
- **Group membership is not authenticated.** Any member can send a member list; there is no admin. Members learn each
  other's device ids and names. Each copy is end-to-end encrypted, but a group of N people costs N packets per message.
