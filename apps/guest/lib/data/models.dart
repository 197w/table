/// Modele danych. Nazwy pól w JSON odpowiadają kolumnom i funkcjom z supabase/migrations.
library;

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

// ---------------------------------------------------------------
// Kuchnie
// ---------------------------------------------------------------

const _cuisineLabels = <String, String>{
  'polska': 'Polska',
  'wloska': 'Włoska',
  'francuska': 'Francuska',
  'grecka': 'Grecka',
  'hiszpanska': 'Hiszpańska',
  'gruzinska': 'Gruzińska',
  'turecka': 'Turecka',
  'japonska': 'Japońska',
  'chinska': 'Chińska',
  'tajska': 'Tajska',
  'wietnamska': 'Wietnamska',
  'koreanska': 'Koreańska',
  'indyjska': 'Indyjska',
  'meksykanska': 'Meksykańska',
  'amerykanska': 'Amerykańska',
  'wegetarianska': 'Wegetariańska',
  'weganska': 'Wegańska',
  'srodziemnomorska': 'Śródziemnomorska',
  'kawiarnia': 'Kawiarnia',
  'inna': 'Inna',
};

String cuisineLabel(String slug) {
  final label = _cuisineLabels[slug];
  if (label != null) return label;
  if (slug.isEmpty) return slug;
  return slug[0].toUpperCase() + slug.substring(1);
}

// ---------------------------------------------------------------
// Lokale
// ---------------------------------------------------------------

class RestaurantSummary {
  const RestaurantSummary({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.priceLevel,
    required this.address,
    required this.city,
    required this.isPro,
    required this.isExample,
    this.logoUrl,
    required this.distanceM,
    required this.verifiedReviews,
    required this.unverifiedReviews,
    this.foodAvg,
    this.foodScore,
    this.coverUrl,
    this.deliveryEnabled = false,
    this.pickupEnabled = false,
    this.matchedDish,
  });

  final String id;
  final String name;
  final String cuisine;
  final int priceLevel;

  /// Zdjęcie na kartę: zdjęcie lokalu albo pierwsze zdjęcie dania z menu. Null: karta z ikoną kuchni.
  final String? coverUrl;
  final bool deliveryEnabled;
  final bool pickupEnabled;

  /// Danie z menu pasujące do wpisanej frazy, np. „Pizza Margherita” przy „pizza”.
  final String? matchedDish;

  /// Zamówienie w aplikacji (dostawa albo odbiór) jest tylko w planie Pro.
  bool get canOrder => isPro && (deliveryEnabled || pickupEnabled);
  final String address;
  final String city;
  final bool isPro;
  final bool isExample;
  final String? logoUrl;
  final double distanceM;
  final int verifiedReviews;
  final int unverifiedReviews;
  final double? foodAvg;
  final double? foodScore;

  factory RestaurantSummary.fromJson(Map<String, dynamic> json) {
    return RestaurantSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      cuisine: json['cuisine'] as String,
      priceLevel: _toInt(json['price_level']),
      address: json['address'] as String,
      city: json['city'] as String,
      isPro: json['plan'] == 'pro',
      isExample: json['is_example'] == true,
      logoUrl: json['logo_url'] as String?,
      distanceM: _toDouble(json['distance_m']) ?? 0,
      verifiedReviews: _toInt(json['verified_reviews']),
      unverifiedReviews: _toInt(json['unverified_reviews']),
      foodAvg: _toDouble(json['food_avg']),
      foodScore: _toDouble(json['food_score']),
      coverUrl: (json['cover_url'] as String?)?.trim().isEmpty ?? true ? null : json['cover_url'] as String,
      deliveryEnabled: json['delivery_enabled'] == true,
      pickupEnabled: json['pickup_enabled'] == true,
      matchedDish: json['matched_dish'] as String?,
    );
  }
}

class OpeningHours {
  const OpeningHours({
    required this.weekday,
    required this.opens,
    required this.closes,
  });

  /// ISO: 1 = poniedziałek, 7 = niedziela.
  final int weekday;
  final String opens;
  final String closes;

