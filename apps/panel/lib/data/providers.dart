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

  @override
  LiveState build() {
    // Kanał może jeszcze coś zgłosić, gdy panel już go zamyka. Wtedy nic nie zmieniamy.
    var alive = true;
    final stop = ref.watch(repositoryProvider).watchReservations(
      restaurantId,
      onChange: (inserted) {
        if (!alive) return;
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
        state = (
          version: reconnected ? state.version + 1 : state.version,
          status: status,
        );
      },
    );
    ref.onDispose(() {
      alive = false;
      stop();
    });
    return (version: 0, status: LiveStatus.connecting);
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
