/// Modele panelu restauracji. Nazwy pól w JSON odpowiadają funkcjom `panel_*`
/// i tabelom z supabase/migrations.
library;

double? _toDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _toInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime _toDate(Object? value) => DateTime.parse(value as String).toLocal();

DateTime? _toDateOrNull(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

List<String> _toStrings(Object? value) =>
    (value as List? ?? const []).map((e) => e.toString()).toList();

// ---------------------------------------------------------------
// Lokal i rola
// ---------------------------------------------------------------

enum StaffRole {
  owner('Właściciel'),
  manager('Kierownik'),
  staff('Obsługa');

  const StaffRole(this.label);
  final String label;

  static StaffRole fromDb(Object? value) => switch (value) {
    'owner' => owner,
    'manager' => manager,
    _ => staff,
  };
}

class PanelRestaurant {
  const PanelRestaurant({
    required this.id,
    required this.name,
    required this.city,
    required this.isPro,
    required this.role,
    this.logoUrl,
    this.listed = true,
  });

  final String id;
  final String name;
  final String city;
  final bool isPro;
  final StaffRole role;
  final String? logoUrl;

  /// Goście widzą lokal w aplikacji. Nowy lokal czeka na weryfikację przez Table.
  final bool listed;

  /// Kierownik i właściciel zmieniają salę, menu, dane lokalu i odpowiadają na opinie.
  bool get canManage => role != StaffRole.staff;

  factory PanelRestaurant.fromJson(Map<String, dynamic> json) {
    return PanelRestaurant(
      id: json['id'] as String,
      name: json['name'] as String,
      city: json['city'] as String? ?? '',
      isPro: json['plan'] == 'pro',
      role: StaffRole.fromDb(json['role']),
      logoUrl: json['logo_url'] as String?,
      listed: json['listed'] != false,
    );
  }
}

// ---------------------------------------------------------------
// Rezerwacje
// ---------------------------------------------------------------

enum ReservationStatus {
  confirmed('confirmed', 'Potwierdzona'),
  seated('seated', 'Przy stoliku'),
  completed('completed', 'Zakończona'),
  cancelled('cancelled', 'Odwołana'),
  noShow('no_show', 'Nie przyszedł');

  const ReservationStatus(this.db, this.label);
  final String db;
  final String label;

  bool get isActive => this == confirmed || this == seated;

  static ReservationStatus fromDb(Object? value) {
    for (final s in values) {
      if (s.db == value) return s;
    }
    return confirmed;
  }
}

enum ReservationSource {
  app('app', 'Aplikacja'),
  phone('phone', 'Telefon'),
  walkIn('walk_in', 'Z ulicy'),
  block('block', 'Blokada');

  const ReservationSource(this.db, this.label);
  final String db;
  final String label;

  static ReservationSource fromDb(Object? value) {
    for (final s in values) {
      if (s.db == value) return s;
    }
    return app;
  }
}

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
    for (final o in values) {
      if (o.name == value) return o;
    }
    return null;
  }
}

class PanelReservation {
  const PanelReservation({
    required this.id,
    required this.startsAt,
    required this.endsAt,
    required this.partySize,
    required this.status,
    required this.source,
    required this.guestName,
    required this.createdAt,
    required this.tableIds,
    required this.tableLabels,
    required this.fromApp,
    required this.guestVisits,
    required this.guestNoShows,
    this.occasion,
    this.message,
    this.diet,
    this.guestPhone,
    this.staffNote,
    this.seatedAt,
  });

  final String id;
  final DateTime startsAt;
  final DateTime endsAt;
  final int partySize;
  final ReservationStatus status;
  final ReservationSource source;
  final Occasion? occasion;
  final String? message;

  /// Alergie i dieta. Baza oddaje je tylko do 30 dni po wizycie.
  final String? diet;
  final String guestName;
  final String? guestPhone;
  final String? staffNote;
  final DateTime? seatedAt;
  final DateTime createdAt;
  final List<String> tableIds;
  final List<String> tableLabels;
  final bool fromApp;

  /// Wcześniejsze wizyty i niestawiennictwa tego gościa w tym lokalu.
  final int guestVisits;
  final int guestNoShows;

  bool get isBlock => source == ReservationSource.block;

  factory PanelReservation.fromJson(Map<String, dynamic> json) {
    return PanelReservation(
      id: json['id'] as String,
      startsAt: _toDate(json['starts_at']),
      endsAt: _toDate(json['ends_at']),
      partySize: _toInt(json['party_size']),
      status: ReservationStatus.fromDb(json['status']),
      source: ReservationSource.fromDb(json['source']),
      occasion: Occasion.fromDb(json['occasion']),
      message: json['message'] as String?,
      diet: json['diet'] as String?,
      guestName: json['guest_name'] as String? ?? 'Gość',
      guestPhone: json['guest_phone'] as String?,
      staffNote: json['staff_note'] as String?,
      seatedAt: _toDateOrNull(json['seated_at']),
      createdAt: _toDate(json['created_at']),
      tableIds: _toStrings(json['table_ids']),
      tableLabels: _toStrings(json['table_labels']),
      fromApp: json['from_app'] == true,
      guestVisits: _toInt(json['guest_visits']),
      guestNoShows: _toInt(json['guest_no_shows']),
    );
  }
}

/// Dane nowej rezerwacji telefonicznej, gościa z ulicy albo blokady stolika.
class NewReservation {
  const NewReservation({
    required this.startsAt,
    required this.partySize,
    required this.source,
    this.guestName,
    this.guestPhone,
    this.occasion,
    this.message,
    this.staffNote,
    this.tableIds,
    this.durationMinutes,
  });

  final DateTime startsAt;
  final int partySize;
  final ReservationSource source;
  final String? guestName;
  final String? guestPhone;
  final Occasion? occasion;
  final String? message;
  final String? staffNote;

  /// Null oznacza automatyczny dobór stolika.
  final List<String>? tableIds;
  final int? durationMinutes;
}

// ---------------------------------------------------------------
// Plan sali
// ---------------------------------------------------------------

enum TableShape {
  rect('Prostokątny'),
  round('Okrągły');

  const TableShape(this.label);
  final String label;

  static TableShape fromDb(Object? value) => value == 'round' ? round : rect;
}

