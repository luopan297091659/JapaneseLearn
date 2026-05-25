import Flutter
import UIKit
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "kotabi/word_widget",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        switch call.method {
        case "updateWordWidget":
          guard let payload = call.arguments as? [String: Any] else {
            result(FlutterError(code: "bad_args", message: "Missing widget payload", details: nil))
            return
          }
          let defaults = UserDefaults(suiteName: "group.com.kotabi.app")
          payload.forEach { key, value in
            if value is NSNull {
              defaults?.removeObject(forKey: key)
            } else {
              defaults?.set(value, forKey: key)
            }
          }
          defaults?.synchronize()
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: "KotabiWordWidget")
          }
          result(nil)
        case "consumePendingDeepLink":
          let link = UserDefaults.standard.string(forKey: "kotabi_pending_deep_link")
          UserDefaults.standard.removeObject(forKey: "kotabi_pending_deep_link")
          result(link)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    UserDefaults.standard.set(url.absoluteString, forKey: "kotabi_pending_deep_link")
    NotificationCenter.default.post(
      name: Notification.Name("KotabiDeepLinkReceived"),
      object: url.absoluteString
    )
    return true
  }
}
