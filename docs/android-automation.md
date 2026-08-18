# Android automation

## Components

- `android/app/src/main/kotlin/com/jobfilter/app/automation/JobAccessibilityService.kt` — the
  Accessibility Service. Scoped via `accessibility_service_config.xml`'s `packageNames` to only
  `com.ubercab.driver` (Uber Driver) and `ee.mtakso.driver` (Bolt Driver); the OS never delivers
  events from any other app to this service.
- `AutomationForegroundService.kt` — the foreground service required to keep monitoring alive
  while the driver's screen is off, with the persistent notification Android mandates.
- `AutomationMethodChannelHandler.kt` — the only file that registers/handles the
  `com.jobfilter.app/automation` method channel and its two event channels. Mirrors
  `lib/platform/automation/automation_method_channel.dart` on the Dart side.
- `AutomationBridge.kt` — a small static bridge so the Accessibility Service and the foreground
  service (which Android creates/destroys independently) can each push events to Flutter without
  holding a reference to each other.

## Why event-driven, not polling (spec section 45)

`JobAccessibilityService.onAccessibilityEvent` only fires when Android's accessibility framework
detects a relevant change (`typeWindowStateChanged`/`typeWindowContentChanged`) in one of the two
monitored packages. There is no timer, no `Handler.postDelayed` loop, and no continuous screen
capture. This keeps CPU/battery usage close to zero while the driver app is idle, and means
detection latency is bounded by how fast Android delivers the event, not by a polling interval.

## Screen text extraction priority (spec section 9)

1. **Accessibility node tree** (`JobAccessibilityService.extractText`) — walks
   `rootInActiveWindow`, concatenating `text`/`contentDescription` from every node up to a depth
   guard (40) to avoid pathological trees. Cheapest and most reliable; no image processing.
2. **Structured notification** (`NotificationTextProvider`, Dart-only today) — extension point
   for if a driver app ever posts machine-readable job data in a notification. Currently always
   reports unavailable rather than guessing at a schema that doesn't exist.
3. **OCR** (`OcrTextProvider` + `JobAccessibilityService.captureScreenshot`) — only reached when
   1 and 2 both fail. Requires API 30+ (`AccessibilityService.takeScreenshot`); on older devices
   this fallback is simply unavailable and the method channel returns `null`. Runs Google ML Kit
   text recognition on-device (`google_mlkit_text_recognition`) — no image ever leaves the device.

## Safety checks executed natively (spec section 15)

`JobAccessibilityService.findAndClickButtonByKeywords` is the only method that performs a click.
It:

1. Re-reads `rootInActiveWindow` at call time (not a cached tree from when the job was first
   detected), so a stale reference can't cause a click on a screen that has since changed.
2. Searches for a node whose text/content-description contains one of the caller-supplied
   keywords (`"accept"` or `"reject"/"decline"/"no thanks"`), then walks up to the nearest
   clickable ancestor — job-card buttons are often a clickable container around a text label, not
   a clickable label itself.
3. Returns `false` (never throws, never guesses) if no confident match exists.

The remaining safety checks from spec section 15 (correct platform, job actually parsed, decision
is final, not a duplicate, automation still enabled) are enforced in
`AutomationController._handleDetectedText` on the Dart side, before the native tap is ever
requested — see `docs/decision-engine.md`.

## Known fragile points (spec section 59)

These are isolated behind interfaces/keyword lists specifically so they can be tuned without
touching the safety-critical control flow around them:

- `UberJobParser`/`BoltJobParser`'s keyword lists (`_jobCardKeywords`, `_pickupKeywords`,
  `_tripKeywords`) are best-effort guesses, not derived from real device captures — see
  `docs/parser-design.md`.
- `ACCEPT_KEYWORDS`/`REJECT_KEYWORDS` in `AutomationMethodChannelHandler.kt` likewise.
- `AccessibilityNodeInfo.recycle()` is deprecated on newer Android versions (nodes are now
  reference-counted automatically) but kept for correctness back to `minSdk 26`.

None of these being imperfect can cause an incorrect *accept* — worst case, a genuine job offer
is missed (safe failure mode), consistent with spec section 51: "A wrong ACCEPT is more dangerous
than a missed job."

## Foreground service notification

Required by Android for any service that keeps running with the app backgrounded. Shows "JobFilter
— Automation is active, monitoring supported driver apps" with a STOP action that round-trips
through `AutomationBridge`/the control event channel to `AutomationController.stop()` — the exact
same code path as the in-app STOP AUTOMATION button, so there is only one emergency-stop
implementation to reason about.
