# Real-phone test plan (step 0)

Goal: find out what really works over Bluetooth before building more. Fill in the **Result** column as you go and keep the
numbers. Until a row says PASS on real devices, it is not verified.

## Devices
- A: Android tablet (SM-T500, Android 12), debug build from `NearsendChatAndroid`
- B: iPhone, debug build from `NearsendChatiOS` (built on the Mac, installed with Xcode)
- Optional C: a second Android phone, needed for the multi-hop tests (3 devices, A and C out of each other's range)

Both apps must be on the same protocol version (PROTOCOL.md section 1). Turn Bluetooth on, allow the permission prompts,
keep both screens on at first.

## Tests (do in order, stop at the first FAIL and note it)

| # | Test | Steps | Pass if | Result |
|---|---|---|---|---|
| 1 | Discovery A→B | Open both apps, phones 1 m apart | Each shows the other under Nearby within 30 s. Write the time | |
| 2 | Discovery, screen off | Lock B for 2 min, unlock | B still lists A | |
| 3 | Public channel | Send "hello" on Nearby channel from A, then from B | Arrives on the other within 5 s, both directions | |
| 4 | Contact swap | Scan each other's QR, compare the verification code | Codes match; contact saved | |
| 5 | Private message | A→B and B→A, 5 messages each | All arrive, shown as encrypted, ✓ receipts appear | |
| 6 | Photo | Send a photo A→B and B→A | Arrives within 60 s, opens full-screen; note time and size | |
| 7 | Group | Make a group with A and B | Messages both ways | |
| 8 | SOS | Send SOS (with position) from A | B shows it; check the position is right | |
| 9 | Store-and-forward | Turn B's Bluetooth off, send 3 messages from A, turn B back on | They arrive after reconnect (within 1 min); note delay | |
| 10 | Range | Walk apart in a line of sight, then through a wall | Note the distance where the link drops and returns | |
| 11 | Restart | Force-close A, reopen | Contacts and history are kept; peers reappear | |
| 12 | Multi-hop (needs C) | Put A and C out of range, B between | A's message reaches C through B; check TTL in the log | |
| 13 | Battery | 1 hour with the app in the background, screen off | Note % lost on each phone | |
| 14 | Background | App in background 10 min | Still discovered and messages still arrive (iOS limits this; record what happens) | |

## What to record for every failure
Which test, which phone was sender, time, what you saw, and whether turning Bluetooth off and on fixes it.
The apps have almost no logging yet (Android has one log line), so note what you see on screen and take screenshots.
Adding a simple debug log (link up/down, packets in/out, hops) is the first fix to make if a test fails. Android: `adb logcat`.
iPhone: Xcode → Window → Devices and Simulators → Open Console.

## After the run
Put the table in an issue or a new file with the date. Fix only what failed, in this order: discovery, delivery,
interoperability, then battery. Do not start step 1 (mesh hardening) until tests 1 to 6 pass.
