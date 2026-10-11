# Android and iOS builds

Pinned runtime: Godot 4.5.1 standard. Build workflows deliberately share one `client` project and one pack schema. They download the matching engine and export templates on the runner.

## Android

The workflow installs JDK 17, Android platform/build tools 35, configures SDK paths, enables Internet permission, and exports arm64 with Godot's standard APK template. No Gradle custom plugins are needed. The debug APK can be sideloaded. Release AAB/store signing will need a permanent keystore and separate release preset.

## iOS

The default macOS job exports the Xcode project, then builds with `CODE_SIGNING_ALLOWED=NO` for the device SDK. It uploads the Xcode files and unsigned IPA. The placeholder team ID only enables project generation; configure the real `IOS_TEAM_ID` repository variable before signing. Change the bundle ID in `client/export_presets.cfg` to an ID belonging to your account.

Optional signing uses a manual workflow run with `sign_ios` enabled. Configure:

| Repository setting | Purpose |
| --- | --- |
| Variable `IOS_TEAM_ID` | Your 10-character Apple team ID |
| Secret `IOS_P12_BASE64` | Base64 of signing certificate + private key exported as .p12 |
| Secret `IOS_P12_PASSWORD` | Password for that .p12 |
| Secret `IOS_PROFILE_BASE64` | Base64 of provisioning profile for this bundle ID |
| Variable `IOS_SIGNING_IDENTITY` | For example `Apple Development` or `Apple Distribution` |

Choose an export method matching the certificate/profile: `debugging` for development, `release-testing` for ad hoc, or `app-store-connect` for a store distribution archive. Device testing profiles must contain the device UDIDs. The workflow packages the signed IPA but does not upload to TestFlight or submit to a store.

Apple account credentials and certificates are not provided in this project. Hosted gameplay/server/download tests, Android APK export, and unsigned iOS device compilation passed on 2026-10-11 in [run 38164007103](https://github.com/IveBeenAl0ne/literal-mobile-slop/actions/runs/38164007103). Credentialed iOS signing and phone-device testing have not been verified.

Sources checked during implementation:
- https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_android.html
- https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_ios.html
- https://docs.godotengine.org/en/4.5/classes/class_editorexportplatformios.html
