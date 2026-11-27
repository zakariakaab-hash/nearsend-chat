# Real-phone test plan

Goal: find out what really works over Bluetooth. Fill in the **Result** column as you go and keep the numbers. Until a row
says PASS on real devices, it is not verified. Updated 27 Nov 2026 for **iOS build 10**.

## Devices
- A and B: two iPhones with build 10 from TestFlight (different names on the You tab).
- Optional C: a third iPhone for the relay tests (A and C out of each other's range, B in the middle).
- Optional D: the Android tablet (SM-T500) with a debug build, for the iPhone↔Android rows. Note: Android does not reassemble
  write fragments yet (`PROTOCOL.md` section 2), so photos and voice notes **from** an iPhone **to** Android are expected to fail.

Turn Bluetooth on, allow the prompts, keep both screens on at first. Demo mode must be **off** (You → Bluetooth).

## Tests (do in order, stop at the first FAIL and note it)

| # | Test | Steps | Pass if | Result |
|---|---|---|---|---|
| 1 | Discovery | Open both apps, phones 1 m apart | Each shows the other on Nearby within 30 s, labelled "Very close" | |
| 2 | Text + receipts | 5 texts each way | All arrive; ring shows Delivered, then Read when the chat is opened | |
| 3 | **Photo** | One photo each way | Arrives within 60 s, Delivered; note the time | |
| 4 | **Voice note** | One 10 s voice note each way | Arrives, plays, sound bars show | |
| 5 | Add by QR | A: You → My code; B: Chats → + → Add contact → scan | B gets a chat with A, fingerprint matches | |
| 6 | Message request | Phone C (or a fresh install) writes to A first | A sees "Message request", no notification text; Accept opens the chat | |
| 7 | Bluetooth off | A: turn Bluetooth off in Control Center | A's list empties; tapping Close on the iOS alert opens the animated guide | |
| 8 | Allow New Connections | Follow the guide | Guide closes by itself; B reappears on A within 20 s | |
| 9 | Mesh switch ×10 | Nearby → switch Off/On ten times fast | No duplicates; B comes back every time | |
| 10 | Walk away | Walk out of range 1 min, come back | B reappears without restarting (connection timeout fix) | |
| 11 | Background + lock | Lock A, send from B | Notification with the hop sound within a few seconds | |
| 12 | Friend nearby | Keep A and B apart 30+ min (B's app open), bring together | A gets "B is nearby" | |
| 13 | App lock | A: You → Privacy → App lock on; background; reopen | Face ID asked; notifications show "New message" only | |
| 14 | Move to another phone | A: make a transfer file; C: restore it | C shows A's fingerprint, name and chats. Then erase C | |
| 15 | Relay (needs C) | A and C out of range, B between | A's text reaches C as "Through 1 other phone" | |
| 16 | SOS | Hold SOS on A with location | B shows the alarm at the top of SOS, with distance; cancel reaches B | |
| 17 | Battery | 1 h in background, screen off; then Battery saver on | Note % lost; messages still arrive with the saver on | |
| 18 | iPhone↔Android (needs D) | Texts both ways | Arrive both ways (photos iPhone→Android expected to fail) | |

## What to record for every failure
Which test, which phone was sender, time, what you saw, and whether turning Bluetooth off and on fixes it.
The app keeps a debug log of the last 500 events (who connected, packet types, hops, errors; never message text, photos or
keys). Right after a failure open **You → Help → Share debug log** on both phones and send the text to yourself. The log
restarts when the app is closed, so share it before you quit the app. With a Mac attached: Xcode → Window → Devices and
Simulators → Open Console (filter `app.nearsend.chat`).

## After the run
Put the table in a dated file. Fix only what failed, in this order: discovery, delivery (texts, then photos and voice),
interoperability, then battery.
