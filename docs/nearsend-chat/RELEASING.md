# Releasing Nearsend Chat

What is still needed before real people can install the apps. Items marked **(you)** need your accounts or decisions.

## 0. Before any release
- [ ] **Test on real phones:** iPhone↔iPhone, Android↔Android, iPhone↔Android, and a 3-phone chain for relaying. Texts have worked between two iPhones (TestFlight builds 3 to 8); photos, voice notes and the build 10 fixes are not tested yet (`REAL_PHONE_TEST_PLAN.md`).
- [ ] Decide the Bitchat question: this app is **not** compatible with Bitchat. The repo is a GPL-3.0 fork, so releases must offer source (the repo does).
- [ ] Get the protocol reviewed (`PROTOCOL.md` section 5). Do not market it for protests, emergencies or anything safety-critical until then.
- [x] `PRIVACY.md` is published at https://chat.nearsend.app/privacy/ (rebuild with `python3 scripts/build_chat_web_pages.py`, then upload `website/chat/`). **(you, after each policy change)**

## 1. iOS — TestFlight, then App Store
1. Apple Developer Program (team `HW9XRXBJZA`): done. Xcode must be signed in (Xcode → Settings → Accounts); an upload that
   fails with "No Accounts with App Store Connect Access" means the sign-in expired. **(you)**
2. Raise the build number in **both** `NearsendChatiOS/project.yml` (`CURRENT_PROJECT_VERSION`) and
   `NearsendChat.xcodeproj/project.pbxproj` (two lines), because the project file is also edited by hand. The last upload was **build 10**.
3. Run the protocol tests (they must print `ALL PASSED`):
   `swiftc -o /tmp/proto Sources/Models/Models.swift Sources/Mesh/MeshCrypto.swift Sources/Mesh/Framing.swift Sources/Mesh/NLog.swift Sources/Mesh/MeshRouter.swift Tests/main.swift && /tmp/proto`
4. Archive and upload from `NearsendChatiOS/` (or Product → Archive → Distribute App in Xcode):
   ```
   xcodebuild -project NearsendChat.xcodeproj -scheme NearsendChat -configuration Release \
     -destination 'generic/platform=iOS' -archivePath build/NearsendChat.xcarchive -allowProvisioningUpdates archive
   xcodebuild -exportArchive -archivePath build/NearsendChat.xcarchive -exportPath build/export \
     -exportOptionsPlist upload.plist -allowProvisioningUpdates
   ```
   `upload.plist`: `method` = `app-store-connect`, `destination` = `upload`, `teamID` = `HW9XRXBJZA`, `signingStyle` = `automatic`,
   `manageAppVersionAndBuildNumber` = false. Apple processes the build in 15 to 30 minutes and sends an email.
5. In App Store Connect, version page → Build: remove the old build (minus button), Add Build, pick the new one, Save.
5. App Store listing: name, subtitle, description, privacy policy URL, age rating, screenshots (see `NearsendChatiOS/previews/`; App Store needs 6.9″/6.5″ sizes — re-shoot from the matching simulators).
6. **App Review notes:** explain that the app needs two physical devices to demonstrate Bluetooth, and why it declares the `bluetooth-central` and `bluetooth-peripheral` background modes (receive messages while the screen is off). Provide a short demo video. State restoration (`bluetooth-central`/`bluetooth-peripheral` plus restore identifiers) is the reason for the background modes. Reviewers cannot test Bluetooth alone — expect questions.
7. Privacy "nutrition label": *Data not collected*.

## 2. Android — internal testing, then Play
1. Google Play Console, one-time **US$25**. **(you)**
2. Create an upload key and keep it safe: `keytool -genkey -v -keystore nearsend-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`. **Never commit it.**
3. Put the key details in `~/.gradle/gradle.properties` (on your computer, never in the repo):
   `NEARSEND_KEYSTORE=C:/path/to/nearsend-upload.jks`, `NEARSEND_KEYSTORE_PASSWORD=...`, `NEARSEND_KEY_ALIAS=upload`, `NEARSEND_KEY_PASSWORD=...`.
   `app/build.gradle.kts` reads them. Then run `./gradlew :app:bundleRelease` in `NearsendChatAndroid/`; the signed bundle is
   `app/build/outputs/bundle/release/app-release.aab`. Without the four lines the bundle is built **unsigned** and Play will refuse it.
   Upload it to *Internal testing* first. For each new upload raise `versionCode` in `app/build.gradle.kts`.
   Back up the `.jks` file and its passwords somewhere safe (with *Play App Signing* Google keeps the real signing key, and the upload
   key can be reset through Play support if lost, but it is slow).
