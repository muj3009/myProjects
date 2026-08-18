import Flutter
import UIKit

/// Standard Flutter iOS entry point. Deliberately has no custom automation
/// method/event channels: JobFilter's iOS build never attempts cross-app
/// interaction with Uber Driver/Bolt Driver (spec section 26), so
/// `PlatformActionExecutorFactory` on the Dart side resolves straight to
/// `IosAutomationProvider` without ever invoking a native channel here.
///
/// If a legitimate, documented Uber/Bolt (or platform) integration is added
/// in the future — e.g. push-notification-based job alerts, or an official
/// driver API — its native glue belongs here, registered the same way
/// AutomationMethodChannelHandler is registered on Android. See
/// docs/ios-limitations.md.
@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
