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
  });

  final String id;
  final String name;
  final String city;
  final bool isPro;
  final StaffRole role;

  /// Kierownik i właściciel zmieniają salę, menu, dane lokalu i odpowiadają na opinie.
  bool get canManage => role != StaffRole.staff;

  factory PanelRestaurant.fromJson(Map<String, dynamic> json) {
    return PanelRestaurant(
      id: json['id'] as String,
      name: json['name'] as String,
      city: json['city'] as String? ?? '',
      isPro: json['plan'] == 'pro',
      role: StaffRole.fromDb(json['role']),
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
    this.joinGroup,
    this.draftKey,
  });

  /// Null dla stolika dodanego w edytorze i jeszcze niezapisanego.
  final String? id;

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
  }) {
    return DiningTable(
      id: id,
      draftKey: draftKey,
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
    required this.priceLevel,
    required this.hours,
    this.description,
  });

  final String id;
  final String name;
  final String cuisine;
  final String? description;
  final String address;
  final String city;
  final String phone;
  final int slotIntervalMin;
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
      priceLevel: _toInt(json['price_level'], 2),
      hours: hours,
    );
  }
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.sectionId,
    required this.name,
    required this.priceGrosze,
    required this.allergens,
    required this.position,
    this.description,
  });

  final String id;
  final String sectionId;
  final String name;
  final String? description;
  final int priceGrosze;
  final List<String> allergens;
  final int position;

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      id: json['id'] as String,
      sectionId: json['section_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      priceGrosze: _toInt(json['price_grosze']),
      allergens: _toStrings(json['allergens']),
      position: _toInt(json['position']),
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
