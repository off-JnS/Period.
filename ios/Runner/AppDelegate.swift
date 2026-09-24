import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let privacyCover = PrivacyCover()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    privacyCover.install()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Blurs the app whenever it stops being the active app.
///
/// CLAUDE.md section 9: the snapshot iOS keeps for the app switcher must not
/// show her cycle. iOS takes that snapshot as the app leaves the foreground,
/// so the cover goes on the moment the scene deactivates -- before Flutter
/// could reliably draw a frame of its own -- and comes off when it is active
/// again. The same cover also hides the screen behind Control Center and the
/// Face ID prompt.
///
/// Driven by UIScene notifications rather than by overriding scene delegate
/// methods: FlutterSceneDelegate implements those privately, and overriding
/// them from Swift would replace Flutter's own lifecycle handling.
final class PrivacyCover {
  private var covers: [ObjectIdentifier: UIView] = [:]

  func install() {
    let center = NotificationCenter.default
    center.addObserver(
      forName: UIScene.willDeactivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let scene = note.object as? UIWindowScene else { return }
      self?.cover(scene)
    }
    center.addObserver(
      forName: UIScene.didActivateNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let scene = note.object as? UIWindowScene else { return }
      self?.uncover(scene)
    }
  }

  private func cover(_ scene: UIWindowScene) {
    let key = ObjectIdentifier(scene)
    guard covers[key] == nil,
      let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
    else { return }

    // Thick material: at this strength the ring's day number and the card
    // text are unreadable, while the screen still reads as this app.
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    blur.frame = window.bounds
    blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blur.isUserInteractionEnabled = false
    window.addSubview(blur)
    covers[key] = blur
  }

  private func uncover(_ scene: UIWindowScene) {
    covers.removeValue(forKey: ObjectIdentifier(scene))?.removeFromSuperview()
  }
}
