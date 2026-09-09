import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Identifies the privacy cover so removing it cannot miss.
  private static let coverTag = 0x5EC1

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Section 9's screenshot protection
  //
  // iOS has no FLAG_SECURE: screenshots cannot be blocked at all. The only
  // exposure that can be closed is the app-switcher snapshot, and this closes
  // it by covering the window while the app is not active.
  //
  // On willResignActive, deliberately, NOT on didEnterBackground. The system
  // takes its snapshot as the app resigns active; a cover added in
  // didEnterBackground arrives after the picture has already been taken. That
  // version compiles, runs, looks right in every log, and protects nothing.
  //
  // The app lock's own authentication prompt also resigns the app active, so
  // the cover appears beneath the system sheet. That is harmless -- the sheet
  // is its own window -- and didBecomeActive removes the cover afterwards.

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    guard let window = window, window.viewWithTag(Self.coverTag) == nil else { return }

    let cover = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    cover.tag = Self.coverTag
    cover.frame = window.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(cover)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // Removed unconditionally. A cover left behind is its own lockout: the app
    // would be running normally behind a blur nothing clears.
    window?.viewWithTag(Self.coverTag)?.removeFromSuperview()
  }
}
