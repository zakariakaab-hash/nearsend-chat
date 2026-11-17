# Nearsend Chat — store listing drafts

Draft text for Google Play and the App Store, written from a pre-launch ASO audit (17 November 2026). Limits: Play title 30,
short description 80, full description 4000; App Store name 30, subtitle 30, keywords 100, promotional text 170.
Review every claim against the real app before you publish. Nothing has been tested between real phones yet.

## Google Play

**Title (27):** `Nearsend: Offline Mesh Chat`

**Short description (80):** `Chat with people nearby over Bluetooth. No internet, no account, no phone number`

**Full description:**

```
No signal? No problem.

Nearsend Chat sends messages phone to phone over Bluetooth. Other phones nearby pass your message along, up to 5 hops, until it arrives. No internet, no cell signal, no account and no phone number.

WHAT YOU CAN DO
• Private chats, end-to-end encrypted. Phones that pass a message along cannot read it.
• Out of range? Your message waits and is carried by phones nearby for up to 24 hours, then handed over when the person shows up.
• Optional Internet switch: reach contacts who are far away through public relay servers. Off by default, still encrypted.
• A public Nearby channel for everyone in range (clearly labelled: not encrypted).
• Group chats, announcements that stay visible for a few hours, and small photos to a contact in range.
• SOS: hold a button to alert every phone nearby, with your position if you choose. It does NOT call emergency services.
• Emoji and colour profile pictures, a radar view and a network view of who is nearby and how they connect.
• Verify a contact by scanning their QR code or comparing fingerprints in person.
• Privacy switches: stop passing on others' messages, turn off delivery receipts, hide message text in notifications, delete messages automatically.
• Battery saver with a pure black screen. "Erase everything" wipes the phone in one tap.
• 12 languages: English, Svenska, Español, Français, Deutsch, Português, Italiano, العربية, Türkçe, Русский, 简体中文, 日本語.

NO TRACKING
No accounts, no ads, no analytics, no servers of our own. Messages and keys stay on your phone. The app is open source (GPL-3.0).

GOOD TO KNOW
• Both phones need the app open or running in the background, and Bluetooth on.
• Range depends on your phone and the surroundings; every extra phone helps.
• This is an early version. It has not been security audited, so do not rely on it where your safety depends on it.
• SOS alerts only reach phones that run Nearsend Chat nearby. In an emergency call your local emergency number.

Questions or feedback: <your contact email>
```

## App Store (later; the iPhone app trails the Android one)

| Field | Text |
|---|---|
| Name (13) | `Nearsend Chat` |
| Subtitle (28) | `Offline messenger, no signal` |
| Keywords (98) | `bluetooth,mesh,nearby,private,encrypted,festival,hiking,sos,group,relay,local,radar,walkie,no wifi` |
| Promotional text (85) | `Message people nearby with no internet and no signal. Private, encrypted, no account.` |
| Description | Same as the Play description, minus the Internet and battery-saver lines until the iPhone app has them |
| Privacy label | Data not collected (the iPhone app has no internet feature) |

## Images

- **Icon:** 512×512 PNG (Play) and the 1024×1024 App Store icon. The radar icon has no text; check it at small size.
- **Feature graphic (Play):** 1024×500. Not made yet.
- **Phone screenshots:** 2 to 8 on Play, up to 10 on the App Store. Retake on a **real phone without the "Demo data" label**.
  Add a one-line benefit caption to each. Order:
  1. Nearby radar: "See who is near, with no signal"
  2. Encrypted chat: "Private, end-to-end encrypted"
  3. SOS: "Alert everyone nearby"
  4. Messages that wait: "Out of range? It waits and is carried to them"
  5. Announcements: "Notices that stay up for a few hours"
  6. Photos: "Send a photo to a friend in range"
  7. Privacy: "You decide what is passed on"
  8. Languages: "12 languages"
- **Video (optional):** 20 to 30 seconds, two phones, no signal, a message arrives. Must work without sound.

## Policy checklist

- SOS must be described as **not** contacting emergency services (done in the text above).
- Do not call the app secure or safe until it has been reviewed (`PROTOCOL.md` section 7).
- Data safety form and the privacy policy must mention the optional Internet relays, location (SOS and chat) and the camera (QR scanning). See `RELEASING.md` and `PRIVACY.md`.
- Foreground service type "connected device": explain it is for Bluetooth messaging while the app is closed.
- Screenshots must show the real app.

## What's new (per test release)

Write two or three lines for each upload. Example for 0.2.0: "Photos in chats, emoji pictures, announcements, optional Internet switch, privacy settings and a battery saver."
