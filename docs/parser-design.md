# Parser design

## Interface

`domain/parsers/job_parser.dart` defines one method:

```dart
abstract interface class JobParser {
  PlatformType get platform;
  ParsedJobData parse(String rawText);
}
```

`UberJobParser` and `BoltJobParser` each implement it independently — Uber and Bolt's driver
apps are not assumed to use the same wording or layout (spec section 8/20), so there is
deliberately no shared base class encoding "the" job-card format. What they do share is the
generic, platform-agnostic text extraction in `parsed_text_utils.dart` (currency parsing,
distance-unit parsing, km→miles conversion, duration parsing) — that logic has nothing to do with
either app's specific UI wording, so duplicating it would just be two copies of the same regex.

## What's real vs. best-effort

The **extraction mechanics** (currency formats, distance units, km→mile conversion, duration
parsing) are implemented against the concrete formats the spec calls for and are covered by
`test/parsers/parsed_text_utils_test.dart` with exact expected values.

The **keyword lists** each parser uses to (a) decide whether a job card is present at all
(`_jobCardKeywords`) and (b) tell pickup distance apart from trip distance
(`_pickupKeywords`/`_tripKeywords`) are best-effort placeholders. Neither Uber Driver's nor Bolt
Driver's on-screen wording is publicly documented, and it can change without notice (spec section
29). These lists are the thing to revise first after capturing real on-device Accessibility
Service output — see `docs/android-automation.md`.

## Never guess (spec section 8)

`ParsedTextUtils.extractFare` only recognizes amounts with an explicit currency marker (`£12.50`,
`12.50 GBP`, `GBP 12.50`). A bare number is never treated as a fare — that's exactly the
ambiguity that would otherwise confuse a distance figure ("12.5" in "12.5 miles") for money.
If no currency-marked amount is found, `fare` is `null`, and `JobDecisionEngine` treats a null
fare as `pending` (no auto-accept), never as zero or as a guess.

## Pickup vs. trip distance (spec section 12/38)

`ParsedTextUtils.extractAllDistances` returns every distance token found, with its position in
the string. Each parser then looks at up to 20 characters immediately before each match for
pickup-related (`"pickup"`, `"to rider"`, `"collect"`) or trip-related (`"trip"`, `"drop"`,
`"journey"`, etc.) keywords to label it. If exactly one distance is found with no usable label,
it's assumed to be the trip distance (matches the common single-distance job card shown in the
product spec's main example). If two are found with no clear single label, they're assumed to be
`[pickup, trip]` in that order. Both fallbacks are called out in code comments as fragile —
see `docs/android-automation.md` "Known fragile points".

## Adding a third platform

1. Add the platform to `PlatformType` (`domain/enums/platform_type.dart`), including its Android
   package name.
2. Add `com.jobfilter.app` `accessibility_service_config.xml`'s `packageNames` and
   `MonitoredPackages.kt`'s `ANDROID_PACKAGE_NAMES`.
3. Implement `JobParser` for it.
4. Register it in `jobParsersProvider` (`application/state/providers.dart`).

`JobDecisionEngine`, the rules, the database schema, and every screen already operate on
`PlatformType` generically and need no changes.
