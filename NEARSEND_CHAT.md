# Nearsend Chat

Repository: https://github.com/zakariakaab-hash/nearsend-chat (formerly `bitchat`; the old address redirects). Work lives on the `ios-app` branch.

Offline, nearby chat for iPhone and Android over Bluetooth LE. No internet, no account, no phone number.
Belongs to the [nearsend.app](https://nearsend.app) family and shares its "Open Sky" design.

> **Status (27 Nov 2026):** the iPhone app is in App Store Connect as version 1.0, **build 10**, not yet submitted for review
> (`docs/nearsend-chat/IOS_LAUNCH.md`). Texts have worked between two real iPhones on TestFlight; photos, voice notes and the
> build 10 Bluetooth fixes still need a real-phone test (`REAL_PHONE_TEST_PLAN.md`). The protocol tests pass (iOS 77 checks,
> Android 9 tests, including a message encrypted by Python that both apps decrypt). Not security audited
> (`PROTOCOL.md` section 7). Not compatible with the Bitchat protocol. This repository is a fork of Bitchat (GPL-3.0), so this
> work is GPL-3.0 too. The Android app is behind the iPhone app (see "Known limitations").

## Features (both apps)

- Bluetooth discovery between phones, animated radar with signal strength.
- **End-to-end encrypted direct messages** (X25519 + HKDF + ChaCha20-Poly1305), real **fingerprints**, "mark as verified".
- **Multi-hop relay** (up to 5 hops), delivery receipts, **public "Nearby channel"** (unencrypted, clearly labelled).
- Messages are **saved on the phone**; messages to people out of range are **queued and sent when they appear**; failed messages can be retried.
- Local **notifications** and haptics; iOS **state restoration** for background Bluetooth; on Android a **foreground service** keeps Bluetooth running when the app is closed (switchable in the You tab). **Erase everything** (button or triple-tap the title) wipes messages, keys and identity.
- **12 languages** that follow the phone's language, plus an in-app language picker (You tab): English, Svenska, Español, Français, Deutsch, Português, Italiano, العربية (right-to-left), Türkçe, Русский, 简体中文, 日本語.
- Light/dark "Open Sky" design from nearsend.app, app icons, Reduce Motion and screen-reader labels.

### iPhone only (build 10)

- **Photos and voice notes** to a contact in range (photos about 14 KB, voice 12 kbit/s, up to 12 s), with retries until delivered.
- **Add contacts by QR or a pasted code**; **message requests** from strangers (Ask me / Allow / Block) and **Hide me from strangers**.
- **SOS** with optional position and the local emergency number; active alarms shown first. **Announcements**, **groups**.
- **App lock** (Face ID / passcode), **Move to another phone** (password-encrypted transfer file), **Invite a friend** (App Store QR).
- **Notify me when a friend is nearby**; **Battery saver** and automatic battery saving at 20 %.
- Honest **radar** (rings by signal strength, never direction), plain proximity labels, an animated guide for turning Bluetooth on.
- WhatsApp-style You page: Privacy, Notifications, Bluetooth, Language, Move to another phone, Invite a friend, Help.

Docs: [`PROTOCOL.md`](docs/nearsend-chat/PROTOCOL.md) · [`PRIVACY.md`](docs/nearsend-chat/PRIVACY.md) · [`RELEASING.md`](docs/nearsend-chat/RELEASING.md) ·
[`IOS_LAUNCH.md`](docs/nearsend-chat/IOS_LAUNCH.md) · [`AUDIT_2026-11-26.md`](docs/nearsend-chat/AUDIT_2026-11-26.md) ·
[`PRODUCT_VISION_REPORT_2026-11-26.md`](docs/nearsend-chat/PRODUCT_VISION_REPORT_2026-11-26.md)

## What's in this repo

| Path | What |
|---|---|
| `NearsendChatiOS/` | iOS app (SwiftUI, iOS 17+, CoreBluetooth) |
| `NearsendChatAndroid/` | Android app (Kotlin, Jetpack Compose, minSdk 26, Android BLE) |
| `.github/workflows/nearsend-chat-ios.yml` | Builds iOS on a macOS runner, screenshots simulator, commits Xcode project + previews |
| `.github/workflows/nearsend-chat-android.yml` | Builds the APK, screenshots an emulator, commits Gradle wrapper + font + previews |
| `i18n/` | One translation table (`translations.txt`) → generates iOS `*.lproj` and Android `values-*` strings (`python3 i18n/generate.py`) |
| `docs/nearsend-chat/` | Protocol spec, privacy policy, release guide |
| `*/previews/` | CI screenshots (day, night, several languages) |

The rest of the repository is the unmodified upstream Bitchat iOS app.
Work lives on the `ios-app` branch.

## Screens (same on both platforms)

Onboarding (4 pages, ending with your name) → **Nearby** (radar by signal strength + people list) → **Chats** → **Thread** →
**SOS** → **You** (profile, My code, settings rows).
Light ("day sky") and dark ("night sky") themes follow the device setting.

## Run it

**iOS** (Xcode 15+, macOS)
```
git clone -b ios-app https://github.com/zakariakaab-hash/nearsend-chat
cd nearsend-chat/NearsendChatiOS
./run-on-mac.sh            # builds, launches in an iPhone simulator, opens Xcode
```
Or open `NearsendChatiOS/NearsendChat.xcodeproj` and press Run. For a real iPhone choose your Apple ID under
Signing & Capabilities. The project is regenerated from `project.yml` with XcodeGen (`xcodegen generate`).

**Android** (Android Studio, JDK 17)
Open the `NearsendChatAndroid` folder in Android Studio, let Gradle sync, run on a phone with USB debugging
(or `./gradlew :app:assembleDebug`). Allow the Bluetooth permission prompt shown after onboarding.

**Simulators and emulators have no Bluetooth.** They show clearly labelled demo data.
Real discovery needs two physical devices (two iPhones, two Androids, or one of each).

## How the Bluetooth link works

Every phone plays both roles at once, so no pairing step is needed: it advertises the Nearsend service (GATT server) and scans
for it (GATT client). A router on top floods announcements, public messages and encrypted direct messages with a hop limit and
de-duplication. Full details, packet format, encryption and test vectors: [`docs/nearsend-chat/PROTOCOL.md`](docs/nearsend-chat/PROTOCOL.md).

Code: `NearsendChatiOS/Sources/Mesh/` (`BLETransport`, `MeshRouter`, `MeshCrypto`) and `NearsendChatAndroid/app/src/main/java/app/nearsend/chat/`
(`BleTransport.kt`, `MeshRouter.kt`, `MeshCrypto.kt`). Both implement the same protocol and run the same relay scenarios in CI.

## Design system

Taken from the Nearsend web app's `DESIGN.md`:

- Fixed sky background: blue to peach by day, navy with stars by night.
- Frosted-glass surfaces (white 84% by day, navy 74% by night), 24 px card radius, 12 px buttons.
- One filled blue per screen: action blue `#2F6FE0` (deep `#2459C0`). Green only for "connected / secure".
- Navy ink `#1B2A4A` by day, `#EAF2FF` by night. Text sitting directly on the sky goes on a dark-blue pill.
- Anton (capitals) for headlines and page titles, the system sans for everything else.
  The font file is downloaded from Google Fonts (OFL) by CI and committed.

## Known limitations

- Only texts between two iPhones have been seen working on real hardware. Photos, voice notes, relaying over 3 phones and Android↔iPhone are not proven over the air.
- Android does not reassemble write fragments yet, so photos and voice notes from a new iPhone to Android fail; Android also lacks voice notes, contact codes, message requests and the build 10 screens.
- Not audited. No forward secrecy; delivery and read receipts are not authenticated; announcements, the Nearby channel and SOS are public and unauthenticated by design; metadata is visible to relays.
- Text messages are limited to 180 UTF-8 bytes. Messages carried for others are kept in memory only (lost when the app restarts).
- Background operation: Android has a foreground service ("Keep running in the background", on by default) that also restarts itself after a reboot, an app update, a system kill or when Bluetooth is toggled; the start/restart wiring is verified on an emulator only; real Bluetooth in the background is untested, and some phone makers kill background apps. iOS keeps Bluetooth running in the background and has **state restoration** (iOS relaunches the app after the system terminates it), compiled but untested on a real iPhone. iOS does not relaunch an app the user force-quit from the app switcher, and it does not run our 8-second announcement timer while suspended.
- Translations were written without native-speaker review.
- Demo data is shown on simulators/emulators (they have no Bluetooth).

## Next steps

1. Run `REAL_PHONE_TEST_PLAN.md` with build 10, fix what breaks, then submit version 1.0 for review.
2. Crews by QR, Meet point and Find my crew (GPS), the plan in `PRODUCT_VISION_REPORT_2026-11-26.md`.
3. Bring Android level with iOS: write-fragment reassembly first, then voice notes, contact codes and message requests.
4. Save carried messages across app restarts; sealed receipts; independent security review; forward secrecy.
5. Native-speaker review of the translations; Play internal testing.

## Credits and licence

Fork of [Bitchat](https://github.com/permissionlesstech/bitchat) (GPL-3.0). Design from nearsend.app.
Anton font by Vernon Adams, SIL Open Font License.
