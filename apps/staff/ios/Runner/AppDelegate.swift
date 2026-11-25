import CoreLocation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Zgoda na lokalizację dostawcy (kanał `pl.table.staff/location`), trzymana przez cały czas działania aplikacji.
  private var locationPermission: LocationPermissionChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TableLocationPermission") {
      locationPermission = LocationPermissionChannel(messenger: registrar.messenger())
    }
  }
}

/// Pytanie o zgodę na lokalizację wprost z CoreLocation (25.11.2026: na iPhonie „Zezwól na lokalizację” przez
/// wtyczkę geolocator nie pokazywało systemowego pytania). „request” pyta, gdy jeszcze nie pytano, i odpowiada
/// stanem po decyzji; „status” podaje stan teraz.
final class LocationPermissionChannel: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  private let channel: FlutterMethodChannel
  private var waiting: [FlutterResult] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "pl.table.staff/location", binaryMessenger: messenger)
    super.init()
    manager.delegate = self
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "status":
        result(Self.name(self.manager.authorizationStatus))
      case "request":
        let status = self.manager.authorizationStatus
        if status != .notDetermined {
          result(Self.name(status))
          return
        }
        self.waiting.append(result)
        self.manager.requestWhenInUseAuthorization()
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    if status == .notDetermined { return }
    let pending = waiting
    waiting.removeAll()
    for result in pending { result(Self.name(status)) }
  }

  private static func name(_ status: CLAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorizedAlways: return "always"
    case .authorizedWhenInUse: return "whenInUse"
    @unknown default: return "unknown"
    }
  }
}
