import CarPlay
import Flutter
import UIKit

/// Bieżący kurs dla CarPlay. Aplikacja podaje go kanałem „pl.table.car”, a scena samochodu go pokazuje.
/// Zapisany w UserDefaults, żeby CarPlay miał go od razu po podłączeniu telefonu.
final class CarState {
  static let shared = CarState()

  private static let key = "table_car_state"

  private(set) var state: [String: Any] = [:]
  var onChange: (() -> Void)?
  var connectionSink: FlutterEventSink?
  var connected = false {
    didSet { connectionSink?(connected ? "carplay" : "none") }
  }

  func update(_ value: [String: Any]) {
    state = value
    if let data = try? JSONSerialization.data(withJSONObject: value) {
      UserDefaults.standard.set(data, forKey: CarState.key)
    }
    onChange?()
  }

  func load() {
    guard state.isEmpty,
      let data = UserDefaults.standard.data(forKey: CarState.key),
      let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return }
    state = value
  }
}

public class TableCarPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = TableCarPlugin()
    let channel = FlutterMethodChannel(name: "pl.table.car", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    let events = FlutterEventChannel(name: "pl.table.car/connection", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ping":
      result(nil)
    case "show":
      CarState.shared.update(call.arguments as? [String: Any] ?? [:])
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    CarState.shared.connectionSink = events
    events(CarState.shared.connected ? "carplay" : "none")
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    CarState.shared.connectionSink = nil
    return nil
  }
}

/// Scena CarPlay (Info.plist: CPTemplateApplicationSceneSessionRoleApplication → TableCarSceneDelegate).
/// Bieżący kurs: adres, klient, płatność i przyciski „Nawiguj” (Mapy w aucie) oraz „Zadzwoń”.
@objc(TableCarSceneDelegate)
public class TableCarSceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?
  private weak var scene: CPTemplateApplicationScene?

  public func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    scene = templateApplicationScene
    CarState.shared.load()
    CarState.shared.connected = true
    CarState.shared.onChange = { [weak self] in
      DispatchQueue.main.async { self?.render() }
    }
    render()
  }

  public func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
    CarState.shared.connected = false
    CarState.shared.onChange = nil
  }

  private func render() {
    interfaceController?.setRootTemplate(makeTemplate(), animated: true, completion: nil)
  }

  private func text(_ value: Any?) -> String {
    (value as? String) ?? ""
  }

  private func makeTemplate() -> CPTemplate {
    let state = CarState.shared.state
    let status = text(state["status"]).isEmpty
      ? "Otwórz Table for employees na telefonie i zacznij zmianę."
      : text(state["status"])

    guard let course = state["course"] as? [String: Any] else {
      if #available(iOS 14.0, *) {
        return CPInformationTemplate(
          title: "Dostawy",
          layout: .leading,
          items: [CPInformationItem(title: "Table", detail: status)],
          actions: []
        )
      }
      return CPListTemplate(title: "Dostawy", sections: [CPListSection(items: [CPListItem(text: status, detailText: nil)])])
    }

    let number = (course["number"] as? Int) ?? 0
    let next = (state["next"] as? Int) ?? 0
    let title = "Kurs #\(number)" + (next > 0 ? " (+\(next))" : "")
    let address = text(course["address"])
    let phone = text(course["phone"]).replacingOccurrences(of: " ", with: "")
    let stage = [text(course["promised"]), text(course["stage"])].filter { !$0.isEmpty }.joined(separator: " · ")

    if #available(iOS 14.0, *) {
      var items = [
        CPInformationItem(title: "Adres", detail: address),
        CPInformationItem(title: "Klient", detail: "\(text(course["customer"])) · \(text(course["phone"]))"),
        CPInformationItem(title: "Płatność", detail: text(course["payment"])),
        CPInformationItem(title: stage.isEmpty ? "Zamówienie" : stage, detail: text(course["items"])),
      ]
      if !text(course["note"]).isEmpty {
        items.append(CPInformationItem(title: "Uwagi", detail: text(course["note"])))
      }
      let navigate = CPTextButton(title: "Nawiguj", textStyle: .confirm) { [weak self] _ in
        self?.open(self?.mapsURL(address))
      }
      let call = CPTextButton(title: "Zadzwoń", textStyle: .normal) { [weak self] _ in
        self?.open(URL(string: "tel:\(phone)"))
      }
      return CPInformationTemplate(title: title, layout: .leading, items: items, actions: [navigate, call])
    }

    // iOS 13: zwykła lista, stuknięcie adresu otwiera nawigację.
    let addressItem = CPListItem(text: address, detailText: stage)
    addressItem.handler = { [weak self] _, completion in
      self?.open(self?.mapsURL(address))
      completion()
    }
    let customer = CPListItem(text: text(course["customer"]), detailText: text(course["phone"]))
    customer.handler = { [weak self] _, completion in
      self?.open(URL(string: "tel:\(phone)"))
      completion()
    }
    let payment = CPListItem(text: text(course["payment"]), detailText: text(course["items"]))
    return CPListTemplate(title: title, sections: [CPListSection(items: [addressItem, customer, payment])])
  }

  private func mapsURL(_ address: String) -> URL? {
    var components = URLComponents()
    components.scheme = "maps"
    components.host = ""
    components.queryItems = [URLQueryItem(name: "daddr", value: address), URLQueryItem(name: "dirflg", value: "d")]
    return components.url
  }

  private func open(_ url: URL?) {
    guard let url = url, let scene = scene else { return }
    scene.open(url, options: nil, completionHandler: nil)
  }
}
