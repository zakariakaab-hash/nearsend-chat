# Nearsend Chat — App Store Connect answers and App Review notes

Written 21 Nov 2026 for the first iOS submission (version 1.0, build 1, bundle id `app.nearsend.chat`).
Everything here is a draft for you to check; questions marked **YOU DECIDE** are yours to answer.

## 1. App Review notes (paste into "Notes" under App Review Information)

Final text, checked against the code on 21 Nov 2026 (about 2,400 characters; the field allows 4,000).
Replace `[VIDEO LINK]` with the link to the video from section 2 before you submit.

```
Nearsend Chat is an offline messenger. Phones talk directly to each other over Bluetooth Low Energy: no internet, no account, no server. Messages hop from phone to phone (up to 5 hops), and private chats are end-to-end encrypted.

QUICK REVIEW WITH ONE DEVICE (recommended)
1. Open the app and go through the 3 onboarding screens.
2. Open the You tab, scroll down and turn on "Demo mode".
3. The app now shows sample people, chats, a group, announcements and an SOS alarm, so every screen can be reviewed without a second phone. Bluetooth is off while Demo mode is on. Turn it off to return to normal use.

FULL TEST WITH TWO DEVICES
1. Install the app on two iPhones (or an iPhone and an iPad). Turn Bluetooth on. Airplane Mode can stay on: the app does not need Wi-Fi or cellular.
2. Open the app on both devices, finish onboarding and allow Bluetooth.
3. Within a few seconds each device appears on the other's Nearby tab, in the list under the radar.
4. Tap the other person to open a private chat and send a message. It arrives over Bluetooth only.
5. The Chats tab also has the "Nearby channel", a public room for everyone in range.
A 40-second video of two real phones doing this: [VIDEO LINK]

BACKGROUND MODES
bluetooth-central and bluetooth-peripheral let the app keep receiving messages from people nearby, and pass them on to others, while the screen is locked. The app uses Core Bluetooth state restoration. It does not use location in the background.

USER SAFETY (Guideline 1.2)
- Report: long-press any message or announcement and tap Report, or tap the (i) button in a chat to open contact info. Report opens an email to support@nearsend.app with the details.
- Block: long-press a message in the Nearby channel or a group, or an announcement, or use the Block button in contact info. Blocked people's messages and announcements are hidden and ignored.
- Contact us: You tab.

SOS
SOS sends an alarm only to phones nearby that run Nearsend Chat. The SOS screen states that it does not call emergency services, and offers "Call 112" for when there is cell signal.

PRIVACY
No accounts, no analytics, no ads, no tracking. All data stays on the device. "Erase everything" on the You tab deletes it. Location is used only when the user attaches it to an SOS alarm.

ENCRYPTION
Private messages use X25519, HKDF and ChaCha20-Poly1305 from Apple's CryptoKit.

CONTACT
support@nearsend.app
```

## 2. Demo video script (about 40 seconds, no sound needed)

**Why:** App Review often has only one device. Demo mode covers the screens; this video proves the real Bluetooth link
between two phones.

**Before you record**
- Two iPhones with the TestFlight build. Give them different nicknames on the You tab (for example "Anna" and "Ben").
- On both: **Airplane Mode on, then Bluetooth back on** (so the video shows there is no internet), Demo mode **off**,
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
| 27–34 s | On phone B, long-press Anna's message to show Report, then tap the (i) button to show contact info with Block and Report. Close it. | "Report and Block, always one tap away" |
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

- **Privacy Policy URL:** https://nearsend.app/chat/privacy
- **Support URL:** https://nearsend.app/chat/support
- Both pages are built by `python3 scripts/build_chat_web_pages.py` into `docs/nearsend-chat/web/chat/…/index.html`.
  **YOU:** upload them to the nearsend.app site so those two URLs work before you submit. Today they return 404.

## 5. Export compliance (encryption) — YOU DECIDE

App Store Connect asks about encryption for every build. The app uses encryption (end-to-end encrypted chats) and only
standard algorithms through Apple's CryptoKit. For this kind of app the usual answers are "Yes, it uses encryption" and
that it qualifies for the mass-market / standard-encryption exemption. This is a legal export question, so read Apple's
page "Complying with encryption export regulations" and answer it yourself. Once you know the answer you can add
`ITSAppUsesNonExemptEncryption` to `Info.plist` so you are not asked on every upload; I have not added it.

## 6. Age rating — YOU DECIDE

Fill in Apple's questionnaire honestly. The relevant points: the app lets people **message strangers nearby**
(unmoderated user-generated content), has **no** violence, gambling or mature themes, and has Block and Report.
Chat with strangers usually leads to a teen rating rather than 4+.

## 7. Other App Store Connect fields

- **Name:** Nearsend Chat · **Subtitle:** Bluetooth chat with no signal · **Category:** Social Networking
  (secondary: Utilities). Keywords, promotional text and description: `STORE_LISTING.md`.
- **Copyright:** 2026 Zakaria Kaab (or your company name).
- **Price:** Free.
- **Screenshots:** `NearsendChatiOS/appstore-screenshots/` (6.9-inch iPhone and 13-inch iPad). They show the app's demo
  data from the simulator; the people in them are sample names.
- **Sign-in required:** No (there are no accounts).

## 8. Known risks for review

- **One-device testing** (guideline 2.1): if the reviewer cannot test with two devices they may reject or ask
  questions. The notes and video above are the answer; reply in App Store Connect if asked.
- **Real-phone behaviour is untested.** Run `REAL_PHONE_TEST_PLAN.md` with TestFlight before submitting.
- **Bitchat fork:** the app is a GPL-3.0 fork. Keep the source public (it is) and do not use the Bitchat name or icon.
