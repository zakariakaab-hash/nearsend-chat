# Nearsend: implementation inventory and gap analysis

Written 18 November 2026 in answer to the "Master development prompt". Step one of that brief is to inspect what exists before
changing anything. Nothing was changed. **"Verified" below means tests or CI prove it. Nothing in Nearsend Chat has been tested on
two real phones yet, so no Bluetooth item can be called verified in the field.**

## Update 27 Nov 2026 (iOS)

The table below is the 18 Nov snapshot. Since then the **iPhone app** gained: photos and voice notes over Bluetooth with
write fragments (D/B improved), contacts by QR or pasted code (L: **I**), message requests from strangers, app lock,
an encrypted transfer file to move to a new phone, friend-nearby notifications, an honest signal-strength radar,
automatic battery saving and a WhatsApp-style settings page. It is uploaded to App Store Connect as version 1.0 build 10.
Texts have worked between two real iPhones; the rest still needs the real-phone test. Android has not changed and is now
behind iOS (no write-fragment reassembly, voice notes, contact codes or message requests). Current status lives in
`IOS_LAUNCH.md` and `NEARSEND_CHAT.md`.

## 1. What exists today (three separate pieces)

| Piece | Where | Stack | State |
|---|---|---|---|
| **Nearsend web app and website** (nearsend.app) | `Desktop\git\Nearsend`, GitHub `zakariakaab-hash/Nearsend`, live on Render | React 19, Vite, TypeScript, Express, WebSocket signaling, WebRTC data channels, Redis (optional), WebAuthn admin | Live. Files go browser to browser; the server only relays pairing and signaling. 18 languages, about 40 SEO pages, 47 blog posts |
| **Nearsend Chat, Android** | `offline chat app\nearsend-chat\NearsendChatAndroid` (branch `ios-app`) | Kotlin, Jetpack Compose, BLE GATT, Tink crypto, OkHttp (Nostr relays) | Feature-rich, 28 unit tests, runs on an emulator and a tablet |
| **Nearsend Chat, iOS** | `offline chat app\nearsend-chat\NearsendChatiOS` | Swift, SwiftUI, Core Bluetooth, CryptoKit | Ported from Android, compiles in CI, simulator screenshots only |
| Supporting | `nearsend-pc-peer` (Python test peer), `mesh-chat-audit` (audit of upstream Bitchat), `airhop-upstream`, previews | Python, notes | Reference material |

The chat apps are a fork of Bitchat, so they are **GPL-3.0**. They use their own protocol (`PROTOCOL.md`), not Bitchat's.

**The brief assumes Flutter and one app. The reality is two native apps (Kotlin, Swift) plus a web app.** The brief's own rule applies:
"If a working native or Flutter application already exists, extend it." So this plan does **not** introduce Flutter.

## 2. Requirements A to U

Legend: **V** verified by tests/CI · **I** implemented, needs improvement or real-device proof · **P** partial · **N** not implemented.

| # | Requirement | Web app | Chat Android | Chat iOS | Notes |
|---|---|---|---|---|---|
| A | Online file sharing | **V** (scripts: pairing, protocol, security; not run by me) | N | N | WebRTC, 64 KB chunks, no size cap, STUN only, no relay |
| B | Offline nearby file sharing | **N** | **P** (photos up to ~40 KB over BLE) | **P** | The web app needs the internet for signaling. "Local-Only Mode" only limits connection candidates |
| C | Folder sharing | **V** | N | N | |
| D | Offline 1:1 messaging | N | **I** | **I** | Sealed with X25519, HKDF, ChaCha20-Poly1305 |
| E | Offline group messaging | N | **I** | **I** | One sealed copy per member, no admin, no key change on leaving |
| F | Bluetooth LE discovery | N | **I** | **I** | GATT with notify characteristic, 5-hop flood. Tested only in a simulated network and on an emulator |
| G | Peer-to-peer Wi-Fi | N | **N** | **N** | Nothing built (no Wi-Fi Direct, Nearby Connections, Wi-Fi Aware, Multipeer, LAN) |
| H | Automatic multi-hop mesh | N | **I** | **I** | TTL 5 (brief says 7), duplicate cache 1500. No per-peer quotas, no spam control |
| I | Store-and-forward | N | **I** | **I** | 200 packets, 24 h, memory only (lost on app restart), no inventory exchange, no priorities |
| J | Internet messaging | N (no messaging) | **P** (optional Nostr relays, 1:1 only) | **N** | Relay operators see IP, timing, size |
| K | Automatic connectivity selection | N | **N** (manual Internet switch) | N | |
| L | QR user discovery | **V** (pairing QR) | **I** (contact QR with verification code) | **I** | Different formats: web token vs chat key card |
| M | QR event joining | **P** (private rooms up to 5 devices, invite QR) | N | N | Not usable for festivals as built |
| N | Optional user accounts | **P** (admin passkey only) | N | N | Conflicts with "no account" unless it is optional and separate |
| O | Anonymous identity | **V** (random id, device secret) | **I** | **I** | Random id, nickname, key; emoji picture |
| P | End-to-end encryption | **V** (DTLS) | **I** | **I** | No forward secrecy; **not audited**; relays cannot read (tested) |
| Q | Emergency SOS | N | **I** | **I** | Public, unencrypted, optional position. Does not call emergency services |
| R | Concert / festival rooms | P (rooms) | **P** (public Nearby channel, announcements) | **P** | No real rooms, moderation or QR join |
| S | Location sharing | N | **P** (SOS position, map link in chat) | **P** | No live sharing |
| T | Message synchronisation | N | **N** | **N** | Each phone is its own island |
| U | Android to iOS | n/a | **I** | **I** | Same JSON protocol and shared crypto test vector; **never tried on real devices** |

