/// Supported (or selectable) third-party driver applications. Kept as an enum
/// rather than a free string so parser/integration lookups stay exhaustive-checked.
enum PlatformType {
  uber,
  bolt,
  unknown,
}

extension PlatformTypeX on PlatformType {
  String get displayName => switch (this) {
        PlatformType.uber => 'Uber',
        PlatformType.bolt => 'Bolt',
        PlatformType.unknown => 'Unknown',
      };

  /// Android package name of the driver app, used to identify which
  /// foreground application the Accessibility Service is currently looking at.
  /// See docs/android-automation.md — these are the official public package
  /// identifiers for the driver apps, not anything reverse engineered.
  String? get androidPackageName => switch (this) {
        PlatformType.uber => 'com.ubercab.driver',
        PlatformType.bolt => 'ee.mtakso.driver',
        PlatformType.unknown => null,
      };
}

/// Which platforms the driver has enabled automation for (spec section 20).
enum PlatformSelection { uber, bolt, both }

extension PlatformSelectionX on PlatformSelection {
  bool allows(PlatformType type) => switch (this) {
        PlatformSelection.uber => type == PlatformType.uber,
        PlatformSelection.bolt => type == PlatformType.bolt,
        PlatformSelection.both => type == PlatformType.uber || type == PlatformType.bolt,
      };
}
