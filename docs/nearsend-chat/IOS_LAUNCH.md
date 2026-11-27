# iOS App Store launch checklist

Started 18 Nov 2026, updated 27 Nov 2026. Status words: **DONE**, **TODO-ME** (Claude can do it), **TODO-YOU** (needs your
Apple account, a decision or real phones).

## Where it stands (27 Nov 2026)

- App Store Connect: app **Nearsend Chat** (Apple ID 6839386595, bundle id `app.nearsend.chat`), version **1.0**,
  state *Prepare for Submission*. **Build 10** is attached and saved, review notes updated (`APP_REVIEW_NOTES.md`).
- Builds 3 to 10 were uploaded from the Mac (see `RELEASING.md`). Build 10 is the first with photos and voice notes that
  work over every Bluetooth link (write fragments), the 20 s connection timeout and key pinning (`AUDIT_2026-11-26.md`).
- Release setting in App Store Connect: **Automatically release this version**. Switch to manual if you want to pick the day.
- **Not yet done:** a test of build 10 on two real iPhones, and **Add for Review**.

## A. Accounts and tooling
| Item | Status | Notes |
|---|---|---|
| Apple Developer Program | DONE | Team HW9XRXBJZA |
| Xcode 26 / iOS 26.5 SDK | DONE | Apple requires the iOS 27 SDK (Xcode 27) for uploads from April 2027 |
| Signing | DONE | Automatic signing, `-allowProvisioningUpdates` |
| App in App Store Connect | DONE | Name, subtitle, keywords, description, screenshots, privacy and support URLs entered |

## B. Product items
| Item | Status | Notes |
|---|---|---|
| Block and Report | DONE | Long-press, contact info, and Block on message requests |
| Messages from strangers | DONE (build 10) | Ask me (default) / Allow / Block; Hide me from strangers |
| App lock, Move to another phone, Invite a friend | DONE (build 10) | Checked in the simulator; Face ID and the transfer file need a real phone |
| Demo mode for one-phone review | DONE | You → Bluetooth → Demo mode |
| SOS wording | DONE | States it does not call emergency services; local emergency number |
| Privacy policy and support pages | DONE | https://chat.nearsend.app/privacy/ and /support/, built from `PRIVACY.md` / `SUPPORT.md` (`python3 scripts/build_chat_web_pages.py`), uploaded by hand to Cloudflare Pages. **TODO-YOU: re-upload `website/chat/` after the 26 Nov policy changes** |
| Privacy label | DONE | Data not collected; `PrivacyInfo.xcprivacy` |
| Export compliance | DONE | `ITSAppUsesNonExemptEncryption = false` (CryptoKit only), answered 25 Nov 2026 |
| Real-phone test | **TODO-YOU** | `REAL_PHONE_TEST_PLAN.md`, with build 10 from TestFlight |
| Demo video for the review notes | TODO-YOU (optional) | Script in `APP_REVIEW_NOTES.md` section 2 |
| Support inbox | TODO-YOU | Confirm `support@nearsend.app` receives mail |

## C. Order of work from here
1. TODO-YOU: install build 10 from TestFlight on two iPhones and run the test plan (at least tests 1 to 8).
2. TODO-ME: fix whatever fails, upload build 11 if needed and attach it to version 1.0.
3. TODO-YOU: re-upload `website/chat/` so the policy matches the app.
4. TODO-YOU: Add for Review.

Honest status: the protocol tests pass (77 checks) and every screen has been checked in the simulator, but the Bluetooth
fixes in build 10 have **not** run on real phones yet, and the encryption has not been reviewed by a specialist.
