# Architecture

## Layering

```
presentation/   Flutter widgets/screens. Reads state via Riverpod, calls controller methods.
                Never contains £/mile math or platform calls.
        ↓
application/    Riverpod controllers (SettingsController, JobHistoryController,
                StatisticsController, AutomationController). Orchestrates domain + data +
                platform, holds no business rules itself.
        ↓
domain/         Pure Dart: entities, enums, rules, JobDecisionEngine, parsers, services.
                Zero imports from Flutter, sqflite, or platform/. Fully unit-testable without
                a device, emulator, or Flutter test binding beyond what flutter_test's `test()`
                itself needs.
        ↓
data/           SQLite (sqflite) repository implementations of the domain repository
                interfaces. The only place SQL lives.
        ↓
platform/       MethodChannel/EventChannel wrappers, PlatformActionExecutor implementations,
                the iOS capability model. The only place platform channels are touched from
                Dart.
        ↓
android/, ios/  Native Kotlin/Swift. android/ contains the Accessibility Service and
                foreground service; ios/ is a stock Flutter embedding with no automation
                channel at all (see docs/ios-limitations.md).
```

The dependency direction only ever points downward in that list — `domain/` never imports
`presentation/`, `data/` never imports `application/`, etc. `application/` is the only layer
allowed to depend on both `domain/` and `platform/` at once, because orchestrating between them
is its entire job.

## Why this split

- **Testability.** `JobDecisionEngine`, the rules, and the parsers have no Flutter/platform
  dependency, so `test/domain/*` and `test/parsers/*` run as plain Dart unit tests — no
  emulator, no mocked platform channel, no widget pump.
- **Platform isolation (spec section 2/26).** `AutomationController` is identical on Android and
  iOS; the only thing that differs is which `PlatformActionExecutor` it's given
  (`AndroidPlatformActionExecutor` vs `IosAutomationProvider`, chosen by
  `PlatformActionExecutorFactory`). No `if (Platform.isAndroid)` branches leak into
  `application/` or `presentation/` beyond that one factory.
- **Swap-ability.** `JobRepository`/`SettingsRepository` are interfaces; `data/` has the only
  sqflite-aware implementation. A future cloud-sync backend would add a second implementation,
  not touch `domain/` or `presentation/`.

## State management

Riverpod (`flutter_riverpod`), using `StateNotifierProvider` rather than the newer
code-generated `Notifier`/`@riverpod` annotations, specifically because no Flutter/Dart SDK
(and therefore no `build_runner`) was available while authoring this project — see the top-level
README's "Known limitations of this handoff". Migrating to `riverpod_generator` later is a
mechanical, low-risk change since all business logic already lives outside the
controllers themselves (in `domain/`).

## Local database

`sqflite`, two tables (`jobs`, `settings`) — see `lib/data/database/app_database.dart`. Rule
thresholds are stored as JSON inside the `settings` row specifically so adding a new rule field
later doesn't require a schema migration (spec section 41: "Design the schema so new fields can
be added later").

## Privacy (spec section 27)

- All parsing, OCR, rule evaluation, and history/statistics are computed on-device.
- Nothing here ever asks for or stores Uber/Bolt login credentials — `platform/` only ever reads
  already-visible on-screen text and, on Android, taps a UI control; it never opens a login flow
  or touches an authentication token.
- `raw_detected_text` is stored per job (for the debug screen and troubleshooting) but never
  transmitted — there is no network client in this codebase, and the debug screen
  (`presentation/screens/debug`) is only reachable in debug builds.
- `AppLogger` (spec section 36) explicitly never logs anything resembling a password, token, or
  credential — it only logs job figures (fare, distance, decision) and diagnostic strings.

## Error handling philosophy (spec section 35/51/52)

`Result<T>` (`core/utils/result.dart`) is used at every I/O boundary (database, platform
channel) instead of throwing. `JobDecisionEngine` treats missing/invalid data as `pending`
(no action), never as an implicit accept. `AutomationController._handleDetectedText` wraps the
entire detect→act pipeline in a `try/catch` so a single malformed job can never crash monitoring
— see spec section 51/52's stated priority order, reproduced here because it drove several of
these decisions:

1. Safety
2. Correct parsing
3. Correct decision
4. Platform compliance
5. Speed