class FloorZone {
  const FloorZone({
    required this.id,
    required this.name,
    required this.widthCm,
    required this.heightCm,
    required this.position,
  });

  /// Null dla strefy dodanej w edytorze i jeszcze niezapisanej.
  final String? id;
  final String name;
  final int widthCm;
  final int heightCm;
  final int position;

  FloorZone copyWith({String? name, int? widthCm, int? heightCm}) {
    return FloorZone(
      id: id,
      name: name ?? this.name,
      widthCm: widthCm ?? this.widthCm,
      heightCm: heightCm ?? this.heightCm,
      position: position,
    );
  }

  factory FloorZone.fromJson(Map<String, dynamic> json) {
    return FloorZone(
      id: json['id'] as String,
      name: json['name'] as String,
      widthCm: _toInt(json['width_cm'], 1000),
      heightCm: _toInt(json['height_cm'], 700),
      position: _toInt(json['position']),
    );
  }
}

class DiningTable {
  const DiningTable({
    required this.id,
    required this.label,
    required this.seats,
    required this.widthCm,
    required this.heightCm,
    required this.zone,
    required this.priority,
    required this.active,
    required this.xCm,
    required this.yCm,
    required this.rotation,
    required this.shape,
    this.kind = TableKind.table,
    this.chairs,
    this.joinGroup,
    this.draftKey,
  });

  /// Null dla stolika dodanego w edytorze i jeszcze niezapisanego.
  final String? id;

  /// Stolik albo pojedyncze krzesło do rezerwacji, na przykład hoker przy barze.
  final TableKind kind;

  /// Własne położenie krzeseł w cm względem środka blatu, przed obrotem.
  /// Null oznacza rozstawienie automatyczne według liczby miejsc.
  final List<ChairPos>? chairs;

  bool get isSeat => kind == TableKind.seat;

  /// Stały klucz niezapisanego stolika w edytorze. Nie trafia do bazy.
  final String? draftKey;
  final String label;
  final int seats;
  final int widthCm;
  final int heightCm;
  final String zone;
  final String? joinGroup;
  final int priority;
  final bool active;

  /// Środek blatu w centymetrach od lewego górnego rogu strefy.
  final int xCm;
  final int yCm;
  final int rotation;
  final TableShape shape;

  DiningTable copyWith({
    String? label,
    int? seats,
    int? widthCm,
    int? heightCm,
    String? zone,
    String? joinGroup,
    bool clearJoinGroup = false,
    int? priority,
    bool? active,
    int? xCm,
    int? yCm,
    int? rotation,
    TableShape? shape,
    List<ChairPos>? chairs,
    bool resetChairs = false,
  }) {
    return DiningTable(
      id: id,
      draftKey: draftKey,
      kind: kind,
      chairs: resetChairs ? null : (chairs ?? this.chairs),
      label: label ?? this.label,
      seats: seats ?? this.seats,
      widthCm: widthCm ?? this.widthCm,
      heightCm: heightCm ?? this.heightCm,
      zone: zone ?? this.zone,
      joinGroup: clearJoinGroup ? null : (joinGroup ?? this.joinGroup),
      priority: priority ?? this.priority,
      active: active ?? this.active,
      xCm: xCm ?? this.xCm,
      yCm: yCm ?? this.yCm,
      rotation: rotation ?? this.rotation,
      shape: shape ?? this.shape,
    );
  }

  Map<String, dynamic> toJson(String restaurantId) => {
    'id': ?id,
    'restaurant_id': restaurantId,
    'label': label,
    'seats': seats,
    'width_cm': widthCm,
    'height_cm': heightCm,
    'zone': zone,
    'join_group': joinGroup,
    'priority': priority,
    'active': active,
    'x_cm': xCm,
    'y_cm': yCm,
    'rotation': rotation,
    'shape': shape.name,
    'kind': kind.name,
    'chairs': chairs == null ? null : [for (final c in chairs!) c.toJson()],
  };

  factory DiningTable.fromJson(Map<String, dynamic> json) {
    return DiningTable(
      id: json['id'] as String,
      label: json['label'] as String,
      seats: _toInt(json['seats'], 2),
      widthCm: _toInt(json['width_cm'], 80),
      heightCm: _toInt(json['height_cm'], 80),
      zone: json['zone'] as String? ?? 'sala',
      joinGroup: json['join_group'] as String?,
      priority: _toInt(json['priority']),
      active: json['active'] != false,
      xCm: _toInt(json['x_cm'], 100),
      yCm: _toInt(json['y_cm'], 100),
      rotation: _toInt(json['rotation']),
      shape: TableShape.fromDb(json['shape']),
      kind: json['kind'] == 'seat' ? TableKind.seat : TableKind.table,
      chairs: json['chairs'] is List
          ? [for (final c in json['chairs'] as List) ChairPos.fromJson(c as Map<String, dynamic>)]
          : null,
    );
  }
}

enum TableKind { table, seat }

/// Środek krzesła w cm względem środka blatu.
class ChairPos {
  const ChairPos(this.x, this.y);

  final double x;
  final double y;

  Map<String, dynamic> toJson() => {'x': x.round(), 'y': y.round()};

