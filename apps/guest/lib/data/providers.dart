import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/location.dart';
import 'models.dart';
import 'repository.dart';

final repositoryProvider = Provider<Repository>(
  (ref) => Repository(Supabase.instance.client),
);

/// Bieżąca sesja gościa.
/// Subskrypcja zmian logowania żyje przez cały czas działania aplikacji. Riverpod wstrzymuje
/// odczyty w ekranach zasłoniętych innym ekranem, więc gdyby sesję trzymał StreamProvider,
/// ekran pod logowaniem mógłby nie zauważyć zalogowania aż do restartu.
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

/// Identyfikator zalogowanego gościa. Nie zmienia się przy odświeżeniu tokenu,
/// więc dane konta nie pobierają się ponownie co godzinę.
final userIdProvider = Provider<String?>(
  (ref) => ref.watch(sessionProvider.select((session) => session?.user.id)),
);

/// Null, gdy lokalizacja jest wyłączona albo gość nie wyraził zgody.
final locationProvider = FutureProvider<GuestLocation?>(
  (ref) => LocationService.current(),
);

final citiesProvider = FutureProvider<List<City>>(
  (ref) => ref.watch(repositoryProvider).cities(),
);

// ---------------------------------------------------------------
// Odkrywanie
// ---------------------------------------------------------------

enum DiscoverSort {
  ranking('Najlepsza kuchnia'),
  distance('Najbliżej');

  const DiscoverSort(this.label);
  final String label;
}

class DiscoverFilter {
  const DiscoverFilter({
    this.city,
    this.cuisine,
    this.sort = DiscoverSort.ranking,
  });

  /// Miasto wybrane przez gościa. Null oznacza „W pobliżu”.
  final String? city;
  final String? cuisine;
  final DiscoverSort sort;
}

class DiscoverFilterNotifier extends Notifier<DiscoverFilter> {
  @override
  DiscoverFilter build() => const DiscoverFilter();

  /// Zmiana miasta czyści kuchnię, bo w nowym mieście może jej nie być.
  void setCity(String? city) =>
      state = DiscoverFilter(city: city, sort: state.sort);

  void setCuisine(String? cuisine) => state = DiscoverFilter(
    city: state.city,
    cuisine: cuisine,
    sort: state.sort,
  );

  void setSort(DiscoverSort sort) => state = DiscoverFilter(
    city: state.city,
    cuisine: state.cuisine,
    sort: sort,
  );
}

final discoverFilterProvider =
    NotifierProvider<DiscoverFilterNotifier, DiscoverFilter>(
      DiscoverFilterNotifier.new,
    );

/// Miasto, którego lokale widzi gość. Null oznacza lokale w promieniu 10 km od gościa.
/// Bez lokalizacji wybieramy miasto z największą liczbą lokali.
final effectiveCityProvider = Provider<String?>((ref) {
  final filter = ref.watch(discoverFilterProvider);
  if (filter.city != null) return filter.city;
  final location = ref.watch(locationProvider);
  if (!location.hasValue || location.value != null) return null;
  final cities = ref.watch(citiesProvider).value ?? const <City>[];
  return cities.isEmpty ? null : cities.first.name;
});

final cuisineRowsProvider = FutureProvider<List<CuisineRow>>(
  (ref) => ref.watch(repositoryProvider).cuisineRows(),
);

/// Kuchnie dostępne w oglądanym mieście, z liczbą lokali.
final cuisinesProvider = Provider<List<({String slug, int count})>>((ref) {
  final rows = ref.watch(cuisineRowsProvider).value ?? const <CuisineRow>[];
  final city = ref.watch(effectiveCityProvider);
  final counts = <String, int>{};
  for (final row in rows) {
    if (city == null || row.city == city) {
      counts[row.cuisine] = (counts[row.cuisine] ?? 0) + 1;
    }
  }
  final list = [for (final e in counts.entries) (slug: e.key, count: e.value)]
    ..sort((a, b) => cuisineLabel(a.slug).compareTo(cuisineLabel(b.slug)));
  return list;
});

/// Fraza wpisana w wyszukiwarce. Pusta oznacza zwykłą listę lokali w pobliżu.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value.trim();
}

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final searchResultsProvider = FutureProvider<List<RestaurantSummary>>((
  ref,
) async {
  final query = ref.watch(searchQueryProvider);
  final filter = ref.watch(discoverFilterProvider);
  final repository = ref.watch(repositoryProvider);
  final locationFuture = ref.watch(locationProvider.future);
  final citiesFuture = ref.watch(citiesProvider.future);

  final location = await locationFuture;
  final cities = await citiesFuture;

  final cityName =
      filter.city ??
      (location == null && cities.isNotEmpty ? cities.first.name : null);
  City? city;
  for (final c in cities) {
    if (c.name == cityName) city = c;
  }

  final lat = location?.lat ?? city?.lat;
  final lng = location?.lng ?? city?.lng;
  if (lat == null || lng == null) return const [];

  return repository.search(
    lat: lat,
    lng: lng,
    // Z wpisaną frazą szukamy w całym kraju, więc miasto nie zawęża wyników.
    city: query.isEmpty ? city?.name : null,
    cuisine: filter.cuisine,
    sort: filter.sort.name,
    query: query.isEmpty ? null : query,
  );
});

// ---------------------------------------------------------------
// Lokal
// ---------------------------------------------------------------

final restaurantProvider = FutureProvider.autoDispose
    .family<RestaurantDetail, String>(
      (ref, id) => ref.watch(repositoryProvider).restaurant(id),
    );

final reviewsProvider = FutureProvider.autoDispose.family<List<Review>, String>(
  (ref, id) {
    // Po zalogowaniu opinie oznaczają te napisane przez gościa.
    ref.watch(userIdProvider);
    return ref.watch(repositoryProvider).reviews(id);
  },
);

typedef SlotQuery = ({String restaurantId, DateTime date, int partySize});

final slotsProvider = FutureProvider.autoDispose
    .family<List<DateTime>, SlotQuery>(
      (ref, q) => ref
          .watch(repositoryProvider)
          .availableSlots(
            restaurantId: q.restaurantId,
            date: q.date,
            partySize: q.partySize,
          ),
    );

// ---------------------------------------------------------------
// Konto gościa
// ---------------------------------------------------------------

final myReservationsProvider = FutureProvider.autoDispose<List<Reservation>>((
  ref,
) {
  if (ref.watch(userIdProvider) == null) return Future.value(const []);
  return ref.watch(repositoryProvider).myReservations();
});

final myReviewedReservationsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) {
  if (ref.watch(userIdProvider) == null) return Future.value(const {});
  return ref.watch(repositoryProvider).myReviewedReservations();
});

final reservationDetailProvider = FutureProvider.autoDispose
    .family<ReservationDetail?, String>((ref, id) {
      if (ref.watch(userIdProvider) == null) return Future.value(null);
      return ref.watch(repositoryProvider).reservationDetail(id);
    });

final profileProvider = FutureProvider.autoDispose<Profile?>((ref) {
  if (ref.watch(userIdProvider) == null) return Future.value(null);
  return ref.watch(repositoryProvider).myProfile();
});

final notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences?>((ref) {
      if (ref.watch(userIdProvider) == null) return Future.value(null);
      return ref.watch(repositoryProvider).notificationPreferences();
    });

