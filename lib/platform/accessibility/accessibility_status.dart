/// Live state of the Android Accessibility Service, as reported by the
/// native side. Never assume "enabled" — always ask (spec section 24: "The
/// app should detect whether required permissions are enabled").
enum AccessibilityStatus {
  enabled,
  disabled,
  unknown,
}