  factory ChairPos.fromJson(Map<String, dynamic> json) =>
      ChairPos((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}

/// Stały element sali: ściana, bar, filar, donica. Jasnoszary, bez podpisu, nie do rezerwacji.
class FloorElement {
  const FloorElement({
    required this.id,
    required this.zone,
    required this.xCm,
    required this.yCm,
    required this.widthCm,
    required this.heightCm,
    required this.rotation,
    required this.shape,
    this.draftKey,
  });

  final String? id;
  final String? draftKey;
  final String zone;
  final int xCm;
  final int yCm;
  final int widthCm;
  final int heightCm;
  final int rotation;
  final TableShape shape;

  String get key => id ?? draftKey!;

  FloorElement copyWith({
    String? zone,
    int? xCm,
    int? yCm,
    int? widthCm,
    int? heightCm,
    int? rotation,
    TableShape? shape,
  }) {
    return FloorElement(
      id: id,
      draftKey: draftKey,
      zone: zone ?? this.zone,
      xCm: xCm ?? this.xCm,
      yCm: yCm ?? this.yCm,
      widthCm: widthCm ?? this.widthCm,
      heightCm: heightCm ?? this.heightCm,
      rotation: rotation ?? this.rotation,
      shape: shape ?? this.shape,
    );
  }

  Map<String, dynamic> toJson(String restaurantId) => {
    'id': ?id,
    'restaurant_id': restaurantId,
    'zone': zone,
    'x_cm': xCm,
    'y_cm': yCm,
    'width_cm': widthCm,
    'height_cm': heightCm,
    'rotation': rotation,
    'shape': shape.name,
  };

  factory FloorElement.fromJson(Map<String, dynamic> json) {
    return FloorElement(
      id: json['id'] as String,
      zone: json['zone'] as String? ?? 'sala',
      xCm: _toInt(json['x_cm'], 100),
      yCm: _toInt(json['y_cm'], 100),
      widthCm: _toInt(json['width_cm'], 100),
      heightCm: _toInt(json['height_cm'], 40),
      rotation: _toInt(json['rotation']),
      shape: TableShape.fromDb(json['shape']),
    );
  }
}

// ---------------------------------------------------------------
// Lokal, godziny i menu
// ---------------------------------------------------------------

class OpeningHours {
  const OpeningHours({
    required this.weekday,
    required this.opens,
    required this.closes,
  });

  /// ISO: 1 = poniedziałek, 7 = niedziela.
  final int weekday;

  /// Godzina w formacie HH:MM.
  final String opens;
  final String closes;

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'opens': opens,
    'closes': closes,
  };

  factory OpeningHours.fromJson(Map<String, dynamic> json) {
    String hm(Object? v) => (v as String).substring(0, 5);
    return OpeningHours(
      weekday: _toInt(json['weekday']),
      opens: hm(json['opens']),
      closes: hm(json['closes']),
    );
  }
}

class RestaurantProfile {
  const RestaurantProfile({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.address,
    required this.city,
    required this.phone,
    required this.slotIntervalMin,
    required this.maxPartySize,
    required this.priceLevel,
    required this.hours,
    this.description,
    this.logoUrl,
    this.schedulePeriod = 'week',
  });

  final String? logoUrl;

  /// Na jaki okres pracownicy zgłaszają godziny: week, two_weeks albo month.
  final String schedulePeriod;

  final String id;
  final String name;
  final String cuisine;
  final String? description;
  final String address;
  final String city;
  final String phone;
  final int slotIntervalMin;

  /// Największa grupa, którą gość zarezerwuje w aplikacji.
  final int maxPartySize;
  final int priceLevel;
  final List<OpeningHours> hours;

  factory RestaurantProfile.fromJson(Map<String, dynamic> json) {
    final hours =
        (json['opening_hours'] as List? ?? const [])
            .map((e) => OpeningHours.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => a.weekday.compareTo(b.weekday));
    return RestaurantProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      cuisine: json['cuisine'] as String,
      description: json['description'] as String?,
      address: json['address'] as String,
      city: json['city'] as String,
      phone: json['phone'] as String,
      slotIntervalMin: _toInt(json['slot_interval_min'], 15),
      maxPartySize: _toInt(json['max_party_size'], 12),
      priceLevel: _toInt(json['price_level'], 2),
      hours: hours,
      logoUrl: json['logo_url'] as String?,
      schedulePeriod: json['schedule_period'] as String? ?? 'week',
    );
  }
}

/// Wariant (np. rozmiar) albo płatny dodatek pozycji menu.
class MenuOption {
  const MenuOption(this.name, this.priceGrosze);

  final String name;
  final int priceGrosze;

  Map<String, dynamic> toJson() => {'name': name, 'price_grosze': priceGrosze};

  factory MenuOption.fromJson(Map<String, dynamic> json) =>
      MenuOption(json['name'] as String, _toInt(json['price_grosze']));

  static List<MenuOption> listFrom(Object? value) => [
    for (final e in value as List? ?? const []) MenuOption.fromJson(e as Map<String, dynamic>),
  ];
}

/// Stawki VAT w gastronomii: 8% na jedzenie na miejscu, 5% na wynos,
/// 23% na alkohol i napoje słodzone.
const vatRates = [8, 5, 23, 0];

class MenuItem {
  const MenuItem({
    required this.id,
    required this.sectionId,
    required this.name,
    required this.priceGrosze,
    required this.allergens,
    required this.position,
    this.description,
    this.variants = const [],
    this.addons = const [],
    this.vatRate = 8,
    this.available = true,
    this.showInKitchen = true,
    this.photoUrl,
  });

  final String id;
  final String sectionId;

  /// Zdjęcie dania (publiczny adres w Storage). Goście widzą je w aplikacji.
  final String? photoUrl;
  final String name;
  final String? description;

  /// Cena bez wariantów. Przy wariantach najniższa z ich cen.
  final int priceGrosze;
  final List<String> allergens;
  final int position;

  /// Warianty, np. rozmiary. Gdy są, gość i kelner wybierają jeden z nich.
  final List<MenuOption> variants;
  final List<MenuOption> addons;
  final int vatRate;

  /// Chwilowo niedostępne, np. skończyło się na dziś.
  final bool available;

  /// Czy pozycja idzie na ekran kuchni. Napoje nalewane przez kelnera zwykle nie.
  final bool showInKitchen;

  /// Pozycja wymaga wyboru przed nabiciem na rachunek.
  bool get hasOptions => variants.isNotEmpty || addons.isNotEmpty;

