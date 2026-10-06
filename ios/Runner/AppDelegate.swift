import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let privacyCover = PrivacyCover()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    privacyCover.install()
    // Lets flutter_local_notifications decide how a reminder that arrives
    // while the app is open is presented.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PeriodWidgetBridge") {
      WidgetBridge.install(messenger: registrar.messenger())
    }
  }
}

/// Hands the home-screen widget the little it may show.
///
/// The widget runs as its own process and cannot open the encrypted database,
/// so the app writes a small snapshot for it -- the last period start and how
/// to label the day -- into a Keychain group the two share. The Keychain, not
/// a shared file: it is encrypted, where an App Group container is not.
/// Nothing else of hers is ever written there.
enum WidgetBridge {
  static let service = "app.period.widget"
  static let account = "snapshot"

  static func install(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "period/widget", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "update":
        guard let json = call.arguments as? String else {
          result(FlutterError(code: "bad_args", message: nil, details: nil))
          return
        }
        result(write(Data(json.utf8)))
      case "clear":
        result(write(nil))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Replaces the snapshot (or removes it, for nil) and asks WidgetKit to
  /// redraw. True on success.
  static func write(_ data: Data?) -> Bool {
    guard let group = sharedGroup() else { return false }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: group,
    ]
    SecItemDelete(query as CFDictionary)
    var ok = true
    if let data = data {
      var add = query
      add[kSecValueData as String] = data
      // Readable by the widget after the first unlock since restart, so it can
      // redraw at midnight while the phone is locked -- and never before.
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    WidgetCenter.shared.reloadAllTimelines()
    return ok
  }

  static func sharedGroup() -> String? {
    guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String
    else { return nil }
    return prefix + "app.period.shared"
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