4. Store listing, privacy policy URL (publish `PRIVACY.md`, see the checklist above), Data safety form, content rating, target audience.
   Data safety: nothing is sent to us. Because of the optional "Internet" switch, do not tick "no data shared" blindly: read Google's definitions and
   decide whether the IP address and send times that public relays see count (messages themselves are end-to-end encrypted and user-initiated).
   Also declare: precise location (optional, only to attach to SOS or a chat message), camera (QR scanning, not stored), and the foreground service.
   The app targets Android 16 (`targetSdk` 36, raised in November 2026). Play asks for a recent level every August: check `targetSdk` before each upload.
5. **Internet is optional and off by default.** The `INTERNET` permission is declared, but the app only connects when the user turns on "Internet" on the Nearby tab (after a warning). Then public relay servers see the phone's IP address and send times, not the text. So in the Data safety form do **not** say "no data shared" without care: declare that data is sent off the device only when this switch is on, is end-to-end encrypted, and say so in the privacy policy (`PRIVACY_POLICY.md`).
   Bluetooth permissions are declared `neverForLocation`. The app also asks for location (`ACCESS_FINE_LOCATION`), on Android 12+ only when someone opens the SOS tab and turns on "Attach my location" (on Android 11 and older, Bluetooth scanning itself needs it, so it is asked at start). In the Data safety form, declare *precise location*, not collected (it is sent only to phones nearby, never to a server), optional, for app functionality.
6. Background delivery: `MeshService` is a foreground service of type `connectedDevice` (permissions `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_CONNECTED_DEVICE`). Play asks you to declare foreground service types in the Console: choose *Connected device* and explain it is for Bluetooth messaging with nearby phones while the app is closed. It shows an ongoing notification and can be switched off in the You tab. `RECEIVE_BOOT_COMPLETED` is declared so the service comes back after a reboot or update (Play accepts this for apps whose core feature needs it; mention it in the listing). Some phone makers (Xiaomi, Huawei, OnePlus, Samsung "sleeping apps") kill background apps anyway; tell testers to exclude the app from battery optimisation (see dontkillmyapp.com).

## 3. Adding or fixing a language
Edit `i18n/translations.txt` (one row per string, one column per language), then run `python3 i18n/generate.py`.
This regenerates the iOS `*.lproj/Localizable.strings` and the Android `values-*/strings.xml` so the two apps stay in sync.
To add a language, add a column and the code to `LANGS` in `generate.py` and to the picker lists (`AppLanguage.all` in `NearsendChatApp.swift`, `LANGUAGES` in `Screens.kt`).
The current translations were produced without a native-speaker review: have each reviewed before release.

## 4. Continuous integration
`.github/workflows/nearsend-chat-ios.yml` and `...-android.yml` run the protocol tests, build both apps and refresh the screenshots on every push to `ios-app`.

## 5. Testing iOS background behaviour (needs two iPhones)
1. Run on both phones from Xcode, finish onboarding, confirm they see each other, then press Home on phone A (do **not** force-quit).
2. Send a message from phone B: phone A should show a notification within a few seconds, even with the screen locked.
3. Restoration: in Xcode, Debug ▸ *Simulate memory warning* does not terminate the app, so use Xcode's *Product ▸ Stop*, then **re-launch from a message**: with phone A stopped from Xcode (not swiped away in the app switcher), send a message from phone B; iOS should relaunch A in the background and deliver a notification. If it does not, check Settings ▸ General ▸ Background App Refresh is on.
4. Remember: iOS never restores an app the user force-quit, and may delay background work in Low Power Mode.

## 6. Testing Android restart after reboot (needs a real phone)
CI proves the boot/update receiver runs and decides to restart the service, but an `adb` broadcast does not carry the temporary
allow-list that Android gives a real boot, so the OS-level foreground start after a real reboot is untested.
Test: finish onboarding, leave "Keep running in the background" on, reboot the phone, and check that the "Nearsend Chat is on"
notification appears without opening the app. Also test after installing an update over the app, and after toggling Bluetooth off and on.
