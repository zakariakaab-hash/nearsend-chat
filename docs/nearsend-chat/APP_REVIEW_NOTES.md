# Nearsend Chat — App Store Connect answers and App Review notes

Written 21 Nov 2026 for the first iOS submission (version 1.0, build 1, bundle id `app.nearsend.chat`).
Everything here is a draft for you to check; questions marked **YOU DECIDE** are yours to answer.

## 1. App Review notes (paste into "Notes" under App Review Information)

```
Nearsend Chat is an offline messenger: phones talk directly to each other over Bluetooth Low Energy, with no internet, no account and no server. Messages are passed phone to phone (up to 5 hops) and are end-to-end encrypted for private chats.

HOW TO TEST
The app needs at least TWO iPhones (or an iPhone and an iPad) with the app installed, Bluetooth on, and the app open.
1. Open the app on both devices, finish the 3 onboarding screens and allow Bluetooth.
2. Within a few seconds each device appears on the other's Nearby tab.
3. Tap the other person to open a private chat and send a message. It is delivered over Bluetooth only (you can turn on Airplane Mode and keep Bluetooth on to confirm).
4. The Nearby channel (Chats tab) is a public room for everyone in range.
With only ONE device the Nearby tab stays empty: there is nobody to talk to. A short video showing two phones is attached / linked here: [VIDEO LINK]

BACKGROUND MODES
bluetooth-central and bluetooth-peripheral are used so that messages from people nearby are still received, and passed on to others, while the screen is locked. The app uses Core Bluetooth state restoration. It does not use location in the background.

SAFETY
- Block and Report: long-press any message or announcement, or open a person's contact info. Report opens an email to support@nearsend.app with the details. Blocked people's messages are hidden and ignored.
- SOS sends an alarm to phones nearby that run the app. The screen states that it does not call emergency services and offers "Call 112" when there is signal.
- No accounts, no analytics, no ads, no tracking. All data stays on the device; "Erase everything" on the You tab deletes it.

ENCRYPTION
Private messages use X25519 + HKDF + ChaCha20-Poly1305 from Apple's CryptoKit.
```

## 2. Before you submit: a demo video

App Review often tests with one device. Record 20 to 40 seconds with two phones: open both, they find each other,
send a message, it arrives. Upload it unlisted (YouTube or iCloud link) and put the link where it says `[VIDEO LINK]`.

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
