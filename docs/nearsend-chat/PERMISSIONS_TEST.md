# Permissions: what the app asks, and how to test it on a real iPhone

Updated 28 Nov 2026. Nearsend Chat uses **Bluetooth only** to reach phones nearby. It does **not** use Local Network,
Bonjour or MultipeerConnectivity, and it never saves to the photo library, so `NSLocalNetworkUsageDescription`,
`NSBonjourServices` and `NSPhotoLibraryUsageDescription` are deliberately absent (adding them would show a needless prompt
or fail review). Photos are picked with the system photo picker, which needs no permission.

## The rule

Every permission goes through one rule (`PermissionStep` in `Sources/Models/Models.swift`, tested in `Tests/main.swift`):

| State | What the app does |
|---|---|
| Not asked yet | Our explanation dialog first (why, what for), then iOS's own prompt |
| Allowed | Uses the feature straight away |
| Denied | A dialog saying it's off, with **Open Settings** |
| Restricted (Screen Time, profile) | A dialog saying it's blocked on this iPhone, **OK** only (the app's Settings page can't change it) |

## When each one is asked

| Permission | Asked when | Explained first | Denied / off |
|---|---|---|---|
| Bluetooth | End of onboarding (Continue) | Yes | "Bluetooth is not allowed" → Open Settings. Bluetooth switched off: "Bluetooth is off" → Turn on Bluetooth (shows iOS's alert, whose Settings button opens Bluetooth) |
| Location (while using) | Attach my location in SOS, or Location in a chat | Yes | Refused → Open Settings; the SOS switch turns itself off. Location Services off → Turn on Location Services |
| Camera | Take a photo in a chat, or Scan a QR code | Yes | Open Settings |
| Microphone | First hold of the voice button | Yes (then hold again) | Open Settings |
| Notifications | After you send your first message in a chat | Yes | You → Notifications shows "Notifications are off" with Open Settings |
| Face ID | Turning on App lock, or opening a locked chat | The switch itself | Falls back to the passcode |

## Reset so the prompts show again
- Quickest: delete Nearsend Chat and install it again from TestFlight (resets every prompt for this app).
- Or Settings › General › Transfer or Reset iPhone › Reset › **Reset Location & Privacy** (resets every app).
- The simulator can't test Bluetooth or a phone-wide Location Services switch: everything below needs a **real iPhone**.

## Checklist (real iPhone, fresh install)

| # | Do | Expect |
|---|---|---|
| 1 | Open the app the first time | No iOS prompt at all during the first onboarding pages |
| 2 | Last onboarding page → Allow Bluetooth & start | Our "Nearsend Chat uses Bluetooth" dialog, then iOS's Bluetooth prompt. Tap Allow |
| 3 | Look at Nearby | No notifications prompt yet; Bluetooth shows On |
| 4 | Turn Bluetooth off in Control Center, reopen the app | "Bluetooth is off" dialog; Turn on Bluetooth → iOS alert → Settings → switch on → back in app the other phone reappears |
| 5 | Settings › Nearsend Chat › Bluetooth off, reopen | "Bluetooth is not allowed" → Open Settings opens the app's page |
| 6 | Open a chat, send a message | About a second later: "Know when they reply?" → Continue → iOS's notification prompt |
| 7 | Send another message | No second notifications dialog |
| 8 | Tap + › Camera in a chat | "Use the camera?" → Continue → iOS prompt → Allow → camera opens |
| 9 | Settings: camera off, tap + › Camera again | "Camera is off for Nearsend Chat" → Open Settings. No black screen |
| 10 | You › My code area › Scan (or Chats › + › Add contact › Scan) with camera off | Same "Camera is off" dialog; the Scan button never disappears |
| 11 | Hold the voice button the first time | "Use the microphone?" → Continue → iOS prompt → Allow → hold again records |
| 12 | Settings: microphone off, hold the button | "Microphone is off" → Open Settings; nothing records, nothing freezes |
| 13 | SOS › Attach my location on | "Share your location?" → Continue → iOS prompt with the map |
| 14 | Tap Don't Allow in iOS's prompt | The switch turns back off |
| 15 | Settings › Privacy & Security › Location Services off, then the switch on | "Location Services is off" → Turn on Location Services → iOS alert → Settings |
| 16 | Screen Time › Content & Privacy › Camera (or Location) not allowed, then use it | "Blocked on this iPhone" → OK only |
| 17 | Settings › Nearsend Chat › Notifications off, open You › Notifications | "Notifications are off" with Open Settings |
| 18 | You › Privacy › App lock on, background, reopen | Face ID; cancel → Unlock button; passcode works too |
