import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../app/reservation_alerts.dart';
import 'models.dart';
import 'repository.dart';

extension CacheFor on Ref {
  /// Trzyma dane jeszcze przez chwilę po zamknięciu ekranu. Powrót do zakładki
  /// pokazuje je od razu, zamiast mrugać ładowaniem i pustym stanem.
  void cacheFor([Duration duration = const Duration(minutes: 5)]) {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    onDispose(timer.cancel);
  }
}

final repositoryProvider = Provider<PanelRepository>(
  (ref) => PanelRepository(Supabase.instance.client),
);

/// Bieżąca sesja. Subskrypcja zmian logowania żyje przez cały czas działania panelu.
class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() {
    final auth = Supabase.instance.client.auth;
    final subscription = auth.onAuthStateChange.listen((event) {
      state = event.session ?? auth.currentSession;
    });
    ref.onDispose(subscription.cancel);
    return auth.currentSession;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

final userIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider.select((s) => s?.user.id)),
);

// ---------------------------------------------------------------
// Lokal
// ---------------------------------------------------------------

final restaurantsProvider = FutureProvider<List<PanelRestaurant>>((ref) {
  if (ref.watch(userIdProvider) == null) return Future.value(const []);
  return ref.watch(repositoryProvider).myRestaurants();
});

/// Lokal wybrany w panelu, zapamiętany na komputerze.
class SelectedRestaurantNotifier extends Notifier<String?> {
  static const _key = 'panel_lokal';

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final saved = await SharedPreferencesAsync().getString(_key);
      if (saved != null && state == null) state = saved;
    } catch (_) {
      // Brak zapisu: pierwszy lokal z listy.
    }
  }

  Future<void> select(String id) async {
    state = id;
    try {
      await SharedPreferencesAsync().setString(_key, id);
    } catch (_) {
      // Wybór działa do zamknięcia panelu.
    }
  }
}

final selectedRestaurantIdProvider =
    NotifierProvider<SelectedRestaurantNotifier, String?>(
      SelectedRestaurantNotifier.new,
    );

/// Wybrany lokal. Bez zapamiętanego wyboru pierwszy z listy.
final currentRestaurantProvider = Provider<PanelRestaurant?>((ref) {
  final list = ref.watch(restaurantsProvider).value ?? const [];
  if (list.isEmpty) return null;
  final id = ref.watch(selectedRestaurantIdProvider);
  for (final r in list) {
    if (r.id == id) return r;
  }
  return list.first;
});

// ---------------------------------------------------------------
// Rezerwacje
// ---------------------------------------------------------------

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class SelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(DateTime.now());

  void set(DateTime day) => state = dateOnly(day);
  void shift(int days) => state = DateTime(state.year, state.month, state.day + days);
  void today() => state = dateOnly(DateTime.now());
}

final selectedDayProvider = NotifierProvider<SelectedDayNotifier, DateTime>(
  SelectedDayNotifier.new,
);

typedef DayQuery = ({String restaurantId, DateTime day});

/// Stan na żywo: numer kolejnej zmiany rezerwacji i stan połączenia.
typedef LiveState = ({int version, LiveStatus status});

/// Rezerwacje lokalu na żywo. Jedno połączenie na lokal, niezależnie od tego,
/// ile dni jest otwartych w panelu. Boczne menu trzyma je przy życiu, więc
/// o nowej rezerwacji z aplikacji panel da znać na każdej zakładce.
class ReservationsLive extends Notifier<LiveState> {
  ReservationsLive(this.restaurantId);

  final String restaurantId;

  /// Kolejne próby ponownego połączenia. Przerwy rosną, żeby nie zasypać serwera.
  static const _retryDelays = [2, 5, 10, 20, 30];

  /// Numer próby i ostatnia wersja dla lokalu. Przeżywają ponowne połączenie,
  /// bo przy nim cały obiekt buduje się od nowa.
  static final _attempts = <String, int>{};
  static final _versions = <String, int>{};

