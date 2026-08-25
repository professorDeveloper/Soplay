import Flutter
import UIKit

/// Native iOS 26 "Liquid Glass" for the bottom navigation bar.
///
/// ## Why this exists
///
/// Nothing in the Flutter stack can produce real Liquid Glass. Flutter's
/// `CupertinoTabBar` is still `DecoratedBox` + `BackdropFilter`, the shipped
/// engine binary carries no `UIGlassEffect` symbols, and the
/// `liquid_glass_widgets` package the Android bar uses is pure Dart + GLSL with
/// no iOS side at all. On iOS the app was *emulating* a material the system
/// already provides — an approximation that can never quite match, paid for
/// with a shader.
///
/// ## The selection indicator is native too
///
/// A first pass drew the bar natively and the selected-tab pill in Flutter on
/// top. That misses the point of the material. Liquid Glass is not a texture;
/// its defining behaviour is that two glass shapes *merge and separate like
/// liquid* as they approach — which is exactly what a selection indicator
/// sliding along a bar should do. A flat Flutter rectangle laid over the glass
/// can never do that, and next to real glass it reads as a sticker.
///
/// So both are glass here: the bar and the indicator are sibling
/// `UIGlassEffect` views inside a `UIGlassContainerEffect`, which is the API
/// whose whole job is to make sibling glass merge. Flutter only says *where*
/// the selection is — including fractionally, mid-drag — and UIKit does the
/// morph.
///
/// ## Why every class is looked up by name
///
/// `UIGlassEffect` and `UIGlassContainerEffect` exist only in the iOS 26 SDK,
/// so naming them directly would make the whole Runner target fail to compile
/// on any older Xcode, including a CI image that has not been updated.
/// `NSClassFromString` keeps this file building against every SDK and simply
/// reports "unsupported" where the classes are absent.
///
/// That runtime lookup is also the only *correct* way to answer the capability
/// question. A Dart-side `Platform.operatingSystemVersion >= 26` check would
/// say yes on an iOS 26 device running a binary built with an older SDK, where
/// the classes do not exist — precisely the case that would ship a broken bar.
enum LiquidGlass {
  static let channelName = "soplay/liquid_glass"
  static let viewType = "soplay/liquid_glass_view"

  static var isAvailable: Bool { glassEffectClass() != nil }

  static func glassEffectClass() -> NSObject.Type? {
    guard #available(iOS 26.0, *) else { return nil }
    return NSClassFromString("UIGlassEffect") as? NSObject.Type
  }

  static func containerEffectClass() -> NSObject.Type? {
    guard #available(iOS 26.0, *) else { return nil }
    return NSClassFromString("UIGlassContainerEffect") as? NSObject.Type
  }

  /// A `UIGlassEffect`, or nil where the class is unavailable.
  ///
  /// No tint is applied. `tintColor` recolours the material rather than washing
  /// over it, so feeding it an app accent produces a flat coloured slab and
  /// discards the effect — which defeats the entire reason for being here. The
  /// accent belongs on the Flutter icons drawn above.
  static func makeGlass(interactive: Bool) -> UIVisualEffect? {
    guard let cls = glassEffectClass(),
          let effect = cls.init() as? UIVisualEffect else { return nil }
    // KVC for the same reason the class is looked up by name: the property does
    // not exist in older SDKs, and an unknown key would raise.
    if effect.responds(to: NSSelectorFromString("setInteractive:")) {
      effect.setValue(interactive, forKey: "interactive")
    }
    return effect
  }

  /// A `UIGlassContainerEffect` — the thing that makes sibling glass merge.
  static func makeContainer() -> UIVisualEffect? {
    guard let cls = containerEffectClass() else { return nil }
    return cls.init() as? UIVisualEffect
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(isAvailable)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    registrar.register(
      LiquidGlassViewFactory(messenger: registrar.messenger()),
      withId: viewType
    )
  }
}

final class LiquidGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    LiquidGlassPlatformView(
      frame: frame,
      viewId: viewId,
      args: args as? [String: Any],
      messenger: messenger
    )
  }
}

/// The bar and its selection indicator, both real glass.
///
/// Flutter draws the icons and labels above this and owns the gestures; UIKit
/// owns the material and the morph. Keeping the tab row on the Flutter side
/// means the semantics, hit targets and the Shorts coach-mark stay one
/// implementation shared with Android — only what is behind them differs.
final class LiquidGlassBarView: UIView {
  private let containerView: UIVisualEffectView
  private let barView: UIVisualEffectView
  private let indicatorView: UIVisualEffectView

