import Flutter
import UIKit

#if canImport(ActivityKit)
  import ActivityKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityBridge") {
      LiveActivityBridge.register(with: registrar)
    }
  }
}

#if canImport(ActivityKit)
  /// Dane kafla rezerwacji na ekranie blokady.
  /// Rozszerzenie z widżetem ma własną, identyczną kopię tego typu:
  /// to osobny moduł, a ActivityKit dopasowuje je po nazwie i kształcie.
  /// Zmieniasz tu cokolwiek, zmień też ios/TableActivityWidget/TableReservationAttributes.swift.
  @available(iOS 16.2, *)
  struct TableReservationAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
      /// Godzina rezerwacji.
      var startsAt: Date

      /// Dodatkowy wiersz, na przykład „4 osoby”. Może być pusty.
      var details: String
    }

    /// Nazwa lokalu, po lewej stronie kafla.
    var restaurantName: String

    /// Adres używany przez przycisk „Nawiguj”.
    var address: String

    /// Identyfikator rezerwacji, żeby zakończyć właściwy kafel.
    var reservationId: String
  }
#endif

/// Most między Flutterem a ActivityKit. Flutter mówi, która rezerwacja jest najbliższa,
/// a tu powstaje albo znika kafel na ekranie blokady.
///
/// Kod siedzi w AppDelegate.swift celowo: ten plik jest już w celu Runner, więc
/// projekt buduje się bez dokładania czegokolwiek w Xcode. Kafel pokaże się dopiero,
/// gdy powstanie rozszerzenie z widżetem, a do tego potrzebne jest płatne konto Apple.
enum LiveActivityBridge {
  static let channelName = "pl.table.app/live_activity"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      handle(call: call, result: result)
    }
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    #if canImport(ActivityKit)
      // Cały most wymaga iOS 16.2: wcześniejsze wersje mają inne, przestarzałe API
      // kafli i nie znają daty ważności. Na starszym systemie aplikacja działa bez kafla.
      guard #available(iOS 16.2, *) else {
        result(false)
        return
      }
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        result(false)
        return
      }

      switch call.method {
      case "show":
        guard let args = call.arguments as? [String: Any],
          let id = args["reservationId"] as? String,
          let name = args["restaurantName"] as? String,
          let address = args["address"] as? String,
          let startsAtMs = args["startsAtMs"] as? NSNumber
        else {
          result(false)
          return
        }
        let details = args["details"] as? String ?? ""
        let startsAt = Date(timeIntervalSince1970: startsAtMs.doubleValue / 1000)
        result(show(id: id, name: name, address: address, startsAt: startsAt, details: details))

      case "end":
        let id = (call.arguments as? [String: Any])?["reservationId"] as? String
        end(reservationId: id)
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    #else
      result(false)
    #endif
  }

  #if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private static func show(
      id: String,
      name: String,
      address: String,
      startsAt: Date,
      details: String
    ) -> Bool {
      let state = TableReservationAttributes.ContentState(startsAt: startsAt, details: details)
      // Kafel znika godzinę po godzinie rezerwacji.
      let content = ActivityContent(state: state, staleDate: startsAt.addingTimeInterval(3600))

      // Kafel dla tej rezerwacji już wisi: tylko odświeżamy jego treść.
      for activity in Activity<TableReservationAttributes>.activities
      where activity.attributes.reservationId == id {
        Task { await activity.update(content) }
        return true
      }

      // Kafle innych rezerwacji nie są już aktualne.
      end(reservationId: nil)

      let attributes = TableReservationAttributes(
        restaurantName: name,
        address: address,
        reservationId: id
      )

      do {
        _ = try Activity.request(
          attributes: attributes,
          content: content,
          pushType: nil
        )
        return true
      } catch {
        return false
      }
    }

    @available(iOS 16.2, *)
    private static func end(reservationId: String?) {
      for activity in Activity<TableReservationAttributes>.activities {
        if let reservationId, activity.attributes.reservationId != reservationId { continue }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
      }
    }
  #endif
}