## 3. The four connectivity modes (Online, Nearby, Nearby Chat, No Wi-Fi)

I searched the web app source and found **no code or UI for these four modes**. The only matching idea is **Local-Only Mode**
(connection candidates limited to the local network) and a blog post about using a hotspot. If the four modes exist in a design
file or on the live site, I need that reference before I "preserve" it.

What each mode would map to today:

| Mode | What exists | Gap |
|---|---|---|
| 1 Online | Web file sharing; Android's optional Internet switch | iOS none; no automatic choice |
| 2 Nearby | Web "nearby devices" = devices on the **same public IP**, not radio proximity | A real radio-based Nearby needs the native apps |
| 3 Nearby Chat | **This is Nearsend Chat** | Needs the mode shell around it |
| 4 No Wi-Fi | Chat works over Bluetooth with no internet and no router | Web app cannot. No fast transfer without a router |

The wording rule in the brief is right and matters: "no Wi-Fi" must mean **no internet and no router**, not "Wi-Fi radio off".

## 4. Transports and engine (section 6 of the brief)

| Brief component | Today |
|---|---|
| TransportManager | **Missing.** The routers take a `transmit` callback and link ids (transport independent at that level). Bluetooth is wired in directly; the internet path is a separate hook |
| BluetoothTransport | Android `BleTransport`, iOS `BLETransport`. Works in simulation only |
| WifiPeerTransport | **None** |
| InternetTransport | Android only: Nostr relays (4 public servers) |
| MessageManager, MeshManager, DeliveryManager | `ChatStore` and `MeshRouter` (both platforms) |
| EncryptionManager, IdentityManager | `MeshCrypto`, `KeyStore` |
| FileTransferManager | Photos only (chunked over BLE, 60 KB max) |
| SynchronizationManager | None |
| LocalDatabase | One JSON file (`chat.json`), not SQLite/Drift |

## 5. Tests that exist

- Android: 28 JUnit tests (crypto vectors, framing, relay networks, store-and-forward, photos, avatars). Pass in CI.
- iOS: Swift protocol checks in CI (same scenarios), simulator build, unsigned `.ipa`.
- Web: five scripts (pairing, protocol, security, store, signaling security) that need a running server; CI runs lint, build and some.
- **None** on real devices. No battery or throughput measurements.

## 6. Risks to settle before building more

1. **Never verified on real hardware.** Everything in section 2 marked **I** is simulation-proven only. This blocks every claim about Bluetooth, mesh, interoperability and battery.
2. **Security.** Not audited, no forward secrecy, public SOS and channel are spoofable, relay operators see metadata. The brief's "emergency / disaster" use raises the bar: do not market it for that before a review.
3. **Bluetooth is slow.** The brief says so too. Real files and folders need a second transport (next section).
4. **Cross-platform Wi-Fi is the hard part.** Android Nearby Connections and Apple Multipeer do **not** talk to each other. Wi-Fi Aware is the only standard that can (iOS 26 and newer on supported iPhones, Android 8 and newer on supported hardware). Hotspot/LAN works everywhere.
5. **Hop limit, expiry and quotas** in the brief (7 hops, 24 h, per-peer quotas, spam protection) differ from today (5 hops). They are cheap to change but need load testing.
6. **Two worlds, no bridge.** The web app and the native apps share a brand but no protocol. Merging them is a product decision, not just code.

## 7. Recommended plan (small steps, each ending in something testable)

0. **Prove it.** Two real phones (iPhone and Android tablet), a written device test plan, measure discovery time, range, delivery, battery. Fix what breaks. *Blocks everything else.*
1. **Harden the mesh.** Persist held packets to disk, hop limit 7 (configurable), inventory exchange (ids first, then missing packets), per-peer quotas, bounded queues, spam limits, battery-aware forwarding. Add a shared `docs/` protocol version field and a golden test suite both platforms run.
2. **Mode shell.** The four modes as a screen and a state, an automatic recommendation (internet reachable? hotspot or LAN? Bluetooth only?), and the honest "no internet, not no radio" wording.
3. **LAN transport (first fast transport).** Devices on the same hotspot or Wi-Fi find each other with Bonjour/NSD and move data over TCP or QUIC. Works across Android and iOS today, needs no internet. Use it for files, folders and big messages.
4. **Files and folders in the native apps** over the LAN transport, with BLE for small items. Reuse the web app's manifest and chunk format where practical, so web and native can talk later.
5. **Rooms and events.** QR event join, rooms with moderation, announcements per room.
6. **Wi-Fi Aware** as a second fast transport where both phones support it.
7. **Internet transport on iOS** (parity with Android), automatic selection, then optional accounts and cross-device sync.
8. **Independent security review** before any safety or emergency marketing.

## 8. What I need from you

1. The brief stops at section 6.3. Please send the rest (file transfer, identity, security, UI, roadmap) if it exists.
2. Where is the "four modes" concept (design file, page, notes)? I found only Local-Only Mode.
3. ~~One app or two?~~ **Decided 18 Nov 2026: the native apps stay separate from the web app.**
4. Confirm **native Kotlin/Swift, no Flutter rewrite** (my recommendation, because it already exists and works).
5. Do you want optional accounts at all? They conflict with "no account, no phone number" unless they are strictly optional and separate.
6. Two real phones and some time for step 0. Without it I can only simulate.