  @override
  LiveState build() {
    // Kanał może jeszcze coś zgłosić, gdy panel już go zamyka. Wtedy nic nie zmieniamy.
    var alive = true;
    Timer? retry;
    Timer? watchdog;

    // Po zerwaniu połączenia (uśpiony komputer, chwilowy brak internetu) kanał nie zawsze
    // wraca sam. Wtedy zamykamy go i zakładamy nowy po krótkiej przerwie.
    void reconnectLater() {
      if (retry != null) return;
      final attempt = _attempts[restaurantId] ?? 0;
      final seconds = _retryDelays[attempt.clamp(0, _retryDelays.length - 1)];
      _attempts[restaurantId] = attempt + 1;
      retry = Timer(Duration(seconds: seconds), () {
        if (alive) ref.invalidateSelf();
      });
    }

    // Każde zbudowanie od nowa to nowa wersja, więc lista rezerwacji odświeży się
    // także po ponownym połączeniu i dociągnie zmiany z przerwy.
    final version = (_versions[restaurantId] ?? 0) + 1;
    _versions[restaurantId] = version;

    final stop = ref.watch(repositoryProvider).watchReservations(
      restaurantId,
      onChange: (inserted) {
        if (!alive) return;
        _versions[restaurantId] = state.version + 1;
        state = (version: state.version + 1, status: state.status);
        if (inserted != null) {
          ReservationAlerts.instance.onInserted(
            inserted,
            muted: ref.read(alertsMutedProvider),
          );
          if (inserted['source'] == 'app') ref.read(tabNewsProvider.notifier).add(TabNews.reservations);
        }
      },
      onStatus: (status) {
        if (!alive) return;
        // Po powrocie połączenia odświeżamy listę, bo zmiany z przerwy nie przyszły.
        final reconnected = state.status == LiveStatus.offline && status == LiveStatus.live;
        final next = reconnected ? state.version + 1 : state.version;
        _versions[restaurantId] = next;
        state = (version: next, status: status);
        if (status == LiveStatus.live) {
          _attempts[restaurantId] = 0;
          watchdog?.cancel();
        } else if (status == LiveStatus.offline) {
          reconnectLater();
        }
      },
    );

    // Łączenie, które trwa za długo, traktujemy jak zerwane połączenie.
    watchdog = Timer(const Duration(seconds: 20), () {
      if (alive && state.status == LiveStatus.connecting) {
        state = (version: state.version, status: LiveStatus.offline);
        reconnectLater();
      }
    });

    ref.onDispose(() {
      alive = false;
      retry?.cancel();
      watchdog?.cancel();
      stop();
    });
    return (version: version, status: LiveStatus.connecting);
  }
}

final reservationsLiveProvider = NotifierProvider.autoDispose
    .family<ReservationsLive, LiveState, String>(ReservationsLive.new);

/// Wyciszony dźwięk i powiadomienia o nowych rezerwacjach. Pamiętane na komputerze.
class AlertsMutedNotifier extends Notifier<bool> {
  static const _key = 'panel_dzwiek_wyciszony';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = await SharedPreferencesAsync().getBool(_key);
      if (saved != null) state = saved;
    } catch (_) {
      // Bez zapisu dźwięk jest włączony.
    }
  }

  Future<void> toggle() async {
    state = !state;
    try {
      await SharedPreferencesAsync().setBool(_key, state);
    } catch (_) {
      // Wybór działa do zamknięcia panelu.
    }
  }
}

final alertsMutedProvider = NotifierProvider<AlertsMutedNotifier, bool>(
  AlertsMutedNotifier.new,
);

/// Rezerwacje jednego dnia. Odświeżają się same, gdy ktoś zmieni rezerwację lokalu.
final reservationsProvider = FutureProvider.autoDispose
    .family<List<PanelReservation>, DayQuery>((ref, q) {
      ref.cacheFor();
      ref.watch(reservationsLiveProvider(q.restaurantId).select((s) => s.version));
      final repo = ref.watch(repositoryProvider);
      return repo.reservations(
        restaurantId: q.restaurantId,
        from: q.day,
        to: DateTime(q.day.year, q.day.month, q.day.day + 1),
      );
    });

