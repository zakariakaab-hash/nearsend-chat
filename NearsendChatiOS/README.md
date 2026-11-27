# Nearsend Chat for iPhone

SwiftUI app, iOS 17+, CoreBluetooth and CryptoKit, no third-party dependencies. Version 1.0, build 10 in App Store Connect.
Overview, features and limits: [`../NEARSEND_CHAT.md`](../NEARSEND_CHAT.md).

- `Sources/Mesh/` Bluetooth link (`BLETransport`), relay and store-and-forward (`MeshRouter`), encryption (`MeshCrypto`),
  app state (`MeshService`, the `ChatStore`), framing (`Framing`), debug log (`NLog`).
- `Sources/Views/` screens; `Sources/DesignSystem/` theme and battery saver; `Tests/main.swift` protocol tests (77 checks).
- Translations come from `../i18n/translations.txt` (`python3 ../i18n/generate.py`); never edit `*.lproj` by hand.

Run in the simulator (shows demo data; the simulator has no Bluetooth):

    xcodegen generate   # only after changing project.yml; the .pbxproj is also edited by hand
    open NearsendChat.xcodeproj

Release steps: [`../docs/nearsend-chat/RELEASING.md`](../docs/nearsend-chat/RELEASING.md).
