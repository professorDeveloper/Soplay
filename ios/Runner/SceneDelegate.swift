import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  /// A file opened while the app is already running ("Open in Sozo" from Files,
  /// Safari, Telegram…). Parked for Flutter to pull over `soplay/repo_file`;
  /// see `RepoFileImport`.
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    var handled = false
    for context in URLContexts where RepoFileImport.handle(url: context.url) {
      handled = true
    }
    // Anything we didn't claim is a deeplink (`sozo://`, universal link) and
    // still belongs to the Flutter plugins, so always forward.
    super.scene(scene, openURLContexts: URLContexts)
    if handled {
      // Flutter polls on resume; nothing else to do here.
    }
  }

  /// Cold start: the launch options carry the URL before any Flutter code runs.
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    for context in connectionOptions.urlContexts {
      RepoFileImport.handle(url: context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