  /// Najniższa cena, od której zaczyna się pozycja.
  int get fromPrice => variants.isEmpty
      ? priceGrosze
      : variants.map((v) => v.priceGrosze).reduce((a, b) => a < b ? a : b);

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      sectionId: json['section_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceGrosze: _toInt(json['price_grosze']),
      allergens: _toStrings(json['allergens']),
      position: _toInt(json['position']),
      variants: MenuOption.listFrom(json['variants']),
      addons: MenuOption.listFrom(json['addons']),
      vatRate: _toInt(json['vat_rate'], 8),
      available: json['available'] != false,
      showInKitchen: json['show_in_kitchen'] != false,
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

/// Czternaście alergenów z rozporządzenia UE 1169/2011.
const allergenLabels = <String, String>{
  'gluten': 'Gluten',
  'skorupiaki': 'Skorupiaki',
  'jaja': 'Jaja',
  'ryby': 'Ryby',
  'orzeszki ziemne': 'Orzeszki ziemne',
  'soja': 'Soja',
  'mleko': 'Mleko',
  'orzechy': 'Orzechy',
  'seler': 'Seler',
  'gorczyca': 'Gorczyca',
  'sezam': 'Sezam',
  'siarczyny': 'Siarczyny',
  'łubin': 'Łubin',
  'mięczaki': 'Mięczaki',
};

const cuisineLabels = <String, String>{
  'polska': 'Polska',
  'wloska': 'Włoska',
  'japonska': 'Japońska',
  'wietnamska': 'Wietnamska',
  'gruzinska': 'Gruzińska',
  'weganska': 'Wegańska',
  'francuska': 'Francuska',
  'indyjska': 'Indyjska',
};

// ---------------------------------------------------------------
// Opinie i statystyki
// ---------------------------------------------------------------

class PanelReview {
  const PanelReview({
    required this.id,
    required this.food,
    required this.service,
    required this.ambience,
    required this.verification,
    required this.author,
    required this.createdAt,
    this.body,
    this.pricePerPerson,
    this.replyBody,
    this.replyAt,
  });

  final String id;
  final int food;
  final int service;
  final int ambience;
  final String? body;

  /// reservation | receipt | none
  final String verification;
  final String author;
  final int? pricePerPerson;
  final DateTime createdAt;
  final String? replyBody;
  final DateTime? replyAt;

  bool get isVerified => verification != 'none';

  String get verificationLabel => switch (verification) {
    'reservation' => 'Zweryfikowana wizyta',
    'receipt' => 'Zweryfikowana paragonem',
    _ => 'Niezweryfikowana',
  };

  factory PanelReview.fromJson(Map<String, dynamic> json) {
    final price = json['price_per_person'];
    return PanelReview(
      id: json['id'] as String,
      food: _toInt(json['food']),
      service: _toInt(json['service']),
      ambience: _toInt(json['ambience']),
      body: json['body'] as String?,
      verification: json['verification'] as String,
      author: json['author'] as String? ?? 'Gość',
      pricePerPerson: price == null ? null : _toInt(price),
      createdAt: _toDate(json['created_at']),
      replyBody: json['reply_body'] as String?,
      replyAt: _toDateOrNull(json['reply_at']),
    );
  }
}

class OccasionStat {
  const OccasionStat({
    required this.occasion,
    required this.reservations,
    required this.covers,
  });

  final Occasion occasion;
  final int reservations;
  final int covers;

  factory OccasionStat.fromJson(Map<String, dynamic> json) {
    return OccasionStat(
      occasion: Occasion.fromDb(json['occasion']) ?? Occasion.other,
      reservations: _toInt(json['reservations']),
      covers: _toInt(json['covers']),
    );
  }
}

class DayStat {
  const DayStat({
    required this.day,
    required this.views,
    required this.callClicks,
    required this.reservations,
    required this.covers,
    required this.cancellations,
    required this.noShows,
  });

  final DateTime day;
  final int views;
  final int callClicks;
  final int reservations;
  final int covers;
  final int cancellations;
  final int noShows;

  factory DayStat.fromJson(Map<String, dynamic> json) {
    return DayStat(
      day: DateTime.parse(json['day'] as String),
      views: _toInt(json['views']),
      callClicks: _toInt(json['call_clicks']),
      reservations: _toInt(json['reservations']),
      covers: _toInt(json['covers']),
      cancellations: _toInt(json['cancellations']),
      noShows: _toInt(json['no_shows']),
    );
  }
}

double? averageOf(Iterable<int> values) {
  if (values.isEmpty) return null;
  return _toDouble(values.reduce((a, b) => a + b) / values.length);
}

// ---------------------------------------------------------------
// Pracownicy i dyspozycyjność
// ---------------------------------------------------------------

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.color,
    required this.active,
    this.firstName,
    this.lastName,
    this.positionId,
    this.position,
    this.phone,
    this.userId,
  });

  final String id;

  /// Imię i nazwisko razem, do list i kalendarza.
  final String name;
  final String? firstName;
  final String? lastName;
  final String? positionId;

  /// Nazwa stanowiska zapisana przy pracowniku. Aktualną nazwę bierzemy ze stanowisk.
  final String? position;
  final String? phone;

  /// Numer koloru 0–7 w kalendarzu.
  final int color;
  final bool active;

  /// Konto, którym pracownik loguje się do panelu. Null, gdy nie ma konta.
  final String? userId;

  factory StaffMember.fromJson(Map<String, dynamic> json) {
    return StaffMember(
      id: json['id'] as String,
      name: json['name'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      positionId: json['position_id'] as String?,
      position: json['position'] as String?,
      phone: json['phone'] as String?,
      color: _toInt(json['color']),
      active: json['active'] != false,
      userId: json['user_id'] as String?,
    );
  }
}

class Availability {
  const Availability({
    required this.id,
    required this.memberId,
    required this.day,
    required this.starts,
    required this.ends,
    this.note,
  });

  final String id;
  final String memberId;
  final DateTime day;

  /// Godziny w formacie HH:MM.
  final String starts;
  final String ends;
  final String? note;

  factory Availability.fromJson(Map<String, dynamic> json) {
    String hm(Object? v) => (v as String).substring(0, 5);
    return Availability(
      id: json['id'] as String,
      memberId: json['member_id'] as String,
      day: DateTime.parse(json['day'] as String),
      starts: hm(json['starts']),
      ends: hm(json['ends']),
      note: json['note'] as String?,
    );
  }
}

// ---------------------------------------------------------------
// Karty podarunkowe
// ---------------------------------------------------------------

class GiftCard {
  const GiftCard({
    required this.id,
    required this.code,
    required this.initialGrosze,
    required this.balanceGrosze,
    required this.testMode,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.recipientName,
    this.message,
    this.lastUsedAt,
  });

  final String id;
  final String code;
  final int initialGrosze;
  final int balanceGrosze;
  final String? recipientName;
  final String? message;
  final bool testMode;
  final String status;
  final DateTime expiresAt;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  bool get isExpired => expiresAt.isBefore(DateTime.now());
  bool get isUsable => status == 'active' && !isExpired && balanceGrosze > 0;

