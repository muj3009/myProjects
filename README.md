# JobFilter

JobFilter is a driver assistant that evaluates incoming taxi/private-hire jobs against
driver-defined rules (£ per mile, pickup distance, minimum fare, hourly rate, and more) and —
where the operating system legitimately allows it — automatically accepts or rejects them in
supported third-party driver apps (Uber Driver, Bolt Driver).

The app name shown in the UI is configurable (Settings → App name); "JobFilter" is just the
default.

## Why Android and iOS behave differently

**This is intentional, not a missing feature.** Android's Accessibility Service APIs allow an
app — with the driver's explicit, revocable permission — to read on-screen text and interact
with another app's visible UI. iOS's app sandboxing model has no equivalent, and JobFilter does
not attempt to bypass it. Concretely:

| Capability | Android | iOS |
|---|---|---|
| Rule engine, £/mile calculation | ✅ | ✅ |
| Job history, statistics | ✅ | ✅ |
| Simulation / manual job analysis | ✅ | ✅ |
| Automatic job detection (reading Uber/Bolt's screen) | ✅ (Accessibility Service) | ❌ not possible under iOS sandboxing |
| Automatic accept/reject (tapping Uber/Bolt's buttons) | ✅ (Accessibility Service) | ❌ not possible under iOS sandboxing |

See [docs/ios-limitations.md](docs/ios-limitations.md) for the full explanation and what would
have to change (an official platform integration) for this to differ.

## Project structure

```
lib/
  core/            constants, Result/Failure types, logging, theme
  domain/          entities, enums, rules, decision engine, parsers — pure Dart, no Flutter/platform imports
  data/            sqflite database + repository implementations
  application/     Riverpod state + AutomationController (orchestration)
  presentation/    screens and widgets
  platform/        method-channel bridges, PlatformActionExecutor, iOS capability model
android/           Kotlin Accessibility Service, foreground service, method channel handler
ios/               Swift AppDelegate (no automation channel — see above)
test/              unit tests (domain, parsers, application)
docs/              architecture and design notes
```

See [docs/architecture.md](docs/architecture.md) for the full layering rationale.

## Getting started

This was authored without a local Flutter SDK available, so the Android/iOS native
scaffolding was hand-written to match current Flutter conventions rather than generated. Before
running:

```powershell
flutter pub get
flutter create --platforms=android,ios .   # fills in gradlew, Xcode project files, Generated.xcconfig
```

`flutter create .` will offer to overwrite a few files it considers "its own" (app icons,
possibly `AndroidManifest.xml`/`Info.plist` if it detects no existing content) — decline
overwrites for anything under `android/app/src/main/kotlin`, `android/app/src/main/AndroidManifest.xml`,
`ios/Runner/AppDelegate.swift`, and `ios/Runner/Info.plist`; those are hand-authored for this
project. See `ios/XCODE_PROJECT_NOTE.md` and `android/app/src/main/res/mipmap-placeholder/README.txt`
for the specific gaps (Xcode project file, launcher icon PNGs) that only Flutter/Xcode tooling
can safely generate.

### Run

```powershell
flutter run                 # Android device/emulator or iOS simulator/device
```

### Test

```powershell
flutter test
```

Tests never touch a real Uber/Bolt account or a real device's Accessibility Service — see
`test/application/automation_controller_test.dart`, which drives the whole
detect → parse → decide → act pipeline with fabricated text and mocked platform channels.

## Android setup (on a real device)

1. Install the app and open **Settings → Permissions & setup**.
2. Grant **Accessibility access** — this is what lets JobFilter read job offer text from Uber
   Driver / Bolt Driver. JobFilter's Accessibility Service is scoped (see
   `android/app/src/main/res/xml/accessibility_service_config.xml`) to only the two supported
   apps' packages; it cannot see any other app.
3. Optionally allow **unrestricted battery usage** so monitoring isn't paused by the OS.
4. Choose your platform(s) and minimum £/mile in **Settings**/**Rules**.
5. Press **START AUTOMATION** on the Dashboard.

The persistent notification while automation is active is required by Android for any
long-running foreground service — see [docs/android-automation.md](docs/android-automation.md).

## iOS setup

No special permissions are required. Use **Simulation Mode** to test the rule engine against
hypothetical jobs, and **Settings/Rules** to configure thresholds — those apply automatically if
an official platform integration is ever added.

## Building

### Android APK / AAB

```powershell
flutter build apk --release      # release/app-release.apk, debug-signed by default (see below)
flutter build appbundle --release
```

The default `android/app/build.gradle` release build is **debug-signed** so it builds out of the
box for local testing. Before shipping:

1. `keytool -genkey -v -keystore jobfilter-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias jobfilter`
2. Copy `android/key.properties.example` to `android/key.properties` and fill in the values.
3. Wire a real `signingConfigs.release` block in `android/app/build.gradle` reading from
   `key.properties`, and point `buildTypes.release.signingConfig` at it instead of `signingConfigs.debug`.

### iOS

```powershell
flutter build ios --release
```

Then archive/sign via Xcode as usual (`open ios/Runner.xcworkspace` after running
`flutter create --platforms=ios .` and `pod install`, per `ios/XCODE_PROJECT_NOTE.md`).

## Permissions required (Android)

| Permission | Why |
|---|---|
| Accessibility Service | Read job offer text and (only after all safety checks pass) tap Accept/Reject in supported driver apps |
| `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_SPECIAL_USE` | Keep monitoring alive while the driver's screen is off |
| `POST_NOTIFICATIONS` | Show the required persistent "automation active" notification |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (optional) | Avoid Android pausing monitoring in the background |

JobFilter never requests Uber/Bolt login credentials, camera, microphone, location, contacts, or
SMS permissions — see [docs/architecture.md](docs/architecture.md) "Privacy".

## Known limitations of this handoff

- **No Flutter SDK was available while writing this code**, so `flutter analyze`/`flutter
  test`/a real build were not run here. The Android/iOS native project files follow current
  Flutter embedding conventions but should be verified with `flutter doctor` and a real build
  on your machine as the first step.
- App launcher icons and `android/app/*/Runner.xcodeproj` are generated/binary artifacts not
  included — see the notes above.
- The Uber/Bolt on-screen text parsers (`UberJobParser`, `BoltJobParser`) use best-effort
  keyword heuristics documented in [docs/parser-design.md](docs/parser-design.md); neither
  driver app's UI text is publicly documented, so these should be tuned against real devices
  before relying on them for real money.
- OCR fallback (`OcrTextProvider`) and the Accessibility Service's screenshot capture are wired
  end-to-end but the `InputImageMetadata` size populated by the native screenshot call should be
  verified against the actual device resolution — see the code comment in
  `lib/platform/ocr/ocr_text_provider.dart`.

## Testing checklist

- [ ] `£10 / 5 miles` → `£2.00/mile` → ACCEPT at a £2.00 minimum
- [ ] `£1.99` effective rate → REJECT at a £2.00 minimum; `£2.00` exactly → ACCEPT
- [ ] Missing fare or missing distance → NO ACTION (never auto-accept on unknown data)
- [ ] Same job detected twice in a row → processed once (`JobFingerprintService`)
- [ ] STOP AUTOMATION → monitoring and further actions stop immediately
- [ ] Changing minimum £/mile in Settings immediately affects the next simulated/live job
- [ ] Simulation Mode shows fare, distance, £/mile, each rule's PASS/FAIL/UNKNOWN, and the
      final decision for a manually entered job
- [ ] Permissions screen correctly reflects whether the Accessibility Service is enabled
- [ ] iOS build never shows an automation toggle that claims to work — see
      `IosAutomationProvider`/`IosAutomationCapabilities`
- [ ] Revoking the Accessibility Service permission mid-session is reflected next time
      automation is started (does not crash)
