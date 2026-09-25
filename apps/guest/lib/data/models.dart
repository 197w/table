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
  });

  final String id;
  final String name;
  final String cuisine;
  final int priceLevel;
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
    required this.hours,
    required this.menu,
    required this.rating,
    this.description,
  });

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
      hours: hours,
      menu: menu,
      rating: rating,
    );
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
  });

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
// Karty podarunkowe
// ---------------------------------------------------------------

class GuestGiftCard {
  const GuestGiftCard({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantCity,
    required this.code,
    required this.initialGrosze,
    required this.balanceGrosze,
    required this.testMode,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.logoUrl,
    this.recipientName,
    this.message,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String restaurantCity;
  final String? logoUrl;
  final String code;
  final int initialGrosze;
  final int balanceGrosze;
  final String? recipientName;
  final String? message;

  /// Karta kupiona bez prawdziwej płatności, na czas testów.
  final bool testMode;
  final String status;
  final DateTime expiresAt;
  final DateTime createdAt;

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isUsable => status == 'active' && !isExpired && balanceGrosze > 0;

  factory GuestGiftCard.fromJson(Map<String, dynamic> json) {
    return GuestGiftCard(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String,
      restaurantName: json['restaurant_name'] as String,
      restaurantCity: json['restaurant_city'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      code: json['code'] as String,
      initialGrosze: _toInt(json['initial_grosze']),
      balanceGrosze: _toInt(json['balance_grosze']),
      recipientName: json['recipient_name'] as String?,
      message: json['message'] as String?,
      testMode: json['test_mode'] == true,
      status: json['status'] as String? ?? 'active',
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