// ---------------------------------------------------------------
// Sala, lokal, menu, opinie, statystyki
// ---------------------------------------------------------------

final zonesProvider = FutureProvider.autoDispose.family<List<FloorZone>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).zones(id),
);

final tablesProvider = FutureProvider.autoDispose
    .family<List<DiningTable>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).tables(id),
    );

final inventoryItemsProvider = FutureProvider.autoDispose.family<List<InventoryItem>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).inventoryItems(id),
);

final inventoryStockProvider = FutureProvider.autoDispose.family<List<InventoryStock>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).inventoryStock(id),
);

final inventoryCountsProvider = FutureProvider.autoDispose.family<List<InventoryCount>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).inventoryCounts(id),
);

final profileProvider = FutureProvider.autoDispose
    .family<RestaurantProfile, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).profile(id),
    );

final menuProvider = FutureProvider.autoDispose
    .family<List<MenuSection>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).menu(id),
    );

final reviewsProvider = FutureProvider.autoDispose
    .family<List<PanelReview>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).reviews(id),
    );

final elementsProvider = FutureProvider.autoDispose
    .family<List<FloorElement>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).elements(id),
    );

final staffProvider = FutureProvider.autoDispose
    .family<List<StaffMember>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).staff(id),
    );

typedef WeekQuery = ({String restaurantId, DateTime weekStart});

final availabilityProvider = FutureProvider.autoDispose
    .family<List<Availability>, WeekQuery>(
      (ref, q) => (ref..cacheFor()).watch(repositoryProvider).availability(
        restaurantId: q.restaurantId,
        from: q.weekStart,
        to: DateTime(q.weekStart.year, q.weekStart.month, q.weekStart.day + 7),
      ),
    );

typedef StatsQuery = ({String restaurantId, int days});

final statsProvider = FutureProvider.autoDispose
    .family<List<DayStat>, StatsQuery>(
      (ref, q) => (ref..cacheFor()).watch(repositoryProvider).stats(q.restaurantId, q.days),
    );

final occasionStatsProvider = FutureProvider.autoDispose
    .family<List<OccasionStat>, StatsQuery>(
      (ref, q) => (ref..cacheFor()).watch(repositoryProvider).occasionStats(q.restaurantId, q.days),
    );

final positionsProvider = FutureProvider.autoDispose
    .family<List<StaffPosition>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).positions(id),
    );

final exceptionsProvider = FutureProvider.autoDispose
    .family<List<OpeningException>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).exceptions(id),
    );

final staffAccountsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).staffAccounts(id),
    );

// ---------------------------------------------------------------
// Uprawnienia i zamówienia
// ---------------------------------------------------------------

/// Uprawnienia zalogowanego konta w lokalu. Kierownik i właściciel mają wszystkie,
/// obsługa te ze stanowiska, do którego przypisał ją właściciel.
final myPermissionsProvider = FutureProvider.autoDispose.family<Set<String>, String>(
  (ref, id) {
    ref.cacheFor(const Duration(minutes: 30));
    if (ref.watch(userIdProvider) == null) return Future.value(const {});
    return ref.watch(repositoryProvider).myPermissions(id);
  },
);

/// Czy zalogowane konto może nabijać zamówienia w lokalu.
final canTakeOrdersProvider = Provider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(effectivePermissionsProvider(id))?.contains('orders') ?? false,
);

/// Rachunki lokalu na żywo: numer zmiany i stan połączenia. Każda zmiana pozycji
/// na dowolnym urządzeniu (komputer, tablet) od razu odświeża ekran zamówień.
class OrdersLive extends Notifier<LiveState> {
  OrdersLive(this.restaurantId);

  final String restaurantId;

  static const _retryDelays = [2, 5, 10, 20, 30];
  static final _attempts = <String, int>{};
  static final _versions = <String, int>{};

