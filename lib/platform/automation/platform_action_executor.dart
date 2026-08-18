import '../../core/errors/failures.dart';
import '../../core/utils/result.dart';
import '../../domain/enums/platform_type.dart';

/// The only interface through which the app is allowed to interact with a
/// third-party driver app (spec section 39/49). [AutomationController] never
/// calls native code directly — it only ever calls through this interface,
/// which keeps the safety checks in one place and makes the automation path
/// fully mockable for tests (spec section 39).
abstract interface class PlatformActionExecutor {
  /// Static platform capability, independent of runtime permission state:
  /// true on Android (even before the Accessibility Service is enabled),
  /// false on iOS and any other platform. [AutomationController] uses this —
  /// not a raw `Platform.isAndroid` check — to decide whether the automation
  /// UI should be offered at all, which keeps that decision testable with an
  /// injected fake executor instead of depending on the OS the tests happen
  /// to run on.
  bool get isAutomationSupportedOnThisPlatform;

  /// Whether automation can actually run right now (e.g. false on Android
  /// until the Accessibility Service is connected). Checked by the caller
  /// *before* accept/reject — this method must never have side effects.
  Future<bool> canPerformActions();

  /// Presses (or, on Bolt, swipes) the driver app's Accept control for the
  /// job currently on screen. Implementations MUST re-verify the visible job
  /// still matches before acting on anything (spec section 15) and must
  /// return a failure rather than guess if that verification fails.
  ///
  /// [platform] selects how the control is found: Bolt's card must be
  /// opened via [cardAnchor] (e.g. a pickup address, unique per job) before
  /// its Accept button can be tapped, since more than one offer can be
  /// visible at once. Uber shows one offer at a time and its whole card —
  /// accept button included — is a real clickable node in the accessibility
  /// tree with no card to open first (confirmed on a real device via
  /// `uiautomator dump`), so [cardAnchor] is ignored for it.
  Future<Result<void>> acceptJob({required PlatformType platform, String? cardAnchor});

  /// Presses (or swipes) the driver app's Reject/Decline control, or — on
  /// platforms/UIs where no explicit reject action exists — simply takes no
  /// action (a missing action is not an error). See [acceptJob] for
  /// [platform] and [cardAnchor].
  Future<Result<void>> rejectJob({required PlatformType platform, String? cardAnchor});

  /// Bolt-only: opens the job's "Change price" counter-offer flow and taps
  /// the highest suggested amount, sending it to the customer instead of
  /// rejecting a near-miss £/mile job outright (see CounterOfferConfig).
  /// [cardAnchor] behaves exactly as in [acceptJob]. No equivalent exists on
  /// Uber — callers must never invoke this for [PlatformType.uber].
  Future<Result<void>> counterOfferJob({required PlatformType platform, String? cardAnchor});
}

/// Executor used whenever the current platform cannot legitimately perform
/// automated UI interaction (iOS, or Android before setup is complete). Used
/// instead of leaving the executor null so callers never need a separate
/// "is this supported" branch before calling accept/reject — see spec
/// section 48 ("No fake features").
class UnsupportedPlatformActionExecutor implements PlatformActionExecutor {
  const UnsupportedPlatformActionExecutor(this.reason);

  final String reason;

  @override
  bool get isAutomationSupportedOnThisPlatform => false;

  @override
  Future<bool> canPerformActions() async => false;

  @override
  Future<Result<void>> acceptJob({required PlatformType platform, String? cardAnchor}) async =>
      Result.err(AutomationFailure(reason));

  @override
  Future<Result<void>> rejectJob({required PlatformType platform, String? cardAnchor}) async =>
      Result.err(AutomationFailure(reason));

  @override
  Future<Result<void>> counterOfferJob({required PlatformType platform, String? cardAnchor}) async =>
      Result.err(AutomationFailure(reason));
}
