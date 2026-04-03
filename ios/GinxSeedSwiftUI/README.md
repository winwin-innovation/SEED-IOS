# GinxSeed SwiftUI

This folder now contains a full native SwiftUI iOS app scaffold for Lucy realtime.

## What it includes

- Secure token fetch from your existing Node backend
- Decart realtime session setup with `lucy_2_rt`
- Front camera capture
- Prompt updates while connected
- Reference image upload for Lucy 2 character transforms
- Local and remote WebRTC video rendering in SwiftUI

## Xcode setup

1. Start the Node backend from the project root with `npm run server`.
2. Find your computer's LAN IP, for example `192.168.1.25`.
3. Open `ios/GinxSeedSwiftUI/GinxSeedSwiftUI.xcodeproj` in Xcode.
4. Let Xcode resolve the Swift package dependency for `decart-ios`.
5. Set your Apple signing team and, if needed, change the bundle identifier.
6. In the app target's `Info` tab, replace `GINXBackendBaseURL` with your machine's LAN URL, for example:

```swift
http://192.168.1.25:8787
```

7. Optionally adjust `GINXDefaultPrompt` or disable `GINXAutoConnectOnLaunch`.
8. Build and run on a physical iPhone on the same network as your computer.

## Notes

- Run on a real iPhone or iPad.
- Keep your permanent Decart secret key on the Node server only.
- The iOS app should consume the short-lived token returned by `POST /api/realtime-token`.
- `Info.plist` already includes camera/photo permissions and relaxed ATS for local development over HTTP.
- The in-app "Check Backend" button hits `GET /api/health` so you can verify LAN connectivity before starting a session.