  @override
  LiveState build() {
    var alive = true;
    Timer? retry;

    void reconnectLater() {
      if (retry != null) return;
      final attempt = _attempts[restaurantId] ?? 0;
      _attempts[restaurantId] = attempt + 1;
      retry = Timer(
        Duration(seconds: _retryDelays[attempt.clamp(0, _retryDelays.length - 1)]),
        () {
          if (alive) ref.invalidateSelf();
        },
      );
    }

    final version = (_versions[restaurantId] ?? 0) + 1;
    _versions[restaurantId] = version;

    final stop = ref.watch(repositoryProvider).watchOrders(
      restaurantId,
      onChange: () {
        if (!alive) return;
        _versions[restaurantId] = state.version + 1;
        state = (version: state.version + 1, status: state.status);
      },
      onStatus: (status) {
        if (!alive) return;
        final reconnected = state.status == LiveStatus.offline && status == LiveStatus.live;
        final next = reconnected ? state.version + 1 : state.version;
        _versions[restaurantId] = next;
        state = (version: next, status: status);
        if (status == LiveStatus.live) {
          _attempts[restaurantId] = 0;
        } else if (status == LiveStatus.offline) {
          reconnectLater();
        }
      },
    );

    final watchdog = Timer(const Duration(seconds: 20), () {
      if (alive && state.status == LiveStatus.connecting) {
        state = (version: state.version, status: LiveStatus.offline);
        reconnectLater();
      }
    });

    ref.onDispose(() {
      alive = false;
      retry?.cancel();
      watchdog.cancel();
      stop();
    });
    return (version: version, status: LiveStatus.connecting);
  }
}

final ordersLiveProvider = NotifierProvider.autoDispose
    .family<OrdersLive, LiveState, String>(OrdersLive.new);

/// Otwarte rachunki lokalu. Odświeżają się same przy każdej zmianie.
final openOrdersProvider = FutureProvider.autoDispose.family<List<PanelOrder>, String>(
  (ref, id) {
    ref.cacheFor();
    ref.watch(ordersLiveProvider(id).select((s) => s.version));
    return ref.watch(repositoryProvider).openOrders(id);
  },
);

/// Czy zalogowane konto widzi ekran kuchni.
final canUseKitchenProvider = Provider.autoDispose.family<bool, String>(
  (ref, id) => ref.watch(effectivePermissionsProvider(id))?.contains('kitchen') ?? false,
);

/// Bileciki na ekranie kuchni. Odświeżają się na żywo razem z rachunkami.
final kitchenTicketsProvider = FutureProvider.autoDispose.family<List<KitchenTicket>, String>(
  (ref, id) {
    ref.cacheFor();
    ref.watch(ordersLiveProvider(id).select((s) => s.version));
    return ref.watch(repositoryProvider).kitchenTickets(id);
  },
);

/// Pojazdy floty lokalu.
final vehiclesProvider = FutureProvider.autoDispose.family<List<Vehicle>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).vehicles(id),
);

/// Baza klientów lokalu.
final customersProvider = FutureProvider.autoDispose.family<List<Customer>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).customers(id),
);

typedef TeamStatsQuery = ({String restaurantId, TeamPeriod period});

/// Statystyki zespołu za miesiąc (pierwszy dzień miesiąca).
final teamStatsProvider = FutureProvider.autoDispose.family<List<TeamStat>, TeamStatsQuery>(
  (ref, q) => (ref..cacheFor()).watch(repositoryProvider).teamStats(q.restaurantId, q.period),
);

final teamSummaryProvider = FutureProvider.autoDispose.family<TeamSummary, TeamStatsQuery>(
  (ref, q) => (ref..cacheFor()).watch(repositoryProvider).teamSummary(q.restaurantId, q.period),
);

/// Stawki brutto za godzinę i rodzaje umów według numeru pracownika.
final staffRatesProvider = FutureProvider.autoDispose.family<Map<String, StaffRate>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).staffRates(id),
);

typedef CustomerQuery = ({String restaurantId, String key});

/// Wizyty i zamówienia wybranego klienta.
final customerHistoryProvider = FutureProvider.autoDispose.family<List<CustomerEvent>, CustomerQuery>(
  (ref, q) => ref.watch(repositoryProvider).customerHistory(q.restaurantId, q.key),
);