  factory OpeningHours.fromJson(Map<String, dynamic> json) {
    String hm(Object? v) => (v as String).substring(0, 5);
    return OpeningHours(
      weekday: _toInt(json['weekday']),
      opens: hm(json['opens']),
      closes: hm(json['closes']),
    );
  }
}

/// Wariant (np. rozmiar) albo płatny dodatek dania.
class MenuOption {
  const MenuOption(this.name, this.priceGrosze);

  final String name;
  final int priceGrosze;

  static List<MenuOption> listFrom(Object? value) => [
    for (final e in (value as List? ?? const []).cast<Map<String, dynamic>>())
      MenuOption(e['name'] as String, _toInt(e['price_grosze'])),
  ];
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.priceGrosze,
    required this.allergens,
    required this.position,
    this.description,
    this.variants = const [],
    this.addons = const [],
    this.available = true,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String? description;

  /// Cena dania. Przy wariantach najniższa z ich cen.
  final int priceGrosze;
  final List<String> allergens;
  final int position;

  /// Warianty, np. rozmiary, każdy z własną ceną.
  final List<MenuOption> variants;
  final List<MenuOption> addons;

  /// Lokal oznaczył danie jako chwilowo niedostępne.
  final bool available;

  /// Warianty mają różne ceny, więc cena zaczyna się „od”. Jeden wariant (np. Tonic 200 ml) ma jedną cenę.
  bool get priceVaries => variants.map((v) => v.priceGrosze).toSet().length > 1;

  /// Zdjęcie dania dodane w panelu restauracji.
  final String? photoUrl;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceGrosze: _toInt(json['price_grosze']),
      allergens: (json['allergens'] as List? ?? const []).cast<String>(),
      position: _toInt(json['position']),
      variants: MenuOption.listFrom(json['variants']),
      addons: MenuOption.listFrom(json['addons']),
      available: json['available'] != false,
      photoUrl: json['photo_url'] as String?,
    );
  }
}

class MenuSection {
  const MenuSection({
    required this.id,
    required this.name,
    required this.position,
    required this.items,
  });

  final String id;
  final String name;
  final int position;
  final List<MenuItem> items;

  factory MenuSection.fromJson(Map<String, dynamic> json) {
    final items =
        (json['menu_items'] as List? ?? const [])
            .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return MenuSection(
      id: json['id'] as String,
      name: json['name'] as String,
      position: _toInt(json['position']),
      items: items,
    );
  }
}

class Rating {
  const Rating({
    required this.verified,
    required this.unverified,
    this.food,
    this.service,
    this.ambience,
  });

  final int verified;
  final int unverified;
  final double? food;
  final double? service;
  final double? ambience;

  static const empty = Rating(verified: 0, unverified: 0);

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      verified: _toInt(json['verified_reviews']),
      unverified: _toInt(json['unverified_reviews']),
      food: _toDouble(json['food_avg']),
      service: _toDouble(json['service_avg']),
      ambience: _toDouble(json['ambience_avg']),
    );
  }
}

class RestaurantDetail {
  const RestaurantDetail({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.priceLevel,
    required this.address,
    required this.city,
    required this.phone,
    required this.isPro,
    required this.isExample,
    this.logoUrl,
    this.maxPartySize = 12,
    this.depositMinParty,
    this.depositPerPersonGrosze,
    required this.hours,
    required this.menu,
    required this.rating,
    this.description,
    this.deliveryEnabled = false,
    this.pickupEnabled = false,
    this.takeawayCash = true,
    this.deliveryFeeGrosze = 0,
    this.deliveryMinGrosze = 0,
    this.deliveryArea,
    this.coverUrl,
    this.leadPickupMin = 20,
    this.leadDeliveryMin = 40,
  });

  /// Zdjęcie lokalu z panelu („Dane lokalu”). Bez niego: pierwsze zdjęcie dania z menu ([coverPhoto]).
  final String? coverUrl;

