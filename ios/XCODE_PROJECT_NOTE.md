# About this ios/ directory

This directory was hand-authored (no Flutter/Xcode tooling was available in
the environment that generated it) and intentionally does **not** include
`Runner.xcodeproj/project.pbxproj` or `Runner.xcworkspace` — those are
generated, highly tool-specific files that are unsafe to hand-write; a
malformed one silently breaks in Xcode with confusing errors.

What's here is everything Xcode-independent: `AppDelegate.swift`,
`Info.plist`, storyboards, the `Podfile`, and the `Flutter/*.xcconfig` files
that reference Flutter's own `Generated.xcconfig`.

**Before opening this in Xcode or running `flutter build ios`, run once from
the project root:**

```powershell
flutter create --platforms=ios .
```

This generates `Runner.xcodeproj`/`Runner.xcworkspace` and `Generated.xcconfig`
without touching your other files. Flutter's scaffolder will offer to
overwrite `AppDelegate.swift`/`Info.plist`/the storyboards with its own
defaults — decline, or re-apply this directory's versions afterward, so the
`JobFilter` bundle name/display name and the doc comments explaining why
there's no automation channel here are preserved. Then `cd ios && pod install`.