/// Notatki o wybranym kliencie.
final customerNotesProvider = FutureProvider.autoDispose.family<List<Note>, CustomerQuery>(
  (ref, q) => ref.watch(repositoryProvider).customerNotes(q.restaurantId, q.key),
);

/// Notatki o pojazdach lokalu według pojazdu.
final vehicleNotesProvider = FutureProvider.autoDispose.family<Map<String, List<Note>>, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).vehicleNotes(id),
);

/// Ostatnio wybrana grupa zakładek w górnym pasku (Rezerwacje, Kuchnia...). Zostaje wybrana także na stronach
/// spoza grup (Ustawienia lokalu, Dane lokalu, Edycja sali).
class PanelSectionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String section) {
    if (state != section) state = section;
  }
}

final panelSectionProvider = NotifierProvider<PanelSectionNotifier, String?>(PanelSectionNotifier.new);

/// Coś nowego w zakładce: nowa rezerwacja z aplikacji, nowe zamówienie na dostawę albo odbiór, nowe danie
/// do wydania. Kropka na ikonie zakładki i jej grupy, dopóki ktoś nie zajrzy do zakładki.
enum TabNews { reservations, deliveries, pickup, serving }

class TabNewsNotifier extends Notifier<Set<TabNews>> {
  @override
  Set<TabNews> build() => const {};

  void add(TabNews news) {
    if (!state.contains(news)) state = {...state, news};
  }

  void seen(TabNews news) {
    if (state.contains(news)) state = {...state}..remove(news);
  }
}

final tabNewsProvider = NotifierProvider<TabNewsNotifier, Set<TabNews>>(TabNewsNotifier.new);

/// Dane właściciela w „Dane lokalu”.
final ownerDetailsProvider = FutureProvider.autoDispose.family<OwnerDetails, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).ownerDetails(id),
);

/// Karty na ekranie „Kompletowanie”. Odświeżają się na żywo razem z rachunkami.
final servingTicketsProvider = FutureProvider.autoDispose.family<List<ServingTicket>, String>(
  (ref, id) {
    ref.cacheFor();
    ref.watch(ordersLiveProvider(id).select((s) => s.version));
    return ref.watch(repositoryProvider).servingTickets(id);
  },
);

/// Wyciszony dźwięk nowych dań na ekranie „Kompletowanie”. Pamiętany na komputerze.
class ServingMutedNotifier extends Notifier<bool> {
  static const _key = 'panel_wydanie_wyciszone';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = await SharedPreferencesAsync().getBool(_key);
      if (saved != null) state = saved;
    } catch (_) {
      // Bez zapisu dźwięk jest włączony.
    }
  }

  Future<void> toggle() async {
    state = !state;
    try {
      await SharedPreferencesAsync().setBool(_key, state);
    } catch (_) {
      // Wybór działa do zamknięcia panelu.
    }
  }
}

final servingMutedProvider = NotifierProvider<ServingMutedNotifier, bool>(
  ServingMutedNotifier.new,
);

/// Ekran kuchni na cały ekran, bez bocznego menu. Wyjście przyciskiem albo klawiszem Esc.
class KitchenFullscreenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> set(bool value) async {
    state = value;
    try {
      await windowManager.setFullScreen(value);
    } catch (_) {
      // Bez trybu pełnoekranowego zostaje samo ukrycie menu.
    }
  }
}

final kitchenFullscreenProvider = NotifierProvider<KitchenFullscreenNotifier, bool>(
  KitchenFullscreenNotifier.new,
);

/// Wyciszony dźwięk nowego zamówienia na kuchni. Pamiętany na komputerze.
class KitchenMutedNotifier extends Notifier<bool> {
  static const _key = 'panel_kuchnia_wyciszona';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = await SharedPreferencesAsync().getBool(_key);
      if (saved != null) state = saved;
    } catch (_) {
      // Bez zapisu dźwięk jest włączony.
    }
  }

  Future<void> toggle() async {
    state = !state;
    try {
      await SharedPreferencesAsync().setBool(_key, state);
    } catch (_) {
      // Wybór działa do zamknięcia panelu.
    }
  }
}