  /// Zdjęcie na górę strony lokalu: zdjęcie lokalu albo pierwsze zdjęcie dania. Null: ikona kuchni.
  String? get coverPhoto {
    if (coverUrl != null) return coverUrl;
    for (final s in menu) {
      for (final i in s.items) {
        if (i.photoUrl != null && i.available) return i.photoUrl;
      }
    }
    return null;
  }

  /// Zamówienie na godzinę: najwcześniej za tyle minut (kuchnia potrzebuje czasu), osobno odbiór i dostawa.
  final int leadPickupMin;
  final int leadDeliveryMin;

  /// Zamówienia w aplikacji: dostawa i odbiór osobisty (tylko plan Pro).
  final bool deliveryEnabled;
  final bool pickupEnabled;

  /// Gotówka u dostawcy albo przy odbiorze. Karta online jest zawsze.
  final bool takeawayCash;
  final int deliveryFeeGrosze;
  final int deliveryMinGrosze;
  final String? deliveryArea;

  bool get canOrder => isPro && (deliveryEnabled || pickupEnabled);

  final String id;
  final String name;
  final String cuisine;
  final int priceLevel;
  final String? description;
  final String address;
  final String city;
  final String phone;
  final bool isPro;
  final bool isExample;
  final String? logoUrl;

  /// Największa grupa, którą można zarezerwować w aplikacji.
  final int maxPartySize;
  final List<OpeningHours> hours;
  final List<MenuSection> menu;
  final Rating rating;

  /// Zadatek przy rezerwacji: od ilu osób i ile za osobę. Null: lokal nie bierze zadatku.
  final int? depositMinParty;
  final int? depositPerPersonGrosze;

  /// Zadatek za rezerwację dla [party] osób. Null: bez zadatku.
  int? depositFor(int party) {
    final min = depositMinParty;
    final per = depositPerPersonGrosze;
    if (min == null || per == null || party < min) return null;
    return per * party;
  }

