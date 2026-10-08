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
  /// Najlepsze dopasowanie na górze, dalej ranking kuchni.
  recommended('Polecane'),
  ranking('Najlepsza kuchnia'),
  distance('Najbliżej');

  const DiscoverSort(this.label);
  final String label;

  /// Kolejność z bazy (`search_restaurants`).
  String get db => this == distance ? 'distance' : 'ranking';
}

const _keep = Object();

class DiscoverFilter {
  const DiscoverFilter({
    this.city,
    this.cuisine,
    this.sort = DiscoverSort.recommended,
    this.prices = const {},
    this.minRating,
    this.bookable = false,
    this.orderOnline = false,
    this.delivery = false,
    this.pickup = false,
    this.maxKm,
  });

  /// Miasto wybrane przez gościa. Null oznacza „W pobliżu”.
  final String? city;
  final String? cuisine;
  final DiscoverSort sort;

  /// Poziomy cen (1–4). Puste: wszystkie.
  final Set<int> prices;

  /// Najniższa ocena kuchni ze zweryfikowanych opinii.
  final double? minRating;

  /// Rezerwacja w aplikacji (plan Pro).
  final bool bookable;

  /// Zamówienie w aplikacji: dostawa albo odbiór.
  final bool orderOnline;
  final bool delivery;
  final bool pickup;

  /// Najdalej tyle kilometrów od gościa (tylko z włączoną lokalizacją).
  final int? maxKm;

  /// Ile filtrów z okna „Filtry” jest włączonych. Miasto, kuchnia i sortowanie mają własne przyciski.
  int get extraCount =>
      (prices.isEmpty ? 0 : 1) +
      (minRating == null ? 0 : 1) +
      (bookable ? 1 : 0) +
      (orderOnline ? 1 : 0) +
      (delivery ? 1 : 0) +
      (pickup ? 1 : 0) +
      (maxKm == null ? 0 : 1);

  DiscoverFilter copyWith({
    Object? city = _keep,
    Object? cuisine = _keep,
    DiscoverSort? sort,
    Set<int>? prices,
    Object? minRating = _keep,
    bool? bookable,
    bool? orderOnline,
    bool? delivery,
    bool? pickup,
    Object? maxKm = _keep,
  }) => DiscoverFilter(
    city: identical(city, _keep) ? this.city : city as String?,
    cuisine: identical(cuisine, _keep) ? this.cuisine : cuisine as String?,
    sort: sort ?? this.sort,
    prices: prices ?? this.prices,
    minRating: identical(minRating, _keep) ? this.minRating : minRating as double?,
    bookable: bookable ?? this.bookable,
    orderOnline: orderOnline ?? this.orderOnline,
    delivery: delivery ?? this.delivery,
    pickup: pickup ?? this.pickup,
    maxKm: identical(maxKm, _keep) ? this.maxKm : maxKm as int?,
  );

  /// Bez filtrów z okna „Filtry” (miasto, kuchnia i sortowanie zostają).
  DiscoverFilter withoutExtras() => DiscoverFilter(city: city, cuisine: cuisine, sort: sort);
}

class DiscoverFilterNotifier extends Notifier<DiscoverFilter> {
  @override
  DiscoverFilter build() => const DiscoverFilter();

  /// Zmiana miasta czyści kuchnię, bo w nowym mieście może jej nie być.
  void setCity(String? city) => state = state.copyWith(city: city, cuisine: null);

  void setCuisine(String? cuisine) => state = state.copyWith(cuisine: cuisine);

  void setSort(DiscoverSort sort) => state = state.copyWith(sort: sort);

  void set(DiscoverFilter filter) => state = filter;
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
  // Baza dostaje tylko miasto, kuchnię i kolejność. Reszta filtrów działa na gotowej liście, bez nowego zapytania.
  final filter = ref.watch(
    discoverFilterProvider.select((f) => (city: f.city, cuisine: f.cuisine, sort: f.sort.db)),
  );
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
    sort: filter.sort,
    query: query.isEmpty ? null : query,
  );
});

/// Lista na ekranie Odkrywaj: wyniki wyszukiwania po filtrach z okna „Filtry”, z najlepszym dopasowaniem
/// na górze przy sortowaniu „Polecane”. [total]: ile lokali przed filtrami.
typedef DiscoverResults = ({List<RestaurantSummary> items, String? bestMatchId, int total});

final discoverResultsProvider = FutureProvider<DiscoverResults>((ref) async {
  final all = await ref.watch(searchResultsProvider.future);
  final filter = ref.watch(discoverFilterProvider);
  final hasLocation = ref.watch(locationProvider).value != null;
  // Historia gościa (rezerwacje i zamówienia): lokale, w których był, i kuchnie, które lubi.
  final visited = <String>{
    for (final r in ref.watch(myReservationsProvider).value ?? const <Reservation>[]) r.restaurantId,
    for (final o in ref.watch(myOrdersProvider).value ?? const <GuestOrder>[]) o.restaurantId,
  };
  final items = applyDiscoverFilter(all, filter, hasLocation: hasLocation);
  final best = filter.sort == DiscoverSort.recommended
      ? bestMatch(items, visited: visited, hasLocation: hasLocation)
      : null;
  if (best != null) {
    items
      ..remove(best)
      ..insert(0, best);
  }
  return (items: items, bestMatchId: best?.id, total: all.length);
});