final kitchenMutedProvider = NotifierProvider<KitchenMutedNotifier, bool>(
  KitchenMutedNotifier.new,
);

/// Progi czasu na ekranie kuchni.
final kitchenConfigProvider = FutureProvider.autoDispose.family<KitchenConfig, String>(
  (ref, id) => (ref..cacheFor()).watch(repositoryProvider).kitchenConfig(id),
);

/// Średni czas przygotowania. Odświeża się, gdy kuchnia coś zbije.
final kitchenStatsProvider = FutureProvider.autoDispose.family<KitchenStats, String>(
  (ref, id) {
    ref.cacheFor();
    ref.watch(ordersLiveProvider(id).select((s) => s.version));
    return ref.watch(repositoryProvider).kitchenStats(id);
  },
);

/// Zamknięte rachunki jednego dnia.
/// Zamówienia na wynos: aktywne i zakończone dzisiaj. Odświeżają się na żywo razem z rachunkami.
final takeawayOrdersProvider = FutureProvider.autoDispose.family<List<TakeawayOrder>, String>(
  (ref, id) {
    ref.cacheFor();
    ref.watch(ordersLiveProvider(id).select((s) => s.version));
    final now = DateTime.now();
    return ref.watch(repositoryProvider).takeawayOrders(id, since: DateTime(now.year, now.month, now.day));
  },
);

/// Dostawcy na zmianie. Odświeżają się razem z zamówieniami (koniec kursu zwalnia dostawcę).
/// Szkice zamówień na wynos z panelu (Zamówienia), na żywo razem z rachunkami.
final takeawayDraftsProvider = FutureProvider.autoDispose.family<List<TakeawayOrder>, String>((ref, id) {
  ref.watch(ordersLiveProvider(id));
  return ref.watch(repositoryProvider).takeawayDrafts(id);
});

typedef LookupQuery = ({String restaurantId, String phone});

/// Wcześniejsze zamówienia klienta po telefonie (ostatnie 9 cyfr).
final customerLookupProvider = FutureProvider.autoDispose.family<CustomerLookup, LookupQuery>((ref, q) {
  ref.cacheFor(const Duration(minutes: 2));
  return ref.watch(repositoryProvider).customerLookup(q.restaurantId, q.phone);
});

final couriersProvider = FutureProvider.autoDispose.family<List<Courier>, String>(
  (ref, id) {
    ref.cacheFor();
    ref.watch(ordersLiveProvider(id).select((s) => s.version));
    return ref.watch(repositoryProvider).couriers(id);
  },
);

/// Kwota do zapłaty za rachunek z rabatem z kodu rezerwacji.
final orderDueProvider = FutureProvider.autoDispose.family<OrderDue, String>(
  (ref, orderId) => ref.watch(repositoryProvider).orderDue(orderId),
);

/// Kody rabatowe lokalu (Management).
final discountCodesProvider = FutureProvider.autoDispose.family<List<DiscountCode>, String>(
  (ref, restaurantId) => ref.watch(repositoryProvider).discountCodes(restaurantId),
);

/// Podsumowanie dnia w Management. Odświeża się razem z zamówieniami.
final daySummaryProvider = FutureProvider.autoDispose.family<DaySummary, DayQuery>((ref, q) {
  ref.watch(ordersLiveProvider(q.restaurantId).select((s) => s.version));
  return ref.watch(repositoryProvider).daySummary(q.restaurantId, q.day);
});

final orderHistoryProvider = FutureProvider.autoDispose.family<List<PanelOrder>, DayQuery>(
  (ref, q) {
    ref.cacheFor();
    ref.watch(ordersLiveProvider(q.restaurantId).select((s) => s.version));
    return ref.watch(repositoryProvider).orderHistory(q.restaurantId, q.day);
  },
);

// ---------------------------------------------------------------
// Pracownicy: logowanie kodem albo kodem QR, kody, grafik
// ---------------------------------------------------------------

/// Kody pracowników lokalu według numeru pracownika.
final staffCodesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).staffCodes(id),
    );