  factory GiftCard.fromJson(Map<String, dynamic> json) {
    return GiftCard(
      id: json['id'] as String,
      code: json['code'] as String,
      initialGrosze: _toInt(json['initial_grosze']),
      balanceGrosze: _toInt(json['balance_grosze']),
      recipientName: json['recipient_name'] as String?,
      message: json['message'] as String?,
      testMode: json['test_mode'] == true,
      status: json['status'] as String? ?? 'active',
      expiresAt: _toDate(json['expires_at']),
      createdAt: _toDate(json['created_at']),
      lastUsedAt: _toDateOrNull(json['last_used_at']),
    );
  }
}

/// Stan połączenia na żywo z bazą rezerwacji.
enum LiveStatus {
  /// Łączymy się albo wracamy po zerwaniu.
  connecting,

  /// Zmiany rezerwacji przychodzą same.
  live,

  /// Brak połączenia: lista może być nieaktualna.
  offline,
}

/// Uprawnienie stanowiska. Działa, gdy pracownicy dostaną własne konta w panelu.
enum StaffPermission {
  reservations('reservations', 'Rezerwacje', 'Przyjmowanie, zmiana i odwoływanie rezerwacji', 'Sala'),
  floor('floor', 'Plan sali', 'Podgląd sali i wyłączanie stolików w Rezerwacjach', 'Sala'),
  floorEdit('floor_edit', 'Edycja sali', 'Zmiana układu stolików i stref', 'Sala'),
  orders('orders', 'Zamówienia', 'Nabijanie pozycji i wysyłanie ich na kuchnię', 'Zamówienia'),
  ordersClose('orders_close', 'Zamykanie rachunków', 'Przyjmowanie płatności i zamykanie rachunku', 'Zamówienia'),
  ordersCancel('orders_cancel', 'Anulowanie pozycji', 'Anulowanie pozycji, które są już na kuchni', 'Zamówienia'),
  deliveries('deliveries', 'Dostawy', 'Aplikacja dla kurierów', 'Zamówienia', soon: true),
  kitchen('kitchen', 'Kuchnia', 'Ekran zamówień na kuchni', 'Kuchnia'),
  kitchenSettings('kitchen_settings', 'Ustawienia kuchni', 'Progi czasu i pozycje ukryte na kuchni', 'Kuchnia'),
  staff('staff', 'Pracownicy', 'Dodawanie i edycja pracowników, ich statystyki', 'Zespół'),
  staffLogins('staff_logins', 'Kody pracowników', 'Podgląd i zmiana czterocyfrowych kodów pracowników', 'Zespół'),
  schedule('schedule', 'Grafik', 'Przyjmowanie, zmiana i odrzucanie godzin pracowników', 'Zespół'),
  timesheet('timesheet', 'Czas pracy', 'Podgląd i poprawianie zmian pracowników', 'Zespół'),
  positions('positions', 'Stanowiska', 'Tworzenie stanowisk i nadawanie uprawnień', 'Zespół'),
  profile('profile', 'Dane lokalu', 'Adres, godziny otwarcia i logo', 'Lokal'),
  menu('menu', 'Menu', 'Podgląd menu lokalu', 'Lokal'),
  menuEdit('menu_edit', 'Edycja menu', 'Dodawanie i zmiana dań, cen, sekcji i zdjęć', 'Lokal'),
  menuAvailability('menu_availability', 'Dostępność dań', 'Oznaczanie „Skończyło się” i „Znowu dostępne”', 'Lokal'),
  giftCards('gift_cards', 'Karty podarunkowe', 'Realizacja kart gości', 'Lokal'),
  reviews('reviews', 'Opinie', 'Odpowiadanie na opinie', 'Wyniki'),
  stats('stats', 'Statystyki', 'Sprzedaż, rezerwacje i historia zamówień', 'Wyniki');

  const StaffPermission(this.key, this.label, this.description, this.group, {this.soon = false});

  final String key;
  final String label;
  final String description;

  /// Część panelu, do której należy uprawnienie (nagłówek w oknie stanowiska).
  final String group;

  /// Funkcja, której jeszcze nie ma w panelu.
  final bool soon;

  static StaffPermission? fromKey(String key) {
    for (final p in values) {
      if (p.key == key) return p;
    }
    return null;
  }
}

/// Stanowisko pracownika. Systemowe (Kelner, Kucharz, Dostawca) ma każdy lokal
/// i nie da się ich usunąć, bo korzystają z nich pakiety. Własne dodaje właściciel.
class StaffPosition {
  const StaffPosition({
    required this.id,
    required this.name,
    required this.permissions,
    this.restaurantId,
    this.systemKey,
  });

  final String id;
  final String? restaurantId;

  /// waiter, cook albo courier przy stanowiskach systemowych.
  final String? systemKey;
  final String name;
  final List<StaffPermission> permissions;

  bool get isSystem => systemKey != null;

  /// Stanowisko „ALL”: zawsze wszystkie uprawnienia, także te dodane w przyszłości.
  bool get isAll => systemKey == 'all';

  factory StaffPosition.fromJson(Map<String, dynamic> json) {
    return StaffPosition(
      id: json['id'] as String,
      restaurantId: json['restaurant_id'] as String?,
      systemKey: json['system_key'] as String?,
      name: json['name'] as String,
      permissions: [
        for (final k in (json['permissions'] as List? ?? const []))
          ?StaffPermission.fromKey(k as String),
      ],
    );
  }
}

/// Dzień, w którym lokal jest zamknięty albo pracuje w innych godzinach niż zwykle.
class OpeningException {
  const OpeningException({
    required this.day,
    required this.closed,
    this.opens,
    this.closes,
    this.note,
  });

  final DateTime day;
  final bool closed;

  /// Godziny w formacie HH:MM, gdy lokal pracuje inaczej niż zwykle.
  final String? opens;
  final String? closes;
  final String? note;

  factory OpeningException.fromJson(Map<String, dynamic> json) {
    String? hm(Object? v) => v == null ? null : (v as String).substring(0, 5);
    return OpeningException(
      day: DateTime.parse(json['day'] as String),
      closed: json['closed'] != false,
      opens: hm(json['opens']),
      closes: hm(json['closes']),
      note: json['note'] as String?,
    );
  }
}

