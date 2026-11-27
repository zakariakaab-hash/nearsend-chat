# Nearsend Chat — Privacy Policy

**Last updated:** 26 November 2026

**Contact:** support@nearsend.app

**Project:** Nearsend Chat, an open-source app (GPL-3.0). Source code: https://github.com/zakariakaab-hash/nearsend-chat

<!-- Owner note: update this policy whenever the app starts doing something new with data, and change the date. -->

## In short

- Nearsend Chat has **no accounts, no servers of its own, no analytics, no advertising and no tracking**.
- Messages go **directly between phones over Bluetooth**. We never receive them.
- There is one **optional** internet feature ("Internet", off by default). If you switch it on, private messages to
  contacts who are out of Bluetooth range go through **public relay servers that we do not run**. They stay end-to-end
  encrypted, but those servers can see your IP address and when you send. See "Internet option" below.
- Everything the app keeps stays **on your phone**. "Erase everything" deletes it.

## iPhone and Android

This policy covers both apps. The **iPhone app has no Internet option**, so the "Internet option" section and the Internet
permission below apply to the Android app only.

## What the app keeps on your phone

- Your nickname, your picture (emoji and colour), a random device id and your private encryption key (Android: app-private storage; iOS: Keychain).
- Your conversations, including photos and voice notes you sent or received (small files in the app's private storage), so they are there after a restart. You can set messages to delete themselves after 1, 7 or 30 days
  (You tab → Privacy).
- Your contacts' public keys and which contacts you verified, so you can message people who are out of range.
- Your settings (for example background running, battery saver, app lock, privacy switches, who may message you).
- On iPhone, when people you chat with were last in Bluetooth range (kept 7 days), so the app can tell you when a friend
  is nearby again. You can switch this off (You → Notifications).
- Messages and announcements from other people that your phone is carrying for them for a while (up to 24 hours), if
  "Pass on messages for others" is on. These are kept in memory and are lost when the app restarts. Private messages
  stay encrypted; you cannot read them.

"Erase everything" (You → Account, or triple-tap the You title) deletes all of this and creates a new identity. Uninstalling the
app removes it too. We cannot recover it, because we never had it.

## What other people nearby can see

Bluetooth is a broadcast medium, so people near you can see some things:

- That your phone runs Nearsend Chat, your **nickname**, your **picture** (an emoji and a colour you choose), your random device id and your **public key**.
  On iPhone, **Hide me from strangers** (You → Privacy) shows "Nearsend user" and no picture instead; people you already chat
  with still see your name.
- **Photos and voice notes** go only to one contact in direct Bluetooth range, end-to-end encrypted. The app shrinks photos and
  removes camera metadata (including the GPS position) before sending. They are never sent over the internet relays.
- **Private messages** are end-to-end encrypted. Phones that pass them on cannot read them, but they can see who they are
  from and to, and when.
- **The Nearby channel, announcements and SOS alarms are public and not encrypted.** Everyone in range can read them, and
  other phones may keep and pass them on. Announcements are kept by nearby phones until they expire (at most 24 hours).
- If you attach a position to an **SOS alarm**, everyone who receives the alarm can see it.

## Messages from strangers (iPhone)

A "stranger" is someone you have no chat with yet. By default their first message waits as a **request**: you choose to
accept or block it, and they get no read receipt until you accept. You can also allow or block all strangers
(You → Privacy).

## Moving to another phone (iPhone)

"Move to another phone" makes a **transfer file** with your identity (including your private key), chats, contacts and,
if you choose, photos and voice notes. It is encrypted with a password you choose (at least 10 characters). The app does
not upload it anywhere: you decide where it goes (for example AirDrop or Files). Anyone who has the file **and** the
password can take over your identity, so keep both private and delete the file once the new phone works.

## Internet option (optional, off by default)

If you switch on "Internet" on the Nearby tab, the app connects to these public relay servers (Nostr relays):
relay.damus.io, nos.lol, relay.primal.net and offchain.pub. They are run by other people, not by us.

- What is sent: only **private messages and receipts for your contacts**, sealed so that only the receiver can open them,
  and signed with a throw-away key made for each message. The relays cannot read the text and cannot see who sent it.
- What the relays can see: your **IP address**, **when** you connect or send, the **size** of each message, and a code
  that identifies the **receiver** (a hash of their public key). The app asks relays to delete messages after 24 hours,
  but a relay may keep them longer.
- Nothing else uses the internet: the Nearby channel, announcements and SOS never go to relays.
- You can switch it off at any time. Their own privacy policies apply to what they do with the data they receive.

## Permissions

- **Bluetooth** (nearby devices) — to find nearby phones and exchange messages. Required for the app to work.
- **Notifications** — optional; to tell you about new messages. You can hide the message text in notifications
  (You tab → Privacy).
- **Foreground service / run in the background** — optional; keeps Bluetooth running while the app is closed, with a
  notification. You can switch it off on the You tab. The app can also start again after the phone restarts.
- **Location** — optional. Used only to attach your position to an SOS alarm, to share a position in a chat when you
  choose "Location", and to show how far away an alarm is. Your position is processed on your phone and is sent only to
  the people you send it to (encrypted in a private chat; **not encrypted** in an SOS alarm). On Android 11 and older,
  Android also requires the location permission for Bluetooth scanning; the app does not read your position for that.
- **Camera** — when you scan a QR code to add or verify a contact (images are not saved or sent), and on iPhone when you
  take a photo to send in a chat.
- **Microphone** (iPhone) — only while you hold the microphone button to record a voice note.
- **Face ID / Touch ID** (iPhone) — only if you turn on App lock or lock a chat. iOS checks your face or finger; the app
  only learns "yes" or "no" and never sees biometric data.
- **Internet** — only used when you switch on the "Internet" option.

## Children

Nearsend Chat is not directed at children under 13, and we do not knowingly collect any data from anyone. Because nothing
is sent to us, we have nothing to share, keep or delete on our side.

## Sharing, selling, advertising

We do not sell or share personal data, we show no ads and we use no analytics or crash-reporting services. The only third
parties that can see anything are (a) people near you on Bluetooth, as described above, and (b) the public relay servers,
only if you switch on "Internet".

## Your choices and rights

All your data is on your phone, so you control it: delete messages, remove contacts, block people, switch features off, or
erase everything. To report abusive content or a person, long-press their message (or open their contact info) and tap
Report; this opens an email to support@nearsend.app with the details you choose to send. If you are in the EU/EEA or the UK and want to exercise a data protection right, note that we hold no
data about you; the relay operators (if you used "Internet") are separate from us and you can contact them.

## Security

Private messages use X25519 key agreement and ChaCha20-Poly1305 encryption. The project has **not been security audited**
and has not been tested on many devices yet. Do not rely on it where your safety depends on it. Public messages and SOS
alarms are not encrypted and can be faked by anyone.

## Changes

If this policy changes, the new version and date will be published here.
