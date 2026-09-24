import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Zwinięte menu boczne: zostają same ikony. Wybór pamiętamy na komputerze.
class SidebarCollapsedNotifier extends Notifier<bool> {
  static const _key = 'panel_menu_zwiniete';

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
      // Bez zapisu menu zaczyna rozwinięte.
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

final sidebarCollapsedProvider =
    NotifierProvider<SidebarCollapsedNotifier, bool>(
      SidebarCollapsedNotifier.new,
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

final giftCardsProvider = FutureProvider.autoDispose
    .family<List<GiftCard>, String>(
      (ref, id) => (ref..cacheFor()).watch(repositoryProvider).giftCards(id),
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
  (ref, id) => ref.watch(myPermissionsProvider(id)).value?.contains('orders') ?? false,
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
