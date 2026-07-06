import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The app is always dark (ThemeMode.dark, background 0xFF181818). Force a
    // dark window appearance so the native title bar / traffic-light region and
    // any window chrome render dark regardless of the macOS system Light/Dark
    // setting. Also paint the window background dark to avoid a white flash
    // before Flutter's first frame.
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(
      red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x18 / 255.0, alpha: 1.0)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
