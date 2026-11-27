# Nearsend Chat — App Store Connect answers and App Review notes

Written 21 Nov 2026 for the first iOS submission, updated 27 Nov 2026 for version 1.0 build 10 (bundle id `app.nearsend.chat`).
Everything here is a draft for you to check; questions marked **YOU DECIDE** are yours to answer.

## 1. App Review notes (paste into "Notes" under App Review Information)

Updated 26 Nov 2026 for build 10 (about 2,500 characters; the field allows 4,000).

```
Nearsend Chat is an offline messenger. Phones talk directly to each other over Bluetooth Low Energy: no internet, no account, no server. Messages hop from phone to phone (up to 5 hops), and private chats are end-to-end encrypted.

ONE DEVICE
The app has no demo data: people and chats appear only when a second iPhone running Nearsend Chat is nearby. The attached video shows two iPhones finding each other, chatting and sending an SOS over Bluetooth. On one phone you can still review onboarding, the Nearby radar, SOS, and the You tab (Privacy, Notifications, Bluetooth, Account, Help).

FULL TEST WITH TWO DEVICES (recommended)
1. Install on two iPhones and turn Bluetooth on. Airplane Mode can stay on: the app needs no Wi-Fi or cellular.
2. Open the app on both and allow Bluetooth. Each phone appears on the other's Nearby tab within seconds.
3. Tap the other person to chat. The first message from someone you have never chatted with arrives as a "Message request" (You > Privacy > Messages from strangers is "Ask me" by default). Tap Accept to reply.

OTHER FEATURES
- App lock (You > Privacy): off by default; uses Face ID or the device passcode.
- Move to another phone (You tab): makes a password-encrypted file that the user shares themselves (AirDrop or Files). Nothing is uploaded.
- Invite a friend (You tab): shows a QR code of this app's App Store page.

BACKGROUND MODES
bluetooth-central and bluetooth-peripheral keep messages arriving, and being passed on to others, while the screen is locked (Core Bluetooth state restoration). No background location.

USER SAFETY (Guideline 1.2)
- Message requests: a stranger cannot start a chat until the user accepts. Strangers can also be blocked entirely in You > Privacy.
- Report: in a private chat tap (i) > Report; in the Nearby channel, a group or an announcement, long-press > Report. Report opens an email to support@nearsend.app.
- Block: long-press a message or announcement, the Block button in contact info, or Block on a message request.

SOS
SOS alerts only phones nearby that run Nearsend Chat. The screen states that it does not call emergency services and offers a call to the local emergency number.

PRIVACY
No accounts, analytics, ads or tracking. All data stays on the device; "Erase everything" (You > Account) deletes it. Location is used only when the user shares it or attaches it to an SOS; camera and microphone only for a photo or a voice message.

ENCRYPTION
Apple CryptoKit: X25519, HKDF and ChaCha20-Poly1305. The transfer file uses PBKDF2-SHA256 and ChaCha20-Poly1305.

CONTACT
support@nearsend.app
```

## 2. Demo video script (about 40 seconds, no sound needed)

**Why:** App Review often has only one device, and the app has no demo data: this video shows the real Bluetooth link
between two phones.

**Before you record**
- Two iPhones with the TestFlight build. Give them different nicknames on the You tab (for example "Anna" and "Ben").
- On both: **Airplane Mode on, then Bluetooth back on** (so the video shows there is no internet),
  Do Not Disturb off so the notification shows.
- Put both phones side by side on a table. Film from above with a third phone, or use screen recording on both and put
  the two recordings side by side.
- No real names, real chats or personal notifications on screen.

**Shot list**

| Time | What you show | On-screen caption (add in iMovie or the Photos editor) |
|---|---|---|
| 0–5 s | Both phones side by side. Swipe down Control Center on one to show Airplane Mode on and Bluetooth on. | "Airplane Mode on. Bluetooth on. No internet." |
| 5–12 s | Open Nearsend Chat on both. Each one appears on the other's Nearby tab within a few seconds. | "The phones find each other over Bluetooth" |
| 12–20 s | On phone A, tap "Ben" in the list under the radar and type "Hello from Anna". Tap send. | "Private chat, end-to-end encrypted" |
| 20–27 s | Phone B shows the message (notification or open chat). Reply "Got it!". | "Delivered phone to phone. No server." |
| 27–34 s | On phone B, tap the (i) button in the chat to show contact info with Block and Report. Close it. | "Report and Block, always one tap away" |
| 34–40 s | Open the SOS tab on one phone and show the text under the title. Do NOT send an alarm. | "SOS reaches phones nearby. It does not call emergency services." |

**After recording**
- Keep it under 1 minute. Export at 1080p.
- Upload as **unlisted** on YouTube (or share an iCloud link that works without signing in). Test the link in a private
  browser window.
- Put the link in place of `[VIDEO LINK]` in the notes above.

## 3. App Privacy ("nutrition label")

- **Data collection:** "No, we do not collect data from this app." (The iPhone app has no internet feature; nothing
  reaches us or any third party. Messages go phone to phone.)
- **Tracking:** No.
- Matches `NearsendChatiOS/Sources/Resources/PrivacyInfo.xcprivacy` (no tracking, no collected data; UserDefaults for the
  app's own settings, reason CA92.1).

## 4. URLs App Store Connect asks for

- **Privacy Policy URL:** https://chat.nearsend.app/privacy/
- **Support URL:** https://chat.nearsend.app/support/
- **Marketing URL:** https://chat.nearsend.app/
- All three are the Nearsend Chat website, `website/chat/` in this repo, deployed by hand to the Cloudflare Pages
  project `nearsend-chat` (see `website/README.md`). The privacy and support pages are built from `PRIVACY.md` and
  `SUPPORT.md` by `python3 scripts/build_chat_web_pages.py`. Entered in App Store Connect on 26 Nov 2026.

## 5. Export compliance (encryption)

Answered 25 Nov 2026: the app uses only standard encryption from Apple's CryptoKit (exempt). `ITSAppUsesNonExemptEncryption`
is set to `false` in `Info.plist` and `project.yml`, so App Store Connect no longer asks on every upload. If the app ever adds
its own or non-standard cryptography, revisit this.

## 6. Age rating — YOU DECIDE

Fill in Apple's questionnaire honestly. The relevant points: the app lets people **message strangers nearby**
(unmoderated user-generated content), has **no** violence, gambling or mature themes, and has Block and Report.
Chat with strangers usually leads to a teen rating rather than 4+.

## 7. Other App Store Connect fields

- **Name:** Nearsend Chat · **Subtitle:** Bluetooth chat with no signal · **Category:** Social Networking
  (secondary: Utilities). Keywords, promotional text and description: `STORE_LISTING.md`.
- **Copyright:** 2026 Zakaria Kaab (or your company name).
- **Price:** Free.
- **Screenshots:** `NearsendChatiOS/appstore-screenshots/` (6.3-inch and 6.9-inch iPhone, 13-inch iPad; all uploaded). They show the app's demo
  data from the simulator; the people in them are sample names.
- **Sign-in required:** No (there are no accounts).

## 8. Known risks for review

- **One-device testing** (guideline 2.1): if the reviewer cannot test with two devices they may reject or ask
  questions. The notes and video above are the answer; reply in App Store Connect if asked.
- **Build 10 is not tested on real phones yet.** Texts worked between two iPhones on earlier builds; run `REAL_PHONE_TEST_PLAN.md` with build 10 before submitting.
- **Bitchat fork:** the app is a GPL-3.0 fork. Keep the source public (it is) and do not use the Bitchat name or icon.
