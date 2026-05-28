import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// iOS 16+ scene-based lifecycle doesn't reliably forward Flutter's
  /// `SystemChrome.setPreferredOrientations` to the view controller, so we
  /// own the mask here. Updated from Flutter via the `app/orientation`
  /// channel; defaults to portrait so the rest of the app keeps its existing
  /// behavior.
  static var orientationLock: UIInterfaceOrientationMask = .portrait

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationLock
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppOrientation") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "app/orientation",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "set",
            let args = call.arguments as? [String: Any],
            let modes = args["modes"] as? [String] else {
        result(FlutterMethodNotImplemented)
        return
      }

      var mask: UIInterfaceOrientationMask = []
      for mode in modes {
        switch mode {
        case "portraitUp":     mask.insert(.portrait)
        case "portraitDown":   mask.insert(.portraitUpsideDown)
        // Flutter's landscape naming is mirrored vs UIKit's, so swap.
        case "landscapeLeft":  mask.insert(.landscapeRight)
        case "landscapeRight": mask.insert(.landscapeLeft)
        default: break
        }
      }
      if mask.isEmpty { mask = .portrait }
      AppDelegate.orientationLock = mask

      DispatchQueue.main.async {
        if #available(iOS 16.0, *) {
          UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
              scene.requestGeometryUpdate(
                .iOS(interfaceOrientations: mask)
              ) { _ in }
              scene.windows.forEach { window in
                window.rootViewController?
                  .setNeedsUpdateOfSupportedInterfaceOrientations()
              }
            }
        } else {
          UIViewController.attemptRotationToDeviceOrientation()
        }
        result(nil)
      }
    }
  }
}