  factory RestaurantDetail.fromJson(Map<String, dynamic> json, Rating rating) {
    final hours =
        (json['opening_hours'] as List? ?? const [])
            .map((e) => OpeningHours.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.weekday.compareTo(b.weekday));
    final menu =
        (json['menu_sections'] as List? ?? const [])
            .map((e) => MenuSection.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return RestaurantDetail(
      id: json['id'] as String,
      name: json['name'] as String,
      cuisine: json['cuisine'] as String,
      priceLevel: _toInt(json['price_level']),
      description: json['description'] as String?,
      address: json['address'] as String,
      city: json['city'] as String,
      phone: json['phone'] as String,
      isPro: json['plan'] == 'pro',
      isExample: json['is_example'] == true,
      logoUrl: json['logo_url'] as String?,
      maxPartySize: _toInt(json['max_party_size']) == 0 ? 12 : _toInt(json['max_party_size']),
      depositMinParty: json['deposit_min_party'] == null ? null : _toInt(json['deposit_min_party']),
      depositPerPersonGrosze: json['deposit_per_person_grosze'] == null ? null : _toInt(json['deposit_per_person_grosze']),
      hours: hours,
      menu: menu,
      rating: rating,
      deliveryEnabled: json['delivery_enabled'] == true,
      pickupEnabled: json['pickup_enabled'] == true,
      takeawayCash: json['takeaway_cash'] != false,
      deliveryFeeGrosze: _toInt(json['delivery_fee_grosze']),
      deliveryMinGrosze: _toInt(json['delivery_min_grosze']),
      deliveryArea: json['delivery_area'] as String?,
      coverUrl: json['cover_url'] as String?,
      leadPickupMin: json['kitchen_lead_pickup_min'] == null ? 20 : _toInt(json['kitchen_lead_pickup_min']),
      leadDeliveryMin: json['kitchen_lead_delivery_min'] == null ? 40 : _toInt(json['kitchen_lead_delivery_min']),
    );
  }

  /// Godziny, na które można zamówić [kind] w dniu [day]: co 15 minut w godzinach otwarcia, nie wcześniej
  /// niż za czas przygotowania (co najmniej 15 minut) od [now]. Bez godzin otwarcia: 8:00–22:00.
  List<DateTime> orderSlots(OrderKind kind, DateTime day, DateTime now) {
    final DateTime opens;
    final DateTime closes;
    if (hours.isEmpty) {
      opens = DateTime(day.year, day.month, day.day, 8);
      closes = DateTime(day.year, day.month, day.day, 22);
    } else {
      final h = hoursFor(day);
      if (h == null) return const [];
      DateTime at(String hm) {
        final p = hm.split(':');
        return DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
      }

      opens = at(h.opens);
      closes = at(h.closes);
    }
    final lead = kind == OrderKind.delivery ? leadDeliveryMin : leadPickupMin;
    // 5 minut zapasu na wypełnienie koszyka i płatność.
    final earliest = now.add(Duration(minutes: (lead < 15 ? 15 : lead) + 5));
    var t = opens;
    final slots = <DateTime>[];
    while (t.isBefore(closes)) {
      if (!t.isBefore(earliest)) slots.add(t);
      t = t.add(const Duration(minutes: 15));
    }
    return slots;
  }

  /// Czy lokal jest teraz otwarty, z napisem dla gościa: „Otwarte do 22:00”, „Zamknięte · otwiera jutro o 12:00”.
  /// Null: lokal nie podał godzin.
  ({bool open, String label})? openStatusAt(DateTime now) {
    if (hours.isEmpty) return null;
    int minutes(String hm) {
      final p = hm.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    String closes(String hm) => hm == '24:00' ? 'północy' : hm;
    final today = hoursFor(now);
    final nowMin = now.hour * 60 + now.minute;
    if (today != null) {
      if (nowMin >= minutes(today.opens) && nowMin < minutes(today.closes)) {
        return (open: true, label: 'Otwarte do ${closes(today.closes)}');
      }
      if (nowMin < minutes(today.opens)) return (open: false, label: 'Zamknięte · otwiera o ${today.opens}');
    }
    const days = ['w poniedziałek', 'we wtorek', 'w środę', 'w czwartek', 'w piątek', 'w sobotę', 'w niedzielę'];
    for (var d = 1; d <= 7; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final h = hoursFor(day);
      if (h != null) {
        final when = d == 1 ? 'jutro' : days[day.weekday - 1];
        return (open: false, label: 'Zamknięte · otwiera $when o ${h.opens}');
      }
    }
    return (open: false, label: 'Zamknięte');
  }

  OpeningHours? hoursFor(DateTime day) {
    for (final h in hours) {
      if (h.weekday == day.weekday) return h;
    }
    return null;
  }
}

// ---------------------------------------------------------------
// Opinie
// ---------------------------------------------------------------

class Review {
  const Review({
    required this.id,
    required this.food,
    required this.service,
    required this.ambience,
    required this.verification,
    required this.author,
    required this.isMine,
    required this.createdAt,
    this.body,
  });

  final String id;
  final int food;
  final int service;
  final int ambience;
  final String? body;

  /// reservation | receipt | none
  final String verification;
  final String author;
  final bool isMine;
  final DateTime createdAt;

  bool get isVerified => verification != 'none';

  String get verificationLabel => switch (verification) {
    'reservation' => 'Zweryfikowana wizyta',
    'receipt' => 'Zweryfikowana paragonem',
    _ => 'Niezweryfikowana',
  };

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      food: _toInt(json['food']),
      service: _toInt(json['service']),
      ambience: _toInt(json['ambience']),
      body: json['body'] as String?,
      verification: json['verification'] as String,
      author: json['author'] as String,
      isMine: json['is_mine'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

// ---------------------------------------------------------------
// Rezerwacje
// ---------------------------------------------------------------

enum Occasion {
  birthday('Urodziny'),
  anniversary('Rocznica'),
  date('Randka'),
  business('Spotkanie biznesowe'),
  proposal('Oświadczyny'),
  other('Inna okazja');

  const Occasion(this.label);
  final String label;

  static Occasion? fromDb(Object? value) {
    for (final o in Occasion.values) {
      if (o.name == value) return o;
    }
    return null;
  }
}

enum ReservationStatus {
  confirmed('Potwierdzona'),
  seated('Przy stoliku'),
  completed('Zakończona'),
  cancelled('Odwołana'),
  noShow('Nieobecność');

  const ReservationStatus(this.label);
  final String label;

  static ReservationStatus fromDb(Object? value) => switch (value) {
    'seated' => seated,
    'completed' => completed,
    'cancelled' => cancelled,
    'no_show' => noShow,
    _ => confirmed,
  };
}

/// Moje miejsce na liście oczekujących w lokalu. [offeredTime]: lokal zaproponował godzinę.
class GuestWaitlist {
  const GuestWaitlist({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.day,
    required this.partySize,
    required this.from,
    required this.to,
    this.offeredTime,
    this.offeredNote,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final DateTime day;
  final int partySize;

  /// Godziny jako „18:00”.
  final String from;
  final String to;
  final String? offeredTime;
  final String? offeredNote;

  bool get offered => offeredTime != null;

  static String _hm(Object? v) => v == null ? '' : (v as String).substring(0, 5);

  factory GuestWaitlist.fromJson(Map<String, dynamic> json) => GuestWaitlist(
    id: json['id'] as String,
    restaurantId: json['restaurant_id'] as String,
    restaurantName: json['restaurant_name'] as String? ?? 'Lokal',
    day: DateTime.parse(json['day'] as String),
    partySize: _toInt(json['party_size']),
    from: _hm(json['time_from']),
    to: _hm(json['time_to']),
    offeredTime: json['status'] == 'offered' && json['offered_time'] != null ? _hm(json['offered_time']) : null,
    offeredNote: json['offered_note'] as String?,
  );
}

/// Godziny co pół godziny od [opens] do [closes] (np. „12:00”…„22:00”), do wyboru przedziału.
List<String> halfHours(String opens, String closes) {
  int minutes(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  final end = minutes(closes) == 0 ? 24 * 60 : minutes(closes);
  final start = minutes(opens);
  return [
    for (var m = ((start + 29) ~/ 30) * 30; m <= end; m += 30)
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
  ];
}

/// Kod rabatowy lokalu sprawdzony przed rezerwacją: rabat odejmie się od rachunku stolika.
class GuestDiscount {
  const GuestDiscount({required this.code, required this.percent, required this.value});

  final String code;
  final bool percent;

  /// Procent albo kwota w groszach.
  final int value;

  /// Na przykład „−10% od rachunku” albo „−20 zł od rachunku”.
  String get label {
    final zl = value ~/ 100;
    final gr = value % 100;
    final amount = gr == 0 ? '$zl zł' : '$zl,${gr.toString().padLeft(2, '0')} zł';
    return '${percent ? '−$value%' : '−$amount'} od rachunku';
  }

  factory GuestDiscount.fromJson(Map<String, dynamic> json) => GuestDiscount(
    code: json['code'] as String,
    percent: json['kind'] == 'percent',
    value: _toInt(json['value']),
  );
}

class Reservation {
  const Reservation({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantAddress,
    required this.restaurantPhone,
    this.restaurantLogoUrl,
    required this.partySize,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.occasion,
    this.message,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String restaurantAddress;
  final String restaurantPhone;
  final String? restaurantLogoUrl;
  final int partySize;
  final DateTime startsAt;
  final DateTime endsAt;
  final ReservationStatus status;
  final Occasion? occasion;
  final String? message;

  bool get isUpcoming =>
      status == ReservationStatus.confirmed && startsAt.isAfter(DateTime.now());

  bool get canCancel => isUpcoming;

  bool get canReview =>
      (status == ReservationStatus.confirmed ||
          status == ReservationStatus.seated ||
          status == ReservationStatus.completed) &&
      endsAt.isBefore(DateTime.now());

  factory Reservation.fromJson(Map<String, dynamic> json) {
    final restaurant = json['restaurants'] as Map<String, dynamic>? ?? const {};
    return Reservation(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String,
      restaurantName: restaurant['name'] as String? ?? 'Restauracja',
      restaurantAddress: restaurant['address'] as String? ?? '',
      restaurantPhone: restaurant['phone'] as String? ?? '',
      restaurantLogoUrl: restaurant['logo_url'] as String?,
      partySize: _toInt(json['party_size']),
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      status: ReservationStatus.fromDb(json['status']),
      occasion: Occasion.fromDb(json['occasion']),
      message: json['message'] as String?,
    );
  }
}

// ---------------------------------------------------------------
// Profil i błędy
// ---------------------------------------------------------------

class Profile {
  const Profile({required this.id, this.firstName, this.fullName, this.phone});

  final String id;

  /// Widoczne przy opiniach.
  final String? firstName;

  /// Imię i nazwisko widoczne tylko dla restauracji, w której gość rezerwuje.
  final String? fullName;
  final String? phone;
}

// ---------------------------------------------------------------
// Miasta i ranking w okolicy
// ---------------------------------------------------------------

typedef CuisineRow = ({String city, String cuisine});

class City {
  const City({
    required this.name,
    required this.restaurants,
    required this.lat,
    required this.lng,
  });

  final String name;
  final int restaurants;

  /// Środek miasta liczony z położenia lokali.
  final double lat;
  final double lng;

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      name: json['city'] as String,
      restaurants: _toInt(json['restaurants']),
      lat: _toDouble(json['lat']) ?? 0,
      lng: _toDouble(json['lng']) ?? 0,
    );
  }
}

/// Pełne dane jednej rezerwacji gościa, z położeniem lokalu do nawigacji.
class ReservationDetail {
  const ReservationDetail({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.address,
    required this.city,
    required this.phone,
    required this.lat,
    required this.lng,
    required this.partySize,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.reviewed,
    this.occasion,
    this.message,
    this.diet,
    this.discountLabel,
    this.depositGrosze = 0,
    this.depositStatus = 'none',
  });

  /// Kod rabatowy z rezerwacji, np. „REVE10 · −10% od rachunku”.
  final String? discountLabel;

  /// Zadatek: kwota i stan (none, pending, paid, refunded).
  final int depositGrosze;
  final String depositStatus;

  bool get depositPending => depositStatus == 'pending' && isUpcoming;

  String? get depositLabel => switch (depositStatus) {
    'paid' => 'opłacony, odejmie się od rachunku',
    'pending' => 'czeka na wpłatę',
    'refunded' => 'zwrócony',
    _ => null,
  };

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String address;
  final String city;
  final String phone;
  final double lat;
  final double lng;
  final int partySize;
  final DateTime startsAt;
  final DateTime endsAt;
  final ReservationStatus status;
  final Occasion? occasion;
  final String? message;
  final String? diet;

  /// Gość wystawił już opinię o tej wizycie.
  final bool reviewed;

  bool get isUpcoming =>
      status == ReservationStatus.confirmed && startsAt.isAfter(DateTime.now());

  bool get canCancel => isUpcoming;

  bool get canReview =>
      !reviewed &&
      (status == ReservationStatus.confirmed ||
          status == ReservationStatus.seated ||
          status == ReservationStatus.completed) &&
      endsAt.isBefore(DateTime.now());

  factory ReservationDetail.fromJson(Map<String, dynamic> json) {
    return ReservationDetail(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String,
      restaurantName: json['restaurant_name'] as String,
      address: json['address'] as String,
      city: json['city'] as String,
      phone: json['phone'] as String,
      lat: _toDouble(json['lat']) ?? 0,
      lng: _toDouble(json['lng']) ?? 0,
      partySize: _toInt(json['party_size']),
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      status: ReservationStatus.fromDb(json['status']),
      occasion: Occasion.fromDb(json['occasion']),
      message: json['message'] as String?,
      diet: json['diet'] as String?,
      reviewed: json['reviewed'] == true,
      discountLabel: json['discount_code'] == null
          ? null
          : '${json['discount_code']} · ${GuestDiscount(code: json['discount_code'] as String, percent: json['discount_kind'] == 'percent', value: _toInt(json['discount_value'])).label}',
      depositGrosze: _toInt(json['deposit_grosze']),
      depositStatus: json['deposit_status'] as String? ?? 'none',
    );
  }
}

/// Czas wizyty bez sprzątania. Musi zgadzać się z private.visit_minutes w bazie.
int visitMinutes(int partySize) =>
    partySize <= 2 ? 90 : (partySize <= 4 ? 105 : 120);

/// Zgody na powiadomienia push. Wszystkie powiadomienia idą przez push, SMS tylko z kodem logowania.
class NotificationPreferences {
  const NotificationPreferences({
    this.reservationReminders = true,
    this.reservationUpdates = true,
    this.reviewRequests = true,
    this.news = false,
  });

  final bool reservationReminders;
  final bool reservationUpdates;
  final bool reviewRequests;
  final bool news;

  NotificationPreferences copyWith({
    bool? reservationReminders,
    bool? reservationUpdates,
    bool? reviewRequests,
    bool? news,
  }) {
    return NotificationPreferences(
      reservationReminders: reservationReminders ?? this.reservationReminders,
      reservationUpdates: reservationUpdates ?? this.reservationUpdates,
      reviewRequests: reviewRequests ?? this.reviewRequests,
      news: news ?? this.news,
    );
  }

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      reservationReminders: json['reservation_reminders'] != false,
      reservationUpdates: json['reservation_updates'] != false,
      reviewRequests: json['review_requests'] != false,
      news: json['news'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'reservation_reminders': reservationReminders,
    'reservation_updates': reservationUpdates,
    'review_requests': reviewRequests,
    'news': news,
  };
}

// ---------------------------------------------------------------
// Zamówienia z dostawą i na wynos
// ---------------------------------------------------------------

enum OrderKind {
  delivery('delivery', 'Dostawa'),
  pickup('pickup', 'Odbiór osobisty');

  const OrderKind(this.db, this.label);
  final String db;
  final String label;

  static OrderKind from(Object? value) => value == 'pickup' ? OrderKind.pickup : OrderKind.delivery;
}

enum PaymentChoice {
  card('card_online', 'Karta online'),
  cash('cash', 'Gotówka');

  const PaymentChoice(this.db, this.label);
  final String db;
  final String label;
}

/// Etap zamówienia widziany przez gościa.
enum OrderStage {
  awaitingPayment('awaiting_payment', 'Czeka na płatność'),
  placed('placed', 'Czeka na lokal'),
  accepted('accepted', 'Przygotowujemy'),
  ready('ready', 'Gotowe'),
  onTheWay('on_the_way', 'W drodze'),
  delivered('delivered', 'Zakończone'),
  rejected('rejected', 'Odrzucone'),
  cancelled('cancelled', 'Odwołane');

  const OrderStage(this.db, this.label);
  final String db;
  final String label;

  bool get finished => this == delivered || this == rejected || this == cancelled;

  static OrderStage from(Object? value) =>
      values.firstWhere((s) => s.db == value, orElse: () => OrderStage.placed);
}

class GuestOrderItem {
  const GuestOrderItem({
    required this.name,
    required this.quantity,
    required this.unitPriceGrosze,
    this.variant,
    this.addons = const [],
    this.note,
  });

  final String name;
  final int quantity;
  final int unitPriceGrosze;
  final String? variant;
  final List<String> addons;
  final String? note;

  int get totalGrosze => unitPriceGrosze * quantity;

  String? get details {
    final parts = [?variant, for (final a in addons) '+ ${a.toLowerCase()}'];
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory GuestOrderItem.fromJson(Map<String, dynamic> json) => GuestOrderItem(
    name: json['name'] as String,
    quantity: _toInt(json['quantity']),
    unitPriceGrosze: _toInt(json['unit_price_grosze']),
    variant: json['variant'] as String?,
    addons: [
      for (final a in (json['addons'] as List? ?? const []).cast<Map<String, dynamic>>()) a['name'] as String,
    ],
    note: json['note'] as String?,
  );
}

/// Moje zamówienie z dostawą albo odbiorem osobistym.
class GuestOrder {
  const GuestOrder({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantPhone,
    required this.restaurantAddress,
    required this.kind,
    required this.number,
    required this.stage,
    required this.openedAt,
    required this.items,
    required this.feeGrosze,
    required this.payment,
    required this.paid,
    this.testPayment = false,
    this.address,
    this.promisedAt,
    this.rejectReason,
    this.scheduledFor,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String restaurantPhone;
  final String restaurantAddress;
  final OrderKind kind;
  final int number;
  final OrderStage stage;
  final DateTime openedAt;
  final List<GuestOrderItem> items;
  final int feeGrosze;
  final PaymentChoice payment;
  final bool paid;
  final bool testPayment;
  final String? address;
  final DateTime? promisedAt;
  final String? rejectReason;

  /// Zamówienie na godzinę: odbiór w lokalu albo dostawa o tej porze. Null: jak najszybciej.
  final DateTime? scheduledFor;

  int get totalGrosze => feeGrosze + items.fold(0, (sum, i) => sum + i.totalGrosze);

  bool get canCancel => stage == OrderStage.awaitingPayment || stage == OrderStage.placed;

  factory GuestOrder.fromJson(Map<String, dynamic> json) {
    final r = json['restaurants'] as Map<String, dynamic>? ?? const {};
    return GuestOrder(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String,
      restaurantName: r['name'] as String? ?? '',
      restaurantPhone: r['phone'] as String? ?? '',
      restaurantAddress: [r['address'], r['city']].whereType<String>().join(', '),
      kind: OrderKind.from(json['kind']),
      number: _toInt(json['number']),
      stage: OrderStage.from(json['fulfillment']),
      openedAt: DateTime.parse(json['opened_at'] as String).toLocal(),
      items: [
        for (final i in (json['order_items'] as List? ?? const []).cast<Map<String, dynamic>>())
          if (i['status'] != 'cancelled' || json['fulfillment'] == 'cancelled' || json['fulfillment'] == 'rejected')
            GuestOrderItem.fromJson(i),
      ],
      feeGrosze: _toInt(json['delivery_fee_grosze']),
      payment: json['payment_choice'] == 'cash' ? PaymentChoice.cash : PaymentChoice.card,
      paid: json['payment_status'] == 'paid',
      testPayment: json['payment_test'] == true,
      address: json['delivery_address'] as String?,
      promisedAt: json['promised_at'] == null ? null : DateTime.parse(json['promised_at'] as String).toLocal(),
      rejectReason: json['reject_reason'] as String?,
      scheduledFor: json['scheduled_for'] == null ? null : DateTime.parse(json['scheduled_for'] as String).toLocal(),
    );
  }
}

/// Pozycja w koszyku: danie z wybranym wariantem i dodatkami.
class CartLine {
  const CartLine({
    required this.menuItemId,
    required this.name,
    required this.unitPriceGrosze,
    required this.quantity,
    this.variant,
    this.addons = const [],
  });

  final String menuItemId;
  final String name;
  final int unitPriceGrosze;
  final int quantity;
  final String? variant;
  final List<String> addons;

  /// To samo danie z tymi samymi opcjami łączy się w jedną pozycję.
  String get key => [menuItemId, variant ?? '', ...addons].join('|');

  int get totalGrosze => unitPriceGrosze * quantity;

  String? get details {
    final parts = [?variant, for (final a in addons) '+ ${a.toLowerCase()}'];
    return parts.isEmpty ? null : parts.join(', ');
  }

  CartLine withQuantity(int value) => CartLine(
    menuItemId: menuItemId,
    name: name,
    unitPriceGrosze: unitPriceGrosze,
    quantity: value,
    variant: variant,
    addons: addons,
  );

  Map<String, dynamic> toJson() => {
    'menu_item_id': menuItemId,
    'quantity': quantity,
    'variant': ?variant,
    'addons': addons,
  };
}
