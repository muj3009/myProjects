# iOS limitations

## Why there is no iOS automation

iOS apps run in a sandbox that does not permit one app to read another app's screen contents or
send synthetic input to another app's UI, outside of narrowly scoped, user-initiated system
features (e.g. Shortcuts/App Intents that the *target* app must explicitly opt into). Uber Driver
and Bolt Driver do not currently expose such an integration. There is no private-API workaround
that is legitimate to ship — see spec sections 26/28, which this project follows:

- No reverse-engineered private Uber/Bolt APIs.
- No stolen/intercepted authentication tokens.
- No certificate-pinning bypass or traffic interception.
- No code injection into another app.

This is a deliberate platform security boundary, not a gap in effort.

## What the iOS build does instead

Everything that doesn't require reading another app's screen works identically to Android:

- Rule configuration (`RulesScreen`, `SettingsScreen`)
- The decision engine and £/mile calculation (`domain/`, entirely shared)
- **Simulation Mode** — manually enter a fare/distance/duration and see the exact rule-by-rule
  breakdown and final decision, using the same `JobDecisionEngine` the Android build uses live
- Job history and statistics, once jobs exist (from Simulation Mode, or a future integration)

## The capability model

`lib/platform/automation/ios_automation_provider.dart` defines `IosAutomationCapabilities`, a
small set of booleans (all `false` today except manual entry) that both
`AutomationController` and the UI branch on instead of checking `Platform.isIOS` directly:

```dart
class IosAutomationCapabilities {
  final bool supportsAutomaticCrossAppInteraction; // false
  final bool supportsBackgroundJobDetection;        // false
  final bool supportsManualJobEntry;                // true
  final bool supportsOfficialApiIntegration;         // false
}
```

`IosAutomationProvider implements PlatformActionExecutor` and always returns a failure explaining
why from `acceptJob()`/`rejectJob()` — there is no code path where the iOS build pretends an
accept/reject happened (spec section 48, "No fake features"). The Dashboard shows an explanatory
message (`_IosNotSupportedCard` in `dashboard_screen.dart`) instead of a non-functional START
AUTOMATION button.

## What would need to change if this changes in the future

If Uber or Bolt ship a legitimate iOS integration (a driver-facing API, a supported App
Intent/Shortcut, or push-notification-based job alerts with structured data):

1. Add a native Swift handler in `ios/Runner/` for whatever API surface that integration
   provides, following the same "one file registers the channel" pattern as
   `AutomationMethodChannelHandler.kt` on Android.
2. Flip the relevant flag(s) in `IosAutomationCapabilities`.
3. `AutomationController` and the UI need no changes — they already branch on the capability
   flags and on `PlatformActionExecutor.isAutomationSupportedOnThisPlatform`, not on a hardcoded
   assumption about which OS supports automation.

No such integration exists today, and this codebase does not claim otherwise anywhere in its UI
copy or code comments.
