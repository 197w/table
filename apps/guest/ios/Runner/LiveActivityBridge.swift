import Flutter
import Foundation

#if canImport(ActivityKit)
  import ActivityKit
#endif

/// Most między Flutterem a ActivityKit. Flutter mówi, która rezerwacja jest najbliższa,
/// a tu powstaje albo znika kafel na ekranie blokady.
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
      guard #available(iOS 16.1, *) else {
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
    @available(iOS 16.1, *)
    private static func show(
      id: String,
      name: String,
      address: String,
      startsAt: Date,
      details: String
    ) -> Bool {
      // Kafel dla tej rezerwacji już wisi: tylko odświeżamy jego treść.
      for activity in Activity<TableReservationAttributes>.activities
      where activity.attributes.reservationId == id {
        Task {
          await activity.update(
            using: TableReservationAttributes.ContentState(startsAt: startsAt, details: details)
          )
        }
        return true
      }

      // Kafle innych rezerwacji nie są już aktualne.
      end(reservationId: nil)

      let attributes = TableReservationAttributes(
        restaurantName: name,
        address: address,
        reservationId: id
      )
      let state = TableReservationAttributes.ContentState(startsAt: startsAt, details: details)

      do {
        if #available(iOS 16.2, *) {
          // Kafel znika godzinę po godzinie rezerwacji.
          _ = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: startsAt.addingTimeInterval(3600)),
            pushType: nil
          )
        } else {
          _ = try Activity.request(attributes: attributes, contentState: state)
        }
        return true
      } catch {
        return false
      }
    }

    @available(iOS 16.1, *)
    private static func end(reservationId: String?) {
      for activity in Activity<TableReservationAttributes>.activities {
        if let reservationId, activity.attributes.reservationId != reservationId { continue }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
      }
    }
  #endif
}