/// Filtry z okna „Filtry” na gotowej liście lokali.
List<RestaurantSummary> applyDiscoverFilter(
  List<RestaurantSummary> items,
  DiscoverFilter f, {
  required bool hasLocation,
}) => [
  for (final r in items)
    if ((f.prices.isEmpty || f.prices.contains(r.priceLevel)) &&
        (f.minRating == null || (r.verifiedReviews > 0 && (r.foodAvg ?? 0) >= f.minRating!)) &&
        (!f.bookable || r.isPro) &&
        (!f.orderOnline || r.canOrder) &&
        (!f.delivery || (r.isPro && r.deliveryEnabled)) &&
        (!f.pickup || (r.isPro && r.pickupEnabled)) &&
        (f.maxKm == null || !hasLocation || r.distanceM <= f.maxKm! * 1000))
      r,
];

/// Najlepsze dopasowanie dla gościa: ocena kuchni, odległość i kuchnie lokali, w których już był
/// (rezerwacje i zamówienia). Null, gdy nie ma z czego wybrać (mniej niż dwa lokale albo żadnych danych).
RestaurantSummary? bestMatch(
  List<RestaurantSummary> items, {
  required Set<String> visited,
  required bool hasLocation,
}) {
  if (items.length < 2) return null;
  final liked = {for (final r in items) if (visited.contains(r.id)) r.cuisine};
  final rated = items.any((r) => r.foodScore != null);
  if (liked.isEmpty && !rated && !hasLocation) return null;
  double score(RestaurantSummary r) =>
      0.45 * ((r.foodScore ?? r.foodAvg ?? 3.5) / 5) +
      (hasLocation ? 0.3 * (1 - (r.distanceM.clamp(0, 10000) / 10000)) : 0) +
      (liked.contains(r.cuisine) ? 0.25 : 0) +
      (r.isPro ? 0.05 : 0);
  return items.reduce((a, b) => score(b) > score(a) ? b : a);
}

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

/// Moje wpisy na listach oczekujących (czekam albo lokal zaproponował godzinę).
final myWaitlistProvider = FutureProvider.autoDispose<List<GuestWaitlist>>((ref) {
  if (ref.watch(userIdProvider) == null) return Future.value(const []);
  return ref.watch(repositoryProvider).myWaitlist();
});

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

// ---------------------------------------------------------------
// Zamówienia z dostawą i na wynos
// ---------------------------------------------------------------

/// Koszyk w jednym lokalu. Trzyma się, dopóki gość nie złoży zamówienia albo go nie wyczyści.
class CartNotifier extends Notifier<List<CartLine>> {
  CartNotifier(this.restaurantId);

  final String restaurantId;

  @override
  List<CartLine> build() => const [];

  void add(CartLine line) {
    final i = state.indexWhere((l) => l.key == line.key);
    if (i < 0) {
      state = [...state, line];
    } else {
      state = [
        for (final (j, l) in state.indexed) j == i ? l.withQuantity((l.quantity + line.quantity).clamp(1, 99)) : l,
      ];
    }
  }

  void setQuantity(String key, int quantity) {
    state = [
      for (final l in state)
        if (l.key != key) l else if (quantity > 0) l.withQuantity(quantity.clamp(1, 99)),
    ];
  }

  void clear() => state = const [];
}

final cartProvider = NotifierProvider.family<CartNotifier, List<CartLine>, String>(CartNotifier.new);

final myOrdersProvider = FutureProvider.autoDispose<List<GuestOrder>>((ref) {
  if (ref.watch(userIdProvider) == null) return Future.value(const []);
  return ref.watch(repositoryProvider).myOrders();
});

/// Numer zmiany zamówienia na żywo.
class OrderLive extends Notifier<int> {
  OrderLive(this.orderId);

  final String orderId;

  @override
  int build() {
    final stop = ref.watch(repositoryProvider).watchOrder(orderId, () => state++);
    ref.onDispose(stop);
    return 0;
  }
}

final orderLiveProvider = NotifierProvider.autoDispose.family<OrderLive, int, String>(OrderLive.new);

final guestOrderProvider = FutureProvider.autoDispose.family<GuestOrder?, String>((ref, id) {
  ref.watch(orderLiveProvider(id));
  if (ref.watch(userIdProvider) == null) return Future.value(null);
  return ref.watch(repositoryProvider).order(id);
});

final paymentsTestModeProvider = FutureProvider<bool>(
  (ref) => ref.watch(repositoryProvider).paymentsTestMode(),
);

final profileProvider = FutureProvider.autoDispose<Profile?>((ref) {
  if (ref.watch(userIdProvider) == null) return Future.value(null);
  return ref.watch(repositoryProvider).myProfile();
});

final notificationPreferencesProvider =
    FutureProvider.autoDispose<NotificationPreferences?>((ref) {
      if (ref.watch(userIdProvider) == null) return Future.value(null);
      return ref.watch(repositoryProvider).notificationPreferences();
    });