  private var tabCount: Int
  /// Selected tab, fractional while a finger is dragging along the bar.
  private var selection: CGFloat
  private var cornerRadius: CGFloat

  init(frame: CGRect, tabCount: Int, cornerRadius: CGFloat, interactive: Bool) {
    self.tabCount = max(tabCount, 1)
    self.selection = 0
    self.cornerRadius = cornerRadius

    containerView = UIVisualEffectView(effect: LiquidGlass.makeContainer())
    barView = UIVisualEffectView(effect: LiquidGlass.makeGlass(interactive: interactive))
    indicatorView = UIVisualEffectView(effect: LiquidGlass.makeGlass(interactive: interactive))

    super.init(frame: frame)

    backgroundColor = .clear
    // The bar is decoration; every touch belongs to the Flutter widgets above.
    isUserInteractionEnabled = false
    for v in [containerView, barView, indicatorView] {
      v.isUserInteractionEnabled = false
    }

    barView.layer.cornerRadius = cornerRadius
    barView.layer.cornerCurve = .continuous
    barView.clipsToBounds = true

    indicatorView.layer.cornerCurve = .continuous
    indicatorView.clipsToBounds = true

    // Nil effects mean the classes were missing — the Dart layer believed iOS
    // 26 was available but the binary was built against an older SDK. Rather
    // than a transparent hole where the bar should be, fall back to plain dark
    // pads, which is what the app's "solid" style looks like anyway.
    if barView.effect == nil {
      barView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
      indicatorView.backgroundColor = UIColor.white.withAlphaComponent(0.12)
    }

    // Both glass views are siblings inside the container's content view. That
    // is what the container effect operates on: as the indicator slides toward
    // an edge it fuses with the bar instead of sliding over it.
    addSubview(containerView)
    containerView.contentView.addSubview(barView)
    containerView.contentView.addSubview(indicatorView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func update(tabCount: Int, selection: CGFloat, animated: Bool) {
    self.tabCount = max(tabCount, 1)
    self.selection = selection
    guard animated else {
      // Mid-drag: the indicator must sit under the finger, not chase it.
      indicatorView.frame = indicatorFrame()
      return
    }
    // Spring, not a curve. The settle after release is where the material gets
    // to look like liquid rather than like a moving rectangle.
    UIView.animate(
      withDuration: 0.42,
      delay: 0,
      usingSpringWithDamping: 0.78,
      initialSpringVelocity: 0.4,
      options: [.allowUserInteraction, .beginFromCurrentState]
    ) {
      self.indicatorView.frame = self.indicatorFrame()
    }
  }

  private func indicatorFrame() -> CGRect {
    let slot = bounds.width / CGFloat(tabCount)
    let inset: CGFloat = 6
    return CGRect(
      x: selection * slot + inset,
      y: 8,
      width: max(slot - inset * 2, 0),
      height: max(bounds.height - 16, 0)
    )
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    containerView.frame = bounds
    barView.frame = bounds
    barView.layer.cornerRadius = cornerRadius
    indicatorView.frame = indicatorFrame()
    indicatorView.layer.cornerRadius = max(indicatorView.bounds.height / 2, 0)
  }
}

final class LiquidGlassPlatformView: NSObject, FlutterPlatformView {
  private let barView: LiquidGlassBarView
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    args: [String: Any]?,
    messenger: FlutterBinaryMessenger
  ) {
    let count = (args?["tabCount"] as? NSNumber)?.intValue ?? 5
    let radius = (args?["cornerRadius"] as? NSNumber)?.doubleValue ?? 31.0
    let interactive = (args?["interactive"] as? NSNumber)?.boolValue ?? true

    barView = LiquidGlassBarView(
      frame: frame,
      tabCount: count,
      cornerRadius: CGFloat(radius),
      interactive: interactive
    )
    // Per-view channel: the selection has to reach *this* bar, and a shared
    // channel would break the moment a second one existed.
    channel = FlutterMethodChannel(
      name: "\(LiquidGlass.viewType)_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "setSelection" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let a = call.arguments as? [String: Any]
      let selection = (a?["selection"] as? NSNumber)?.doubleValue ?? 0
      let count = (a?["tabCount"] as? NSNumber)?.intValue ?? 5
      let animated = (a?["animated"] as? NSNumber)?.boolValue ?? true
      self.barView.update(
        tabCount: count,
        selection: CGFloat(selection),
        animated: animated
      )
      result(nil)
    }

    let selection = (args?["selection"] as? NSNumber)?.doubleValue ?? 0
    barView.update(tabCount: count, selection: CGFloat(selection), animated: false)
  }

  func view() -> UIView { barView }
}
