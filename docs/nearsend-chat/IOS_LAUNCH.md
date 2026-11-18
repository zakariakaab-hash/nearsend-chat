# iOS App Store launch checklist

Written 18 Nov 2026. Priority is iOS first (see memory/decision of the same date). Status words: **DONE** (in the repo, built by CI),
**TODO-ME** (Claude can do it), **TODO-YOU** (needs your Apple account, money or a real device), **UNKNOWN** (not checked).

## A. Accounts and tooling (blocks everything)
| Item | Who | Notes |
|---|---|---|
| Apple Developer Program, about 99 USD per year (about 1,000 SEK) | TODO-YOU | Needed for TestFlight and the App Store. Enrol as an individual (days) or an organisation (needs a D-U-N-S number, weeks). I cannot create the account or pay |
| A build made with **Xcode 26 / iOS 26 SDK** | TODO-ME + YOU | Apple only accepts uploads built with Xcode 26 since 28 Apr 2026 ([Apple news](https://developer.apple.com/news/upcoming-requirements/)). **Update 18 Nov: you installed Xcode 27.2 on the MacBook (reported by you, not checked by me), so the Mac can now archive and upload once the developer account exists; CI is no longer needed for that.** CI still uses `macos-15-intel` (older Xcode). Original options, now mostly optional: **Xcode Cloud** (Apple's own build service, free hours come with the developer account; I have not verified the current free allowance), a GitHub macOS 26 runner (arm64 only, and arm64 runners were out of capacity for us before), or a newer Mac |
| Signing (certificate, provisioning profile) | TODO-YOU first | Created in your developer account. Bundle id is `app.nearsend.chat` (change it now if you want another, it is permanent once the app is created) |
| App created in App Store Connect | TODO-YOU | Name "Nearsend Chat" may already be taken; have a second name ready |

## B. Product gaps found in the iOS code
| Item | State | Notes |
|---|---|---|
| **Block people** | **Written, not yet compiled** (18 Nov) | Contact info has Block/Unblock; long-press on a public-channel or group message, or on an announcement, blocks its sender. Blocked phones' messages, photos, announcements and SOS alerts are dropped and their earlier public/group content is removed. Saved in `chat.json` |
| **Report content** | **Built, checked in the simulator** (18 Nov) | Long-press any received message or announcement → Report, or Report in contact info. Opens a prefilled email (person, id, time, content); with no mail app it shows the address with a Copy button. "Contact us" on the You tab. **TODO-YOU:** the address is the placeholder `support@nearsend.app` in `Support.email` (`FeatureViews.swift`); make it a real inbox or change it. A support web page is still needed for the store listing |
| Real-iPhone Bluetooth test | TODO-YOU (+ tablet) | Never run. See REAL_PHONE_TEST_PLAN.md. Reviewers will run it on real phones too |
| Review notes and a demo path | TODO-ME | One reviewer with one phone cannot see a mesh. Ship a demo mode and explain it in the review notes, or Apple may say the app has too little function |
| SOS wording | TODO-ME | Must not promise rescue or replace emergency calls. Check the text in the app and store page |
| Privacy policy page | TODO-YOU + ME | `PRIVACY.md` still has the placeholder `<your contact email>`; it needs a public URL (could live on nearsend.app) |
| Privacy "nutrition label" answers | TODO-ME to draft | Mostly "data not collected"; internet relays on Android only |
| Unused local-network permission text | TODO-ME | `NSLocalNetworkUsageDescription` is declared but the iOS app has no local-network feature; remove it to avoid review questions |
| Version | 0.1.0 (build 1) | Fine for TestFlight |

## C. Store page
Icon (exists), screenshots in the sizes Apple asks (6.9-inch iPhone and 13-inch iPad; CI already makes simulator shots, sizes
to be checked), description and keywords (draft in `STORE_LISTING.md`, written for Google Play first), age rating, support URL,
category (Social Networking), export-compliance answer (the app uses standard encryption, answer in App Store Connect).

## D. Order of work (one step at a time)
1. TODO-YOU: start the Apple Developer enrolment (takes time, so start now).
2. TODO-ME: add block and report on iOS (small, fixes a likely rejection).
3. TODO-ME: clean up permissions and wording, fill the privacy placeholders.
4. TODO-YOU + ME: first TestFlight build (Xcode Cloud or runner), install on your iPhone.
5. TODO-YOU: run the real-phone test plan with the iPhone and the tablet; fix what breaks.
6. TODO-ME: store page, screenshots, review notes. Submit for review.

Honest status: the iOS app compiles in CI and renders in the simulator. **No part of it has run on a real iPhone**, no Bluetooth link
has ever been made between two real phones, and the encryption has not been reviewed by a specialist.
