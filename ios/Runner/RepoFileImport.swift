import Flutter
import Foundation

/// iOS side of "Open with Sozo" for extension repository index files.
///
/// Mirrors `RepoFileIntent.kt` on Android: a file arrives as a URL, we decide
/// whether it looks like an extension index, copy it somewhere durable, and park
/// a JSON payload for Flutter to pull over the `soplay/repo_file` channel.
///
/// The copy is not optional. Documents opened from Files/Mail/Safari arrive as
/// security-scoped URLs inside `Inbox/` or another app's container; the scope is
/// released as soon as the delegate returns, so holding the URL until the user
/// confirms an install dialog would fail. Copying into our own caches directory
/// makes the file ours for as long as we need it.
enum RepoFileImport {

  private static let queue = DispatchQueue(label: "sozo.repofile")
  private static var pending: String?

  /// Parks whatever [url] resolves to, and returns true when it was accepted.
  @discardableResult
  static func handle(url: URL) -> Bool {
    guard let payload = makePayload(url: url) else { return false }
    queue.sync { pending = payload }
    return true
  }

  /// Consume-once, so the install sheet doesn't reappear on every resume.
  static func takePending() -> String? {
    queue.sync {
      let value = pending
      pending = nil
      return value
    }
  }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "soplay/repo_file",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "takePending":
        result(takePending())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - internals

  private static func makePayload(url: URL) -> String? {
    let name = url.lastPathComponent
    guard looksLikeIndex(name: name, url: url.absoluteString) else { return nil }

    var payload: [String: Any] = [
      "kind": kind(name: name, url: url.absoluteString),
      "name": name,
    ]

    if url.scheme == "http" || url.scheme == "https" {
      // The repo managers fetch urls natively; downloading here would only
      // duplicate that (and lose their Cloudflare handling).
      payload["url"] = url.absoluteString
      return json(payload)
    }

    guard let copied = copyToCaches(url: url, name: name) else { return nil }
    payload["path"] = copied.path
    payload["size"] = (try? FileManager.default
      .attributesOfItem(atPath: copied.path)[.size] as? Int) ?? 0
    return json(payload)
  }

  /// Deliberately permissive and name-based — same reasoning as Android: a
  /// wrong guess costs one dismissed dialog, a miss costs the feature. The
  /// parse is the real validation.
  private static func looksLikeIndex(name: String, url: String) -> Bool {
    let n = (name.isEmpty ? String(url.split(separator: "/").last ?? "") : name)
      .lowercased()
    return n.hasSuffix(".pb")
      || n.hasSuffix("index.json")
      || n.hasSuffix("index.min.json")
      || n.hasSuffix("repo.json")
      || n.contains("anime_index")
      || n.contains("novel_index")
  }

  /// `index.pb` / `index.min.json` are shared by the manga and anime
  /// ecosystems and the file itself doesn't say which, so those resolve to
  /// "unknown" and the app asks the user.
  private static func kind(name: String, url: String) -> String {
    let hay = (name + " " + url).lowercased()
    if hay.contains("repo.json") { return "cloudstream" }
    if hay.contains("anime_index") || hay.contains("novel_index") { return "mangayomi" }
    if hay.contains("anime-repo") || hay.contains("aniyomi") { return "aniyomi" }
    if hay.contains("manga-repo") || hay.contains("mangayomi") { return "mangayomi" }
    if hay.contains("keiyoushi") || hay.contains("mihon") || hay.contains("tachiyomi") {
      return "manga"
    }
    return "unknown"
  }

  private static func copyToCaches(url: URL, name: String) -> URL? {
    let fm = FileManager.default
    guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
    else { return nil }
    let dir = caches.appendingPathComponent("repo_import", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let safe = name.isEmpty ? "index" : name
    let dest = dir.appendingPathComponent(safe)

    // Security-scoped access is required for documents handed over by another
    // app; it is a no-op (and returns false) for URLs we already own, so the
    // result is deliberately not treated as fatal.
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    do {
      if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
      try fm.copyItem(at: url, to: dest)
    } catch {
      // Fall back to a read+write: copyItem fails for some provider-backed URLs
      // that NSData can still read.
      guard let data = try? Data(contentsOf: url),
            (try? data.write(to: dest)) != nil
      else { return nil }
    }

    let size = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0
    return size > 0 ? dest : nil
  }

  private static func json(_ dict: [String: Any]) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}