// ---------------------------------------------------------------
// Zamówienia
// ---------------------------------------------------------------

enum OrderItemStatus {
  fresh('new', 'Do wysłania'),
  sent('sent', 'Na kuchni'),
  ready('ready', 'Do wydania'),
  served('served', 'Wydane'),
  cancelled('cancelled', 'Anulowane');

  const OrderItemStatus(this.db, this.label);
  final String db;
  final String label;

  static OrderItemStatus fromDb(Object? value) =>
      values.firstWhere((s) => s.db == value, orElse: () => fresh);
}

enum PaymentMethod {
  cash('cash', 'Gotówka'),
  card('card', 'Karta'),
  giftCard('gift_card', 'Karta podarunkowa'),
  other('other', 'Inne');

  const PaymentMethod(this.db, this.label);
  final String db;
  final String label;

  static PaymentMethod? fromDb(Object? value) {
    for (final m in values) {
      if (m.db == value) return m;
    }
    return null;
  }
}

/// Pozycja na rachunku. Nazwa, wariant i cena są zapisane w chwili nabicia,
/// więc późniejsza zmiana menu nie zmienia rachunku.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.name,
    required this.unitPriceGrosze,
    required this.vatRate,
    required this.quantity,
    required this.course,
    required this.status,
    required this.createdAt,
    this.menuItemId,
    this.variant,
    this.addons = const [],
    this.note,
    this.sentAt,
    this.readyAt,
    this.recalledAt,
  });

  final String id;
  final String orderId;
  final String? menuItemId;
  final String name;
  final String? variant;
  final List<MenuOption> addons;

  /// Cena jednej sztuki razem z dodatkami.
  final int unitPriceGrosze;
  final int vatRate;
  final int quantity;
  final String? note;

  /// Kolejność wydawania: 1 przystawki, 2 dania główne i tak dalej.
  final int course;
  final OrderItemStatus status;
  final DateTime createdAt;
  final DateTime? sentAt;

  /// Kiedy kuchnia zbiła pozycję. Null dla pozycji, których kuchnia nie robi.
  final DateTime? readyAt;

  /// Kuchnia cofnęła zbitą pozycję i robi ją jeszcze raz.
  final DateTime? recalledAt;

  int get totalGrosze => unitPriceGrosze * quantity;

  /// Wariant i dodatki w jednym wierszu, np. „Duża, + skwarki”.
  String? get details {
    final parts = [
      ?variant,
      for (final a in addons) '+ ${a.name.toLowerCase()}',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      menuItemId: json['menu_item_id'] as String?,
      name: json['name'] as String,
      variant: json['variant'] as String?,
      addons: MenuOption.listFrom(json['addons']),
      unitPriceGrosze: _toInt(json['unit_price_grosze']),
      vatRate: _toInt(json['vat_rate'], 8),
      quantity: _toInt(json['quantity'], 1),
      note: json['note'] as String?,
      course: _toInt(json['course'], 1),
      status: OrderItemStatus.fromDb(json['status']),
      createdAt: _toDate(json['created_at']),
      sentAt: _toDateOrNull(json['sent_at']),
      readyAt: _toDateOrNull(json['ready_at']),
      recalledAt: _toDateOrNull(json['recalled_at']),
    );
  }
}

/// Rachunek przy stoliku: otwarty albo zamknięty (historia).
class PanelOrder {
  const PanelOrder({
    required this.id,
    required this.openedAt,
    required this.items,
    this.tableId,
    this.reservationId,
    this.note,
    this.status = 'open',
    this.closedAt,
    this.paymentMethod,
    this.giftCardGrosze,
  });

  final String id;
  final String? tableId;
  final String? reservationId;
  final String? note;
  final DateTime openedAt;
  final List<OrderItem> items;

  /// open, paid albo cancelled.
  final String status;
  final DateTime? closedAt;

  /// Jak gość zapłacił (resztę po karcie podarunkowej, jeśli z niej płacił).
  final PaymentMethod? paymentMethod;

  /// Kwota pobrana z karty podarunkowej.
  final int? giftCardGrosze;

  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';

  /// Pozycje zbite przez kuchnię, które kelner ma zanieść.
  int get ready => items.where((i) => i.status == OrderItemStatus.ready).length;

  /// Pozycje, które liczą się do rachunku.
  List<OrderItem> get active =>
      items.where((i) => i.status != OrderItemStatus.cancelled).toList();

  int get totalGrosze => active.fold(0, (sum, i) => sum + i.totalGrosze);

  /// Liczba nowych pozycji, które czekają na wysłanie na kuchnię.
  int get unsent => items.where((i) => i.status == OrderItemStatus.fresh).length;

  /// Kwota brutto w podziale na stawki VAT, do podsumowania rachunku.
  Map<int, int> get byVat {
    final map = <int, int>{};
    for (final i in active) {
      map[i.vatRate] = (map[i.vatRate] ?? 0) + i.totalGrosze;
    }
    return map;
  }

  factory PanelOrder.fromJson(Map<String, dynamic> json) {
    final items =
        (json['order_items'] as List? ?? const [])
            .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) {
            final byCourse = a.course.compareTo(b.course);
            return byCourse != 0 ? byCourse : a.createdAt.compareTo(b.createdAt);
          });
    return PanelOrder(
      id: json['id'] as String,
      tableId: json['table_id'] as String?,
      reservationId: json['reservation_id'] as String?,
      note: json['note'] as String?,
      openedAt: _toDate(json['opened_at']),
      items: items,
      status: json['status'] as String? ?? 'open',
      closedAt: _toDateOrNull(json['closed_at']),
      paymentMethod: PaymentMethod.fromDb(json['payment_method']),
      giftCardGrosze: json['gift_card_grosze'] == null ? null : _toInt(json['gift_card_grosze']),
    );
  }
}

/// Bilecik na ekranie kuchni: pozycje jednego stolika wysłane za jednym razem.
class KitchenTicket {
  const KitchenTicket({
    required this.orderId,
    required this.sentAt,
    required this.items,
    this.tableId,
    this.waiter,
  });

  final String orderId;
  final String? tableId;
  final DateTime sentAt;
  final List<OrderItem> items;

  /// Imię i nazwisko pracownika, który nabił pozycje (kilku: po przecinku).
  final String? waiter;

