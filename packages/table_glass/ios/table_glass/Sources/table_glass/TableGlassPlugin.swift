import Flutter
import UIKit

/// Natywne szklane przyciski (Liquid Glass, iOS 26) w oknie aplikacji, NAD widokiem Fluttera.
///
/// To nie są widoki platformy Fluttera (UiKitView): Flutter o nich nie wie, nie składa ich z treścią i nie
/// przechwytuje dotyku. Natywny widok platformy w oknie od dołu blokował na iPhonie całe okno (9.11.2026, kilka
/// razy), a tu przycisk to zwykły UIButton w UIWindow obok widoku Fluttera: dotyk w jego polu trafia do niego,
/// reszta ekranu do Fluttera jak zawsze. Położenie (w punktach widoku Fluttera) podaje strona Dart, gdy okno stoi
/// w miejscu; w ruchu przycisk jest schowany, a Flutter rysuje w tym miejscu swoje szkło.
public class TableGlassPlugin: NSObject, FlutterPlugin {
  private var channel: FlutterMethodChannel?
  private var buttons: [Int: UIButton] = [:]
  private weak var flutterView: UIView?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TableGlassPlugin()
    let channel = FlutterMethodChannel(name: "pl.table.glass", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "show":
      result(show(args))
    case "hide":
      if let id = args["id"] as? Int, let button = buttons[id] {
        hide(button)
      }
      result(nil)
    case "remove":
      if let id = args["id"] as? Int {
        buttons.removeValue(forKey: id)?.removeFromSuperview()
      }
      result(nil)
    case "reset":
      // Po ponownym uruchomieniu Darta (hot restart) zostają przyciski z poprzedniego uruchomienia.
      for button in buttons.values {
        button.removeFromSuperview()
      }
      buttons.removeAll()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Pokazuje przycisk w podanym miejscu. False: nie da się (starszy iOS albo brak widoku Fluttera w oknie),
  /// wtedy Flutter zostaje przy swoim szkle.
  private func show(_ args: [String: Any]) -> Bool {
    guard #available(iOS 26.0, *) else { return false }
    guard let id = args["id"] as? Int,
      let view = findFlutterView(),
      let window = view.window
    else { return false }
    let x = args["x"] as? Double ?? 0
    let y = args["y"] as? Double ?? 0
    let width = args["width"] as? Double ?? 44
    let height = args["height"] as? Double ?? 44

    let button = buttons[id] ?? makeButton(id)
    configure(button, args)
    if button.superview !== window {
      window.addSubview(button)
    }
    window.bringSubviewToFront(button)
    button.frame = view.convert(CGRect(x: x, y: y, width: width, height: height), to: window)
    button.isUserInteractionEnabled = true
    if button.alpha < 1 {
      UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
        button.alpha = 1
      }
    }
    return true
  }

  private func hide(_ button: UIButton) {
    button.layer.removeAllAnimations()
    button.alpha = 0
    button.isUserInteractionEnabled = false
  }

  private func makeButton(_ id: Int) -> UIButton {
    let button = UIButton(type: .system)
    button.alpha = 0
    // Czytnik ekranu dostaje przycisk od Fluttera (ten sam napis i działanie), bez drugiego natywnego.
    button.isAccessibilityElement = false
    button.accessibilityElementsHidden = true
    button.tag = id
    button.addTarget(self, action: #selector(pressed(_:)), for: .touchUpInside)
    buttons[id] = button
    return button
  }

  @objc private func pressed(_ button: UIButton) {
    // Okno zaraz zjedzie w dół: przycisk chowa się od razu, a nie dopiero przy następnej klatce Fluttera.
    hide(button)
    channel?.invokeMethod("pressed", arguments: button.tag)
  }

  @available(iOS 26.0, *)
  private func configure(_ button: UIButton, _ args: [String: Any]) {
    var config = UIButton.Configuration.glass()
    let symbol = args["symbol"] as? String ?? "xmark"
    let pointSize = CGFloat(args["symbolSize"] as? Double ?? 19)
    config.image = UIImage(
      systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize))
    config.cornerStyle = .capsule
    config.contentInsets = .zero
    if let argb = args["color"] as? Int {
      config.baseForegroundColor = Self.color(argb)
    }
    button.configuration = config
    button.overrideUserInterfaceStyle = (args["dark"] as? Bool ?? false) ? .dark : .light
  }

  private static func color(_ argb: Int) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }

  /// Widok Fluttera w oknie aplikacji (główny kontroler albo jego dziecko).
  private func findFlutterView() -> UIView? {
    if let view = flutterView, view.window != nil {
      return view
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let controller = Self.flutterController(window.rootViewController) {
          flutterView = controller.view
          return controller.view
        }
      }
    }
    return nil
  }

  private static func flutterController(_ controller: UIViewController?) -> FlutterViewController? {
    guard let controller = controller else { return nil }
    if let flutter = controller as? FlutterViewController {
      return flutter
    }
    for child in controller.children {
      if let flutter = flutterController(child) {
        return flutter
      }
    }
    return nil
  }
}