/// Tabela lokalu na żywo. Stan to wersja: każda zmiana w tabeli ją podbija, więc zależne listy pobierają dane
/// od nowa. Po zerwaniu połączenia (uśpiony komputer, brak internetu) kanał zakłada się od nowa i dociąga
/// zmiany z przerwy; na wszelki wypadek dane odświeżają się też co minutę.
abstract class TableLive extends Notifier<int> {
  TableLive(this.restaurantId);

  final String restaurantId;

  /// Tabela w bazie, np. `staff_shifts`.
  String get table;

  /// Ostatnia wersja dla tabeli i lokalu. Przeżywa ponowne połączenie (obiekt buduje się wtedy od nowa).
  static final _versions = <String, int>{};

  @override
  int build() {
    final key = '$table:$restaurantId';
    var alive = true;
    var offline = false;
    Timer? retry;

    void bump() {
      if (!alive) return;
      final next = state + 1;
      _versions[key] = next;
      state = next;
    }

    final stop = ref.watch(repositoryProvider).watchTable(
      table,
      restaurantId,
      onChange: bump,
      onLive: (live) {
        if (!alive) return;
        if (live) {
          if (offline) bump();
          offline = false;
        } else {
          offline = true;
          retry ??= Timer(const Duration(seconds: 5), () {
            if (alive) ref.invalidateSelf();
          });
        }
      },
    );
    final poll = Timer.periodic(const Duration(minutes: 1), (_) => bump());
    ref.onDispose(() {
      alive = false;
      retry?.cancel();
      poll.cancel();
      stop();
    });
    final version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    return version;
  }
}

/// Grafik na żywo: przyjęcie albo zmiana godzin w aplikacji od razu widać w panelu.
class ScheduleLive extends TableLive {
  ScheduleLive(super.restaurantId);

  @override
  String get table => 'staff_schedule';
}

final scheduleLiveProvider = NotifierProvider.autoDispose.family<ScheduleLive, int, String>(ScheduleLive.new);

final plannedShiftsProvider = FutureProvider.autoDispose.family<List<PlannedShift>, WeekQuery>((ref, q) {
  ref.cacheFor();
  ref.watch(scheduleLiveProvider(q.restaurantId));
  return ref.watch(repositoryProvider).plannedShifts(
    q.restaurantId,
    from: q.weekStart,
    to: DateTime(q.weekStart.year, q.weekStart.month, q.weekStart.day + 7),
  );
});

typedef ScheduleQuery = ({String restaurantId, DateTime from, DateTime to});

/// Grafik lokalu od [from] do [to] (bez tego dnia), na żywo.
final scheduleRangeProvider = FutureProvider.autoDispose.family<List<PlannedShift>, ScheduleQuery>((ref, q) {
  ref.cacheFor();
  ref.watch(scheduleLiveProvider(q.restaurantId));
  return ref.watch(repositoryProvider).plannedShifts(q.restaurantId, from: q.from, to: q.to);
});

/// Uwagi pracowników na tygodnie grafiku, na żywo.
final weekNotesProvider = FutureProvider.autoDispose.family<List<WeekNote>, ScheduleQuery>((ref, q) {
  ref.cacheFor();
  ref.watch(scheduleLiveProvider(q.restaurantId));
  return ref.watch(repositoryProvider).weekNotes(q.restaurantId, q.from, q.to);
});

/// Edycja grafiku: zmiany zbierają się tutaj i trafiają do bazy dopiero po „Zapisz”. Przeżywają przejście
/// do innej zakładki i automatyczne wylogowanie; gdy zaloguje się ktoś inny, znikają (`StaffScreen`).
class ScheduleDraftNotifier extends Notifier<ScheduleDraft> {
  ScheduleDraftNotifier(this.restaurantId);

  final String restaurantId;

  @override
  ScheduleDraft build() => const ScheduleDraft();

  void start(String editor) => state = ScheduleDraft(editing: true, editor: editor);

  void put(ScheduleChange change) =>
      state = ScheduleDraft(editing: true, editor: state.editor, changes: {...state.changes, change.key: change});

  void undo(String key) =>
      state = ScheduleDraft(editing: true, editor: state.editor, changes: {...state.changes}..remove(key));