  /// Klucz bilecika: rachunek i chwila wysłania.
  String get key => '$orderId@${sentAt.millisecondsSinceEpoch}';

  /// Wiersze pozycji z bazy (razem z `orders(table_id)` i `menu_items(show_in_kitchen)`)
  /// pogrupowane w bileciki, najstarsze pierwsze. Bileciki, w których kuchnia zbiła już
  /// wszystko, znikają. Pozycje ukryte przed kuchnią (np. napoje) się nie pokazują.
  static List<KitchenTicket> fromRows(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final sent = row['sent_at'] as String?;
      if (sent == null) continue;
      final menu = row['menu_items'] as Map<String, dynamic>?;
      if (menu?['show_in_kitchen'] == false) continue;
      // Pozycje z jednego „Wyślij na kuchnię” mają ten sam czas wysłania.
      groups.putIfAbsent('${row['order_id']}@$sent', () => []).add(row);
    }
    final tickets = [
      for (final list in groups.values)
        KitchenTicket(
          orderId: list.first['order_id'] as String,
          tableId: (list.first['orders'] as Map<String, dynamic>?)?['table_id'] as String?,
          sentAt: _toDate(list.first['sent_at']),
          waiter: {
            for (final r in list)
              if ((r['member'] as Map<String, dynamic>?)?['name'] case final String name) name,
          }.join(', ').ifEmpty ??
              ((list.first['orders'] as Map<String, dynamic>?)?['opener'] as Map<String, dynamic>?)?['name']
                  as String?,
          items: list.map(OrderItem.fromJson).toList()
            ..sort((a, b) {
              final byCourse = a.course.compareTo(b.course);
              return byCourse != 0 ? byCourse : a.createdAt.compareTo(b.createdAt);
            }),
        ),
    ].where((t) => t.items.any((i) => i.status == OrderItemStatus.sent)).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return tickets;
  }
}

/// Ustawienia ekranu kuchni: po ilu minutach bilecik żółknie i czerwienieje.
class KitchenConfig {
  const KitchenConfig({this.warnMinutes = 4, this.lateMinutes = 6});

  final int warnMinutes;
  final int lateMinutes;

  factory KitchenConfig.fromJson(Map<String, dynamic> json) => KitchenConfig(
    warnMinutes: _toInt(json['kitchen_warn_minutes'], 4),
    lateMinutes: _toInt(json['kitchen_late_minutes'], 6),
  );
}

/// Średni czas od wysłania na kuchnię do zbicia bilecika, w sekundach.
class KitchenStats {
  const KitchenStats({
    this.todaySeconds,
    this.todayCount = 0,
    this.hourSeconds,
    this.hourCount = 0,
  });

  final int? todaySeconds;
  final int todayCount;
  final int? hourSeconds;
  final int hourCount;

  factory KitchenStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KitchenStats();
    int? seconds(Object? v) => v == null ? null : _toInt(v);
    return KitchenStats(
      todaySeconds: seconds(json['today_seconds']),
      todayCount: _toInt(json['today_count']),
      hourSeconds: seconds(json['hour_seconds']),
      hourCount: _toInt(json['hour_count']),
    );
  }
}

/// Pracownik zalogowany w zakładce panelu kodem QR z aplikacji Table for employees albo loginem i hasłem.
/// Panel pokazuje wtedy tylko zakładki z jego uprawnień.
class ActingMember {
  const ActingMember({
    required this.memberId,
    required this.name,
    required this.permissions,
    this.position,
    this.shiftStartedAt,
  });

  final String memberId;
  final String name;
  final String? position;
  final Set<String> permissions;
  final DateTime? shiftStartedAt;

  /// Właściciel odblokował zakładkę hasłem konta restauracji: pełny dostęp, bez pracownika.
  factory ActingMember.account() => ActingMember(
    memberId: '',
    name: 'Konto restauracji',
    position: 'pełny dostęp',
    permissions: {for (final p in StaffPermission.values) p.key},
  );

  bool get isAccount => memberId.isEmpty;

  /// Pracownik zapisywany przy zamówieniach. Konto restauracji: nikt.
  String? get dbMemberId => isAccount ? null : memberId;

  factory ActingMember.fromJson(Map<String, dynamic> json) => ActingMember(
    memberId: json['member_id'] as String,
    name: json['name'] as String,
    position: json['position'] as String?,
    permissions: {for (final p in json['permissions'] as List? ?? const []) p.toString()},
    shiftStartedAt: _toDateOrNull(json['shift_started_at']),
  );
}

enum PlannedShiftStatus {
  pending('Czeka na decyzję'),
  accepted('Przyjęte'),
  rejected('Odrzucone');

  const PlannedShiftStatus(this.label);
  final String label;
}

/// Godziny w grafiku. Pracownik zgłasza w aplikacji, od której do której może pracować,
/// przełożony przyjmuje (także ze zmienionymi godzinami) albo odrzuca. Po decyzji pracownik
/// nie może już zmienić tego dnia. Przełożony może też wpisać godziny sam.
class PlannedShift {
  const PlannedShift({
    required this.id,
    required this.memberId,
    required this.day,
    required this.starts,
    required this.ends,
    required this.status,
    this.requestedStarts,
    this.requestedEnds,
    this.note,
    this.answer,
  });

  final String id;
  final String memberId;
  final DateTime day;

  /// Godziny jako „HH:MM”: zgłoszone albo (po przyjęciu) zatwierdzone.
  final String starts;
  final String ends;
  final PlannedShiftStatus status;

  /// Co zgłosił pracownik. Null: godziny wpisał przełożony.
  final String? requestedStarts;
  final String? requestedEnds;

  /// Uwagi pracownika i odpowiedź przełożonego.
  final String? note;
  final String? answer;

  /// Przyjęte, ale z innymi godzinami, niż zgłosił pracownik.
  bool get changed =>
      status == PlannedShiftStatus.accepted &&
      requestedStarts != null &&
      (requestedStarts != starts || requestedEnds != ends);

  static String? _hm(Object? v) => v == null ? null : (v as String).substring(0, 5);

