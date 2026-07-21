import Flutter
import UIKit

// MARK: - Native glass platform view (UIVisualEffectView)

private enum NativeGlassStyleMapper {
  static func blurStyle(sigma: Double, isDark: Bool) -> UIBlurEffect.Style {
    if isDark {
      if sigma >= 28 { return .systemChromeMaterialDark }
      if sigma >= 20 { return .systemMaterialDark }
      return .systemThinMaterialDark
    }
    if sigma >= 28 { return .systemChromeMaterial }
    if sigma >= 20 { return .systemMaterial }
    return .systemThinMaterial
  }
}

final class NativeGlassPlatformView: NSObject, FlutterPlatformView {
  private let blurContainer: UIVisualEffectView

  init(frame: CGRect, params: [String: Any]?) {
    let sigma = params?["sigma"] as? Double ?? 30.0
    let isDark = params?["isDark"] as? Bool ?? false
    let style = NativeGlassStyleMapper.blurStyle(sigma: sigma, isDark: isDark)
    let effect = UIBlurEffect(style: style)
    blurContainer = UIVisualEffectView(effect: effect)
    blurContainer.frame = frame
    blurContainer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurContainer.isUserInteractionEnabled = false
    super.init()
  }

  func view() -> UIView {
    blurContainer
  }
}

final class NativeGlassViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let params = args as? [String: Any]
    return NativeGlassPlatformView(frame: frame, params: params)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

enum NativeGlassRegistrar {
  static func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "NativeGlassPlugin") else {
      return
    }
    let factory = NativeGlassViewFactory()
    registrar.register(factory, withId: "tieba_app/native_glass")
  }
}
