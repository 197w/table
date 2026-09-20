import Foundation

#if canImport(ActivityKit)
  import ActivityKit

  /// Dane kafla rezerwacji na ekranie blokady.
  /// Ten plik należy do obu celów: aplikacji i rozszerzenia z widżetem.
  @available(iOS 16.2, *)
  struct TableReservationAttributes: ActivityAttributes {
    /// Część, która może się zmieniać w trakcie trwania kafla.
    struct ContentState: Codable, Hashable {
      /// Godzina rezerwacji.
      var startsAt: Date

      /// Dodatkowy wiersz, na przykład „4 osoby · stolik 12”. Może być pusty.
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