  factory PlannedShift.fromJson(Map<String, dynamic> json) => PlannedShift(
    id: json['id'] as String,
    memberId: json['member_id'] as String,
    day: DateTime.parse(json['day'] as String),
    starts: _hm(json['starts'])!,
    ends: _hm(json['ends'])!,
    status: PlannedShiftStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => PlannedShiftStatus.pending,
    ),
    requestedStarts: _hm(json['requested_starts']),
    requestedEnds: _hm(json['requested_ends']),
    note: json['note'] as String?,
    answer: json['answer'] as String?,
  );
}

/// Wyniki pracownika z ostatnich dni: czas pracy i sprzedaż.
class MemberStats {
  const MemberStats({
    this.seconds = 0,
    this.shifts = 0,
    this.weekSeconds = 0,
    this.openSince,
    this.lastShift,
    this.ordersOpened = 0,
    this.ordersClosed = 0,
    this.revenueGrosze = 0,
    this.items = 0,
    this.topItems = const [],
    this.planned = 0,
  });

  final int seconds;
  final int shifts;
  final int weekSeconds;
  final DateTime? openSince;
  final DateTime? lastShift;
  final int ordersOpened;
  final int ordersClosed;
  final int revenueGrosze;
  final int items;
  final List<(String, int)> topItems;

  /// Zaplanowane zmiany od dziś.
  final int planned;

  int get averageOrder => ordersClosed == 0 ? 0 : (revenueGrosze / ordersClosed).round();

  factory MemberStats.fromJson(Map<String, dynamic> json) => MemberStats(
    seconds: _toInt(json['seconds']),
    shifts: _toInt(json['shifts']),
    weekSeconds: _toInt(json['week_seconds']),
    openSince: _toDateOrNull(json['open_since']),
    lastShift: _toDateOrNull(json['last_shift']),
    ordersOpened: _toInt(json['orders_opened']),
    ordersClosed: _toInt(json['orders_closed']),
    revenueGrosze: _toInt(json['revenue']),
    items: _toInt(json['items']),
    topItems: [
      for (final t in (json['top_items'] as List? ?? const []).cast<Map<String, dynamic>>())
        (t['name'] as String, _toInt(t['quantity'])),
    ],
    planned: _toInt(json['planned']),
  );
}

/// Zmiana pracownika: od zeskanowania kodu do końca pracy.
class StaffShift {
  const StaffShift({
    required this.id,
    required this.memberId,
    required this.startedAt,
    this.endedAt,
    this.source = 'scan',
  });

  final String id;
  final String memberId;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// scan: kod QR, panel: wpisana ręcznie przez kierownika.
  final String source;

  bool get isOpen => endedAt == null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  factory StaffShift.fromJson(Map<String, dynamic> json) => StaffShift(
    id: json['id'] as String,
    memberId: json['member_id'] as String,
    startedAt: _toDate(json['started_at']),
    endedAt: _toDateOrNull(json['ended_at']),
    source: json['source'] as String? ?? 'scan',
  );
}

/// Punkt wykresu sprzedaży: dzień, godzina albo dzień tygodnia.
class SalesPoint {
  const SalesPoint(this.key, this.revenue, this.orders);

  final int key;
  final int revenue;
  final int orders;
}

/// Sprzedaż w wybranym okresie z porównaniem do okresu wcześniej.
class SalesStats {
  const SalesStats({
    required this.revenue,
    required this.orders,
    required this.items,
    required this.giftCards,
    required this.cancelled,
    required this.prevRevenue,
    required this.prevOrders,
    required this.daily,
    required this.hourly,
    required this.weekdays,
    required this.topItems,
    required this.payments,
    required this.vat,
    required this.staff,
    this.avgTableMinutes,
    this.kitchenSeconds,
  });

  final int revenue;
  final int orders;
  final int items;
  final int giftCards;
  final int cancelled;
  final int prevRevenue;
  final int prevOrders;
  final int? avgTableMinutes;
  final int? kitchenSeconds;
  final List<(DateTime, int, int)> daily;
  final List<SalesPoint> hourly;
  final List<SalesPoint> weekdays;

  /// Nazwa, sztuki, przychód.
  final List<(String, int, int)> topItems;

  /// Forma płatności, kwota, liczba rachunków.
  final List<(PaymentMethod?, int, int)> payments;

  /// Stawka VAT i kwota brutto.
  final List<(int, int)> vat;

  /// Pracownik, przychód, liczba rachunków.
  final List<(String, int, int)> staff;

  int get averageCheck => orders == 0 ? 0 : revenue ~/ orders;

  factory SalesStats.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => (j[k] as List? ?? const []).cast<Map<String, dynamic>>();
    int? opt(Object? v) => v == null ? null : _toInt(v);
    return SalesStats(
      revenue: _toInt(j['revenue']),
      orders: _toInt(j['orders']),
      items: _toInt(j['items']),
      giftCards: _toInt(j['gift_cards']),
      cancelled: _toInt(j['cancelled']),
      prevRevenue: _toInt(j['prev_revenue']),
      prevOrders: _toInt(j['prev_orders']),
      avgTableMinutes: opt(j['avg_table_minutes']),
      kitchenSeconds: opt(j['kitchen_seconds']),
      daily: [
        for (final d in list('daily'))
          (DateTime.parse(d['day'] as String), _toInt(d['revenue']), _toInt(d['orders'])),
      ],
      hourly: [for (final h in list('hourly')) SalesPoint(_toInt(h['hour']), _toInt(h['revenue']), _toInt(h['orders']))],
      weekdays: [
        for (final w in list('weekdays')) SalesPoint(_toInt(w['weekday']), _toInt(w['revenue']), _toInt(w['orders'])),
      ],
      topItems: [for (final t in list('top_items')) (t['name'] as String, _toInt(t['quantity']), _toInt(t['revenue']))],
      payments: [
        for (final p in list('payments')) (PaymentMethod.fromDb(p['method']), _toInt(p['amount']), _toInt(p['orders'])),
      ],
      vat: [for (final v in list('vat')) (_toInt(v['rate']), _toInt(v['gross']))],
      staff: [for (final s in list('staff')) (s['name'] as String, _toInt(s['revenue']), _toInt(s['orders']))],
    );
  }
}

extension _IfEmpty on String {
  /// Pusty napis zamienia na null.
  String? get ifEmpty => isEmpty ? null : this;
}