  void close() => state = const ScheduleDraft();
}

final scheduleDraftProvider =
    NotifierProvider.family<ScheduleDraftNotifier, ScheduleDraft, String>(ScheduleDraftNotifier.new);

/// Statystyki pracownika za miesiąc (pierwszy dzień miesiąca).
typedef MemberStatsQuery = ({String memberId, DateTime month});

final memberStatsProvider = FutureProvider.autoDispose.family<MemberStats, MemberStatsQuery>((ref, q) {
  ref.cacheFor();
  return ref.watch(repositoryProvider).memberStats(q.memberId, q.month);
});

/// Pracownik zalogowany teraz w panelu (kodem albo kodem QR). Logowanie jest jedno dla wszystkich
/// zakładek: kto zalogował się w Rezerwacjach, jest zalogowany także w Menu. Wylogowuje przycisk,
/// zmiana lokalu i [IdleLogout] po [kIdleLogoutSeconds] sekundach bez ruchu.
class PanelMemberNotifier extends Notifier<ActingMember?> {
  @override
  ActingMember? build() {
    ref.watch(selectedRestaurantIdProvider);
    return null;
  }

  void signIn(ActingMember member) => state = member;

  void signOut() => state = null;

  /// Wylogowuje, jeśli zalogowany jest ten pracownik (np. po zakończeniu jego zmiany).
  void signOutMember(String memberId) {
    if (state?.memberId == memberId) state = null;
  }
}

final panelMemberProvider = NotifierProvider<PanelMemberNotifier, ActingMember?>(PanelMemberNotifier.new);

/// Po tylu sekundach bez ruchu myszy i klawiatury panel wylogowuje pracownika (`IdleLogout`).
const kIdleLogoutSeconds = 30;

/// Ile sekund panel stoi bez ruchu, gdy ktoś jest zalogowany. Liczy `IdleLogout`, pokazuje pasek nad zakładką.
class IdleSecondsNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) {
    if (state != value) state = value;
  }
}

final idleSecondsProvider = NotifierProvider<IdleSecondsNotifier, int>(IdleSecondsNotifier.new);

/// Uprawnienia zalogowanego pracownika: według nich zakładki pokazują przyciski.
final memberPermissionsProvider = Provider<Set<String>>(
  (ref) => ref.watch(panelMemberProvider)?.permissions ?? const {},
);

/// Uprawnienia, według których menu boczne pokazuje zakładki: zalogowanego pracownika,
/// a gdy nikt nie jest zalogowany, konta panelu (kierownik i właściciel mają wszystkie;
/// każda zakładka i tak poprosi wtedy o zalogowanie).
final effectivePermissionsProvider = Provider.autoDispose.family<Set<String>?, String>((ref, id) {
  if (ref.watch(panelMemberProvider) case final member?) return member.permissions;
  return ref.watch(myPermissionsProvider(id)).value;
});

typedef ShiftQuery = ({String restaurantId, DateTime from, DateTime to});

/// Zmiany na żywo: skan w aplikacji Table for employees i koniec zmiany od razu widać w panelu.
class ShiftsLive extends TableLive {
  ShiftsLive(super.restaurantId);

  @override
  String get table => 'staff_shifts';
}

/// Zegar dla trwających zmian: co 30 sekund, żeby czas pracy „trwa” rósł na ekranie.
final clockProvider = StreamProvider.autoDispose<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()),
);

final shiftsLiveProvider = NotifierProvider.autoDispose.family<ShiftsLive, int, String>(ShiftsLive.new);

final shiftsProvider = FutureProvider.autoDispose.family<List<StaffShift>, ShiftQuery>((ref, q) {
  ref.cacheFor();
  ref.watch(shiftsLiveProvider(q.restaurantId));
  return ref.watch(repositoryProvider).shifts(q.restaurantId, from: q.from, to: q.to);
});

final salesStatsProvider = FutureProvider.autoDispose.family<SalesStats, StatsQuery>((ref, q) {
  ref.cacheFor();
  return ref.watch(repositoryProvider).salesStats(q.restaurantId, q.days);
});
