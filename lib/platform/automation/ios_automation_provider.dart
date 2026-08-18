import '../../core/utils/result.dart';
import '../../domain/enums/platform_type.dart';
import 'platform_action_executor.dart';

/// Declares exactly what JobFilter can and cannot do on iOS (spec section 26).
///
/// iOS sandboxing means there is no supported way for one app to read another
/// app's screen or press its buttons. This is not a missing feature to be
/// worked around — it is a deliberate platform security boundary, and
/// JobFilter does not attempt to bypass it (spec sections 26/28).
///
/// Every flag defaults to what is true today. If Uber or Bolt ever ship an
/// official iOS integration (e.g. a driver-facing API or App Intents-based
/// hook), only this class needs to change — [AutomationController] and the
/// UI already branch on these flags rather than on `Platform.isIOS` directly.
class IosAutomationCapabilities {
  const IosAutomationCapabilities({
    this.supportsAutomaticCrossAppInteraction = false,
    this.supportsBackgroundJobDetection = false,
    this.supportsManualJobEntry = true,
    this.supportsOfficialApiIntegration = false,
  });

  /// Whether JobFilter can automatically read a job card from, or press a
  /// button inside, Uber Driver/Bolt Driver. Always false unless a legitimate
  /// supported mechanism exists — see docs/ios-limitations.md.
  final bool supportsAutomaticCrossAppInteraction;

  /// Whether JobFilter can detect a job while it is not the foreground app.
  /// iOS does not allow arbitrary background screen inspection.
  final bool supportsBackgroundJobDetection;

  /// Manual entry (Simulation Mode / "Analyze this job") is always available
  /// — it's just local calculation, no cross-app access required.
  final bool supportsManualJobEntry;

  /// Set to true only once a real, documented Uber/Bolt API is integrated
  /// (spec section 26). Never set based on assumption.
  final bool supportsOfficialApiIntegration;

  static const current = IosAutomationCapabilities();
}

/// iOS's [PlatformActionExecutor]. Always reports automation as unsupported;
/// this is intentional and matches [IosAutomationCapabilities.current] — see
/// spec section 48, "No fake features": there is deliberately no code path
/// on iOS that pretends to accept/reject a job automatically.
class IosAutomationProvider implements PlatformActionExecutor {
  const IosAutomationProvider({
    this.capabilities = IosAutomationCapabilities.current,
  });

  final IosAutomationCapabilities capabilities;

  static const String unavailableMessage =
      'Automatic cross-app interaction is currently unavailable on iPhone. '
      'Manual analysis and supported integrations are available instead.';

  static const _delegate = UnsupportedPlatformActionExecutor(unavailableMessage);

  @override
  bool get isAutomationSupportedOnThisPlatform => capabilities.supportsAutomaticCrossAppInteraction;

  @override
  Future<bool> canPerformActions() async => capabilities.supportsAutomaticCrossAppInteraction;

  @override
  Future<Result<void>> acceptJob({required PlatformType platform, String? cardAnchor}) =>
      _delegate.acceptJob(platform: platform);

  @override
  Future<Result<void>> rejectJob({required PlatformType platform, String? cardAnchor}) =>
      _delegate.rejectJob(platform: platform);

  @override
  Future<Result<void>> counterOfferJob({required PlatformType platform, String? cardAnchor}) =>
      _delegate.counterOfferJob(platform: platform);
}
