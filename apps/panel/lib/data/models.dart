/// Modele panelu restauracji. Nazwy pól w JSON odpowiadają funkcjom `panel_*`
/// i tabelom z supabase/migrations.
library;

import 'package:table_core/table_core.dart';

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
    this.discountLabel,
    this.depositGrosze = 0,
    this.depositStatus = 'none',
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

  /// Kod rabatowy wpisany przy rezerwacji w aplikacji, np. „REVE10 −10%”. Null: bez kodu.
  final String? discountLabel;

  /// Zadatek z aplikacji: kwota i stan (none, pending, paid, refunded).
  final int depositGrosze;
  final String depositStatus;

  String? get depositLabel => switch (depositStatus) {
    'paid' => 'opłacony',
    'pending' => 'nieopłacony',
    'refunded' => 'zwrócony',
    _ => null,
  };

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
      discountLabel: json['discount_code'] == null
          ? null
          : '${json['discount_code']} ${json['discount_kind'] == 'percent' ? '−${json['discount_value']}%' : '−${(_toInt(json['discount_value']) / 100).toStringAsFixed(2).replaceAll('.', ',')} zł'}',
      depositGrosze: _toInt(json['deposit_grosze']),
      depositStatus: json['deposit_status'] as String? ?? 'none',
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
    this.depositMinParty,
    this.depositPerPersonGrosze,
    required this.priceLevel,
    required this.hours,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.schedulePeriod = 'week',
    this.scheduleDeadlineDow,
    this.scheduleDeadlineTime = '20:00',
    this.inventoryPeriod = 'week',
    this.delivery = const DeliverySettings(),
  });

  /// Dostawa i odbiór osobisty.
  final DeliverySettings delivery;

  final String? logoUrl;

  /// Zdjęcie lokalu na liście lokali i na stronie lokalu w aplikacji Table.
  final String? coverUrl;

  /// Na jaki okres pracownicy zgłaszają godziny: week, two_weeks albo month.
  final String schedulePeriod;

  /// Termin zgłaszania dyspozycyjności: dzień tygodnia (1 = poniedziałek) i godzina przed początkiem okresu.
  /// Null: bez terminu.
  final int? scheduleDeadlineDow;
  final String scheduleDeadlineTime;

  /// Co ile lokal robi inwentaryzację: day, week, two_weeks albo month.
  final String inventoryPeriod;

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

  /// Zadatek przy rezerwacji w aplikacji: od ilu osób i ile za osobę. Null: bez zadatku.
  final int? depositMinParty;
  final int? depositPerPersonGrosze;
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
      depositMinParty: json['deposit_min_party'] == null ? null : _toInt(json['deposit_min_party']),
      depositPerPersonGrosze: json['deposit_per_person_grosze'] == null ? null : _toInt(json['deposit_per_person_grosze']),
      priceLevel: _toInt(json['price_level'], 2),
      hours: hours,
      logoUrl: json['logo_url'] as String?,
      coverUrl: json['cover_url'] as String?,
      schedulePeriod: json['schedule_period'] as String? ?? 'week',
      scheduleDeadlineDow: json['schedule_deadline_dow'] == null ? null : _toInt(json['schedule_deadline_dow']),
      scheduleDeadlineTime: (json['schedule_deadline_time'] as String?)?.substring(0, 5) ?? '20:00',
      inventoryPeriod: json['inventory_period'] as String? ?? 'week',
      delivery: DeliverySettings.fromJson(json),
    );
  }
}

/// Dostawa i odbiór osobisty lokalu. Karta online jest zawsze, gotówkę i kartę przy odbiorze lokal włącza sam.
class DeliverySettings {
  const DeliverySettings({
    this.deliveryEnabled = false,
    this.pickupEnabled = false,
    this.cash = true,
    this.card = true,
    this.feeGrosze = 0,
    this.minGrosze = 0,
    this.area,
    this.deliveryPlatforms = const [],
    this.maxItems,
    this.maxPerItem,
  });

  final bool deliveryEnabled;
  final bool pickupEnabled;

  /// Gotówka przy dostawie albo odbiorze.
  final bool cash;

  /// Karta przy odbiorze: dostawcy przy drzwiach albo w lokalu (0074, `takeaway_card`).
  final bool card;
  final int feeGrosze;

  /// Minimalna wartość zamówienia z dostawą (bez opłaty za dostawę).
  final int minGrosze;

  /// Opis obszaru dostawy dla gości, np. „Białystok, do 5 km”.
  final String? area;


  /// Platformy dostaw (np. Glovo, Uber Eats, Wolt) z kwotami w podsumowaniu dnia.
  final List<String> deliveryPlatforms;

  /// Limity zamówień z aplikacji (0070): sztuk w zamówieniu i sztuk jednego dania. Null: bez limitu.
  final int? maxItems;
  final int? maxPerItem;

  bool get any => deliveryEnabled || pickupEnabled;

  factory DeliverySettings.fromJson(Map<String, dynamic> json) => DeliverySettings(
    deliveryEnabled: json['delivery_enabled'] == true,
    pickupEnabled: json['pickup_enabled'] == true,
    cash: json['takeaway_cash'] != false,
    card: json['takeaway_card'] != false,
    feeGrosze: _toInt(json['delivery_fee_grosze']),
    minGrosze: _toInt(json['delivery_min_grosze']),
    area: json['delivery_area'] as String?,
    deliveryPlatforms: [for (final n in json['delivery_platforms'] as List? ?? const []) '$n'],
    maxItems: json['takeaway_max_items'] == null ? null : _toInt(json['takeaway_max_items']),
    maxPerItem: json['takeaway_max_per_item'] == null ? null : _toInt(json['takeaway_max_per_item']),
  );
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
    this.ingredients = const [],
  });

  final String id;
  final String sectionId;

  /// Receptura: składniki z inwentaryzacji zużywane na jedną porcję. Widzi ją tylko panel.
  final List<RecipeLine> ingredients;

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

  /// Warianty mają różne ceny, więc cena zaczyna się „od”. Jeden wariant (np. Tonic 200 ml) ma jedną cenę.
  bool get priceVaries => variants.map((v) => v.priceGrosze).toSet().length > 1;

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
      ingredients: [
        for (final r in json['menu_item_ingredients'] as List? ?? const [])
          RecipeLine.fromJson(r as Map<String, dynamic>),
      ],
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
    this.likes = 0,
    this.likesTotal = 0,
  });

  final DateTime day;

  /// Nowe polubienia lokalu w aplikacji Table tego dnia i wszystkie polubienia na koniec dnia.
  final int likes;
  final int likesTotal;
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
      likes: _toInt(json['likes']),
      likesTotal: _toInt(json['likes_total']),
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
    this.extraPositionIds = const [],
    this.dismissedAt,
  });

  final String id;

  /// Imię i nazwisko razem, do list i kalendarza.
  final String name;
  final String? firstName;
  final String? lastName;
  final String? positionId;

  /// Dodatkowe stanowiska (np. kelner, który bywa też barmanem). Uprawnienia są sumą wszystkich.
  final List<String> extraPositionIds;

  /// Wszystkie stanowiska pracownika: główne i dodatkowe.
  List<String> get positionIds => [?positionId, for (final p in extraPositionIds) if (p != positionId) p];

  /// Nazwa stanowiska zapisana przy pracowniku. Aktualną nazwę bierzemy ze stanowisk.
  final String? position;
  final String? phone;

  /// Numer koloru 0–7 w kalendarzu.
  final int color;
  final bool active;

  /// Konto, którym pracownik loguje się do panelu. Null, gdy nie ma konta.
  final String? userId;

  /// Kiedy pracownik został zwolniony (0075). Zwolniony jest też nieaktywny; godziny pracy zostają.
  final DateTime? dismissedAt;
  bool get dismissed => dismissedAt != null;

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
      dismissedAt: _toDateOrNull(json['dismissed_at']),
      extraPositionIds: [
        for (final p in json['staff_member_positions'] as List? ?? const [])
          if (p is Map && p['position_id'] is String) p['position_id'] as String,
      ],
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
  deliveries('deliveries', 'Dostawy (kurier)', 'Kursy w aplikacji Table for employees, kolejka dostawców', 'Zamówienia'),
  fleet('fleet', 'Flota', 'Pojazdy dostawców: dodawanie, zmiana i przypisanie', 'Zamówienia'),
  kitchen('kitchen', 'Kuchnia', 'Ekran zamówień na kuchni', 'Kuchnia'),
  kitchenSettings('kitchen_settings', 'Ustawienia kuchni', 'Progi czasu i pozycje ukryte na kuchni', 'Kuchnia'),
  serving('serving', 'Kompletowanie', 'Dania gotowe z kuchni do zaniesienia gościom i spakowania na wynos', 'Zamówienia'),
  staff('staff', 'Pracownicy', 'Dodawanie i edycja pracowników, ich statystyki', 'Zespół'),
  staffLogins('staff_logins', 'Kody pracowników', 'Podgląd i zmiana czterocyfrowych kodów pracowników', 'Zespół'),
  schedule('schedule', 'Grafik', 'Przyjmowanie, zmiana i odrzucanie godzin pracowników', 'Zespół'),
  timesheet('timesheet', 'Czas pracy', 'Podgląd i poprawianie zmian pracowników', 'Zespół'),
  positions('positions', 'Stanowiska', 'Tworzenie stanowisk i nadawanie uprawnień', 'Zespół'),
  announcements(
    'announcements',
    'Informacje dla pracowników',
    'Pisanie, zmiana i planowanie informacji dla pracowników',
    'Zespół',
  ),
  profile('profile', 'Dane lokalu', 'Adres, godziny otwarcia i logo', 'Lokal'),
  menu('menu', 'Menu', 'Podgląd menu lokalu', 'Lokal'),
  menuEdit('menu_edit', 'Edycja menu', 'Dodawanie i zmiana dań, cen, sekcji i zdjęć', 'Lokal'),
  menuAvailability('menu_availability', 'Dostępność dań', 'Oznaczanie „Skończyło się” i „Znowu dostępne”', 'Lokal'),
  activity('activity', 'Logi i Time Machine', 'Zdarzenia dnia i stan sali w wybranej chwili', 'Lokal'),
  inventoryEdit('inventory_edit', 'Edytowanie składników', 'Dodawanie, zmiana i usuwanie składników', 'Inwentaryzacja'),
  inventoryCount('inventory_count', 'Wpisywanie ilości składników', 'Spis ilości składników w inwentaryzacji', 'Inwentaryzacja'),
  customers('customers', 'Baza klientów', 'Goście lokalu: wizyty, wydatki, nieobecności', 'Wyniki'),
  reviews('reviews', 'Opinie', 'Odpowiadanie na opinie', 'Wyniki'),
  stats('stats', 'Statystyki', 'Sprzedaż, rezerwacje i historia zamówień', 'Wyniki'),
  revenue('revenue', 'Przychody', 'Obrót i średni rachunek w historii zamówień', 'Management'),
  dayClose('day_close', 'Podsumowanie dnia', 'Raporty z kasy i terminali, petty cash', 'Management'),
  discounts('discounts', 'Kody rabatowe', 'Tworzenie i wyłączanie kodów rabatowych', 'Management'),
  export('export', 'Eksport', 'Pliki dla księgowej: sprzedaż, VAT i czas pracy', 'Management');

  const StaffPermission(this.key, this.label, this.description, this.group);

  final String key;
  final String label;
  final String description;

  /// Część panelu, do której należy uprawnienie (nagłówek w oknie stanowiska).
  final String group;

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

/// Jedna płatność rachunku: forma, kwota (bez napiwku) i napiwek.
class PaymentPart {
  const PaymentPart(this.method, this.amountGrosze, {this.tipGrosze = 0});

  final PaymentMethod method;
  final int amountGrosze;
  final int tipGrosze;

  Map<String, dynamic> toJson() => {'method': method.db, 'amount': amountGrosze, 'tip': tipGrosze};

  factory PaymentPart.fromJson(Map<String, dynamic> json) => PaymentPart(
    PaymentMethod.fromDb(json['method']) ?? PaymentMethod.other,
    _toInt(json['amount_grosze']),
    tipGrosze: _toInt(json['tip_grosze']),
  );
}

/// Ile do zapłaty za rachunek: suma, rabat z kodu rezerwacji i kwota po rabacie.
class OrderDue {
  const OrderDue({
    required this.totalGrosze,
    required this.discountGrosze,
    required this.dueGrosze,
    this.depositGrosze = 0,
    this.label,
    this.percent,
    this.code,
    this.reservationCode,
    this.minGrosze,
    this.missingGrosze,
  });

  final int totalGrosze;
  final int discountGrosze;

  /// Kod działa od tej kwoty rachunku. Null: kod bez progu albo bez kodu.
  final int? minGrosze;

  /// Ile brakuje do progu kodu; rabatu jeszcze nie ma. Null: próg osiągnięty albo go nie ma.
  final int? missingGrosze;

  /// Kod rabatowy wpisany przy rachunku (zastępuje kod z rezerwacji). Null: brak.
  final String? code;

  /// Kod z rezerwacji gościa (wpisany w aplikacji Table).
  final String? reservationCode;

  /// Zadatek opłacony w aplikacji przy rezerwacji, odjęty od rachunku (tylko przy zamknięciu całości).
  final int depositGrosze;
  final int dueGrosze;
  final String? label;

  /// Rabat procentowy liczy się też od części rachunku. Null: brak albo rabat kwotowy.
  final int? percent;

  /// Rabat i kwota do zapłaty za część rachunku o wartości [part].
  (int discount, int due) forPart(int part) {
    final p = percent;
    final discount = p == null ? 0 : (part * p / 100).round().clamp(0, part);
    return (discount, part - discount);
  }

  factory OrderDue.fromJson(Map<String, dynamic> json) => OrderDue(
    totalGrosze: _toInt(json['total']),
    discountGrosze: _toInt(json['discount']),
    depositGrosze: _toInt(json['deposit']),
    dueGrosze: _toInt(json['due']),
    label: json['discount_label'] as String?,
    percent: json['discount_percent'] == null ? null : _toInt(json['discount_percent']),
    code: json['discount_code'] as String?,
    reservationCode: json['reservation_code'] as String?,
    minGrosze: json['discount_min'] == null ? null : _toInt(json['discount_min']),
    missingGrosze: json['discount_missing'] == null ? null : _toInt(json['discount_missing']),
  );
}

/// Kwota w złotych do napisów o progach kodów: „100 zł” albo „99,50 zł”.
String discountMoney(int grosze) =>
    grosze % 100 == 0 ? '${grosze ~/ 100} zł' : '${(grosze / 100).toStringAsFixed(2).replaceAll('.', ',')} zł';

/// Zasada automatycznego kodu osobistego dla gościa: po zrealizowanej rezerwacji albo po zweryfikowanej opinii.
/// Gość widzi kod w aplikacji Table („Moje” → „Kody”), aktywuje go przy stoliku (15 minut) i pokazuje kelnerowi.
class GuestCodeRule {
  const GuestCodeRule({
    required this.event,
    required this.active,
    required this.percent,
    required this.value,
    required this.validDays,
    this.minGrosze,
    this.issued = 0,
    this.used = 0,
  });

  /// `reservation` albo `review`.
  final String event;
  final bool active;
  final bool percent;
  final int value;
  final int validDays;
  final int? minGrosze;

  /// Ile kodów lokal już dał i ile gości wykorzystało.
  final int issued;
  final int used;

  String get title => event == 'review' ? 'Po opinii' : 'Po zrealizowanej rezerwacji';

  String get description => event == 'review'
      ? 'Gość, który wystawi zweryfikowaną opinię (z rezerwacji albo paragonu), dostaje kod do tego lokalu.'
      : 'Gość z kontem w aplikacji dostaje kod do tego lokalu, gdy jego rezerwacja się zakończy.';

  String get valueText => percent ? '−$value%' : '−${discountMoney(value)}';

  GuestCodeRule copyWith({bool? active, bool? percent, int? value, int? validDays, int? Function()? minGrosze}) =>
      GuestCodeRule(
        event: event,
        active: active ?? this.active,
        percent: percent ?? this.percent,
        value: value ?? this.value,
        validDays: validDays ?? this.validDays,
        minGrosze: minGrosze == null ? this.minGrosze : minGrosze(),
        issued: issued,
        used: used,
      );

  factory GuestCodeRule.fromJson(Map<String, dynamic> json) => GuestCodeRule(
    event: json['event'] as String,
    active: json['active'] == true,
    percent: json['kind'] != 'amount',
    value: _toInt(json['value'], 10),
    validDays: _toInt(json['valid_days'], 30),
    minGrosze: json['min_total'] == null ? null : _toInt(json['min_total']),
    issued: _toInt(json['issued']),
    used: _toInt(json['used']),
  );
}

/// Podpowiedź przy wpisywaniu kodu rabatowego do rachunku: kod lokalu, który działa dziś.
class DiscountHint {
  const DiscountHint({
    required this.code,
    required this.percent,
    required this.value,
    this.note,
    this.usesLeft,
    this.minGrosze,
  });

  final String code;
  final bool percent;
  final int value;
  final String? note;

  /// Ile użyć zostało. Null: bez limitu.
  final int? usesLeft;

  /// Rabat od tej kwoty rachunku. Null: od każdej.
  final int? minGrosze;

  String get valueText => percent ? '−$value%' : '−${(value / 100).toStringAsFixed(2).replaceAll('.', ',')} zł';

  factory DiscountHint.fromJson(Map<String, dynamic> json) => DiscountHint(
    code: json['code'] as String,
    percent: json['kind'] == 'percent',
    value: _toInt(json['value']),
    note: (json['note'] as String?)?.ifEmpty,
    usesLeft: json['uses_left'] == null ? null : _toInt(json['uses_left']),
    minGrosze: json['min_total'] == null ? null : _toInt(json['min_total']),
  );
}

/// Podział kwoty na [people] równych części; grosze reszty dostają pierwsze osoby.
List<int> splitEqually(int amount, int people) {
  final n = people < 1 ? 1 : people;
  final base = amount ~/ n;
  final rest = amount % n;
  return [for (var i = 0; i < n; i++) base + (i < rest ? 1 : 0)];
}

/// Kod rabatowy lokalu, wpisywany przez gościa przy rezerwacji w aplikacji Table.
class DiscountCode {
  const DiscountCode({
    required this.id,
    required this.code,
    required this.percent,
    required this.value,
    required this.active,
    required this.uses,
    this.validFrom,
    this.validUntil,
    this.maxUses,
    this.note,
    this.createdBy,
    this.minGrosze,
    this.maxPerGuest,
  });

  final String id;
  final String code;

  /// Rabat działa od tej kwoty rachunku (przed rabatem). Null: od każdej kwoty.
  final int? minGrosze;

  /// Ile razy jeden gość z kontem w aplikacji może użyć kodu. Null: bez limitu. [maxUses] to limit łączny.
  final int? maxPerGuest;

  /// Rabat procentowy (value = procent). False: kwotowy (value w groszach).
  final bool percent;
  final int value;
  final bool active;
  final int uses;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int? maxUses;
  final String? note;
  final String? createdBy;

  /// Rabat do pokazania, np. „−10%” albo „−20,00 zł”.
  String get valueText => percent ? '−$value%' : '−${(value / 100).toStringAsFixed(2).replaceAll('.', ',')} zł';

  /// Kod przestał działać: wyłączony, po terminie albo wykorzystany.
  bool get expired =>
      !active ||
      (validUntil != null && validUntil!.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))) ||
      (maxUses != null && uses >= maxUses!);

  factory DiscountCode.fromJson(Map<String, dynamic> json) => DiscountCode(
    id: json['id'] as String,
    code: json['code'] as String,
    percent: json['kind'] == 'percent',
    value: _toInt(json['value']),
    active: json['active'] != false,
    uses: _toInt(json['uses']),
    validFrom: json['valid_from'] == null ? null : DateTime.parse(json['valid_from'] as String),
    validUntil: json['valid_until'] == null ? null : DateTime.parse(json['valid_until'] as String),
    maxUses: json['max_uses'] == null ? null : _toInt(json['max_uses']),
    note: json['note'] as String?,
    createdBy: json['created_by_name'] as String?,
    minGrosze: json['min_total_grosze'] == null ? null : _toInt(json['min_total_grosze']),
    maxPerGuest: json['max_uses_per_guest'] == null ? null : _toInt(json['max_uses_per_guest']),
  );
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
    this.servedAt,
    this.changes = const [],
    this.guestNo,
  });

  final String id;
  final String orderId;
  final String? menuItemId;

  /// Osoba przy stoliku (1, 2, 3...), do podziału rachunku. Null: pozycja wspólna.
  final int? guestNo;

  /// Zmiany składników („bez cebuli”, „więcej sera”).
  final List<ItemChange> changes;
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

  /// Kiedy pozycję wydano gościom (Kompletowanie albo kelner). Null, dopóki nie jest wydana.
  final DateTime? servedAt;

  int get totalGrosze => unitPriceGrosze * quantity;

  /// Wariant, dodatki i zmiany składników w jednym wierszu, np. „Duża, + skwarki, bez: cebula”.
  String? get details {
    final parts = [
      ?variant,
      for (final a in addons) '+ ${a.name.toLowerCase()}',
      for (final c in changes) c.label,
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
      servedAt: _toDateOrNull(json['served_at']),
      changes: ItemChange.listFrom(json['changes']),
      guestNo: json['guest_no'] == null ? null : _toInt(json['guest_no']),
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
    this.kind = OrderKind.dineIn,
    this.number,
    this.discountGrosze = 0,
    this.discountLabel,
    this.depositGrosze = 0,
    this.tipGrosze = 0,
    this.payments = const [],
    this.deliveryFeeGrosze = 0,
    this.customerName,
    this.customerCompany,
    this.customerPhone,
    this.deliveryAddress,
    this.guests,
    this.guestsSkipped = false,
  });

  /// Liczba gości przy stoliku. Null: nie wpisano (pominięte, gdy [guestsSkipped]).
  final int? guests;
  final bool guestsSkipped;

  /// Zadatek z rezerwacji odjęty od rachunku.
  final int depositGrosze;

  /// Opłata za dostawę (zamówienie z dostawą).
  final int deliveryFeeGrosze;

  /// Klient zamówienia na wynos.
  final String? customerName;
  final String? customerCompany;
  final String? customerPhone;
  final String? deliveryAddress;

  final String id;

  /// Rabat z kodu rezerwacji, np. „REVE10 (−10%)”, i napiwki ze wszystkich płatności.
  final int discountGrosze;
  final String? discountLabel;
  final int tipGrosze;

  /// Płatności zamkniętego rachunku (kilka przy podziale). Starsze rachunki: puste, jest [paymentMethod].
  final List<PaymentPart> payments;

  /// Na sali, dostawa albo odbiór osobisty.
  final OrderKind kind;

  /// Numer zamówienia na wynos w danym dniu, np. 12.
  final int? number;
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

  /// Od kiedy stolik czeka na jedzenie: najstarsza pozycja wysłana na kuchnię, a jeszcze niewydana.
  DateTime? get waitingSince {
    DateTime? since;
    for (final i in items) {
      if (i.status != OrderItemStatus.sent && i.status != OrderItemStatus.ready) continue;
      final at = i.sentAt ?? i.createdAt;
      if (since == null || at.isBefore(since)) since = at;
    }
    return since;
  }

  /// Kwota do zapłaty z dostawą (historia zamówień).
  int get billGrosze => totalGrosze + deliveryFeeGrosze;

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
      kind: OrderKind.from(json['kind']),
      number: json['number'] == null ? null : _toInt(json['number']),
      discountGrosze: _toInt(json['discount_grosze']),
      discountLabel: json['discount_label'] as String?,
      depositGrosze: _toInt(json['deposit_grosze']),
      tipGrosze: _toInt(json['tip_grosze']),
      payments: [
        for (final p in (json['order_payments'] as List? ?? const []))
          PaymentPart.fromJson(p as Map<String, dynamic>),
      ],
      deliveryFeeGrosze: _toInt(json['delivery_fee_grosze']),
      customerName: json['customer_name'] as String?,
      customerCompany: json['customer_company'] as String?,
      customerPhone: json['customer_phone'] as String?,
      deliveryAddress: json['delivery_address'] as String?,
      guests: json['guests'] == null ? null : _toInt(json['guests']),
      guestsSkipped: json['guests_skipped'] == true,
    );
  }

  /// „Dostawa #12” albo „Na wynos #12”. Null przy rachunku ze stolika.
  String? get takeawayLabel => kind == OrderKind.dineIn ? null : '${kind.label} #${number ?? '?'}';
}

enum OrderKind {
  dineIn('dine_in', 'Na sali'),
  delivery('delivery', 'Dostawa'),
  pickup('pickup', 'Na wynos');

  const OrderKind(this.db, this.label);
  final String db;
  final String label;

  static OrderKind from(Object? value) =>
      values.firstWhere((k) => k.db == value, orElse: () => OrderKind.dineIn);
}

/// Adres, który gość wpisał w ustawieniach aplikacji Table (Baza klientów, nad notatkami).
class GuestAppAddress {
  const GuestAppAddress({
    required this.street,
    this.house,
    this.postcode,
    this.city,
    this.entryCode,
    this.building,
    this.updatedAt,
  });

  final String street;
  final String? house;
  final String? postcode;
  final String? city;

  /// Kod do klatki i jak rozpoznać budynek (dla dostawcy).
  final String? entryCode;
  final String? building;
  final DateTime? updatedAt;

  /// „Lipowa 14/3, 15-001 Białystok”.
  String get line => [
    [street, ?house].join(' '),
    [?postcode, ?city].join(' '),
  ].where((p) => p.isNotEmpty).join(', ');

  static GuestAppAddress? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['street'] == null) return null;
    return GuestAppAddress(
      street: json['street'] as String,
      house: json['house'] as String?,
      postcode: json['postcode'] as String?,
      city: json['city'] as String?,
      entryCode: json['entry_code'] as String?,
      building: json['building'] as String?,
      updatedAt: _toDateOrNull(json['updated_at']),
    );
  }
}

/// Do kogo idzie informacja dla pracowników.
enum AnnouncementAudience {
  all('all', 'Wszyscy'),
  working('working', 'Pracujący tego dnia'),
  positions('positions', 'Stanowiska'),
  members('members', 'Osoby');

  const AnnouncementAudience(this.db, this.label);
  final String db;
  final String label;

  static AnnouncementAudience from(Object? value) =>
      values.firstWhere((a) => a.db == value, orElse: () => AnnouncementAudience.all);
}

/// Informacja dla pracowników (Pracownicy → Informacje dla pracowników, Table for employees).
/// Pisze ją osoba z uprawnieniem „Informacje dla pracowników”, reszta tylko czyta. [publishAt] w przyszłości:
/// zaplanowana, odbiorcy zobaczą ją dopiero wtedy.
class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.publishAt,
    this.positionIds = const [],
    this.memberIds = const [],
    this.authorMember,
    this.authorName,
    this.read = false,
    this.forMe = false,
    this.recipients = 0,
    this.reads = 0,
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final List<String> positionIds;
  final List<String> memberIds;
  final DateTime publishAt;
  final String? authorMember;
  final String? authorName;

  /// Zalogowany pracownik już ją przeczytał.
  final bool read;

  /// Jest do zalogowanego pracownika.
  final bool forMe;

  /// Ilu pracowników ją dostanie (albo dostało) i ilu przeczytało.
  final int recipients;
  final int reads;

  bool isPublished([DateTime? now]) => !publishAt.isAfter(now ?? DateTime.now());

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    audience: AnnouncementAudience.from(json['audience']),
    positionIds: [for (final p in json['position_ids'] as List? ?? const []) '$p'],
    memberIds: [for (final m in json['member_ids'] as List? ?? const []) '$m'],
    publishAt: _toDate(json['publish_at']),
    authorMember: json['author_member'] as String?,
    authorName: json['author_name'] as String?,
    read: json['read'] == true,
    forMe: json['for_me'] == true,
    recipients: _toInt(json['recipients']),
    reads: _toInt(json['reads']),
  );
}

/// Niezamknięte zamówienie (Management → Niezamknięte zamówienia): rachunek albo zamówienie na wynos,
/// z etapem i osobą, która je otworzyła.
class UnclosedOrder {
  const UnclosedOrder({required this.order, this.stage, this.openedBy});

  final PanelOrder order;

  /// Etap zamówienia na wynos. Null: rachunek na sali.
  final TakeawayStage? stage;

  /// Kto otworzył rachunek albo przyjął zamówienie w panelu.
  final String? openedBy;

  /// Zamówienie z wcześniejszego dnia niż [now].
  bool fromEarlierDay(DateTime now) {
    final o = order.openedAt.toLocal();
    return DateTime(o.year, o.month, o.day).isBefore(DateTime(now.year, now.month, now.day));
  }

  factory UnclosedOrder.fromJson(Map<String, dynamic> json) {
    final order = PanelOrder.fromJson(json);
    return UnclosedOrder(
      order: order,
      stage: order.kind == OrderKind.dineIn ? null : TakeawayStage.from(json['fulfillment']),
      openedBy: (json['opener'] as Map<String, dynamic>?)?['name'] as String?,
    );
  }
}

/// Etap zamówienia na wynos.
enum TakeawayStage {
  draft('draft', 'Szkic'),
  awaitingPayment('awaiting_payment', 'Czeka na płatność'),
  placed('placed', 'Nowe'),
  accepted('accepted', 'W przygotowaniu'),
  ready('ready', 'Gotowe'),
  onTheWay('on_the_way', 'W drodze'),
  delivered('delivered', 'Zakończone'),
  rejected('rejected', 'Odrzucone'),
  cancelled('cancelled', 'Odwołane');

  const TakeawayStage(this.db, this.label);
  final String db;
  final String label;

  bool get finished => this == delivered || this == rejected || this == cancelled;

  static TakeawayStage from(Object? value) =>
      values.firstWhere((s) => s.db == value, orElse: () => TakeawayStage.placed);
}

const _weekdaysShort = ['pn', 'wt', 'śr', 'cz', 'pt', 'sb', 'nd'];

/// Godzina zamówienia na godzinę: „18:30”, „jutro 18:30” albo „pt 9.10 18:30”.
String dayTimeLabel(DateTime t, [DateTime? now]) {
  final l = t.toLocal();
  final n = now ?? DateTime.now();
  final hm = '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  final days = DateTime(l.year, l.month, l.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (days == 0) return hm;
  if (days == 1) return 'jutro $hm';
  return '${_weekdaysShort[l.weekday - 1]} ${l.day}.${l.month.toString().padLeft(2, '0')} $hm';
}

/// Zamówienie gościa z aplikacji Table: dostawa albo odbiór osobisty.
class TakeawayOrder {
  const TakeawayOrder({
    required this.id,
    required this.kind,
    required this.number,
    required this.stage,
    required this.openedAt,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.feeGrosze,
    required this.cash,
    required this.paid,
    this.cardOnDelivery = false,
    this.testPayment = false,
    this.address,
    this.addressNote,
    this.note,
    this.promisedAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.closedAt,
    this.courierId,
    this.courierName,
    this.rejectReason,
    this.courseId,
    this.company,
    this.nip,
    this.staffNote,
    this.street,
    this.house,
    this.city,
    this.prepaid = false,
    this.fromApp = true,
    this.scheduledFor,
    this.kitchenAt,
  });

  final String id;
  final OrderKind kind;
  final int number;
  final TakeawayStage stage;

  /// Zamówienie na godzinę (odbiór albo dostawa). Null: jak najszybciej.
  final DateTime? scheduledFor;

  /// Przyjęte zamówienie na godzinę, które jeszcze nie weszło do kuchni: wtedy wejdzie.
  final DateTime? kitchenAt;

  /// Nazwa lokalu albo firmy (zamiast imienia i nazwiska) i NIP, z zamówienia przyjętego w panelu.
  final String? company;
  final String? nip;

  /// Komentarz widoczny tylko dla pracowników.
  final String? staffNote;

  /// Adres z formularza panelu (ulica, numer domu albo lokalu, miasto).
  final String? street;
  final String? house;
  final String? city;

  /// Opłacone wcześniej (zamówienie przyjęte w panelu, np. przelewem); dostawca nic nie pobiera.
  final bool prepaid;

  /// Złożone przez gościa w aplikacji Table (inaczej przyjęte w panelu).
  final bool fromApp;

  /// Kurs dostawcy: dostawy połączone w jeden kurs mają ten sam numer i jadą z jednym dostawcą.
  final String? courseId;
  final DateTime openedAt;
  final String customerName;
  final String customerPhone;
  final String? address;

  /// Uwagi do adresu (kod do klatki, piętro), tylko przy dostawie (0074).
  final String? addressNote;

  /// Uwagi do zamówienia.
  final String? note;
  final List<OrderItem> items;
  final int feeGrosze;

  /// Gotówka przy dostawie/odbiorze.
  final bool cash;

  /// Karta przy dostawie/odbiorze (terminal dostawcy albo w lokalu, 0074).
  final bool cardOnDelivery;
  final bool paid;
  final bool testPayment;
  final DateTime? promisedAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? closedAt;
  final String? courierId;
  final String? courierName;
  final String? rejectReason;

  String get label => '${kind.label} #$number';

  /// Czeka na swoją porę: kuchnia go jeszcze nie robi, dostawca nie jest przydzielony.
  bool waitingForKitchen([DateTime? now]) => kitchenAt != null && kitchenAt!.isAfter(now ?? DateTime.now());

  /// Dostawę można połączyć z inną albo wyjąć z kursu, dopóki jest w lokalu.
  bool get canJoinCourse =>
      kind == OrderKind.delivery && (stage == TakeawayStage.accepted || stage == TakeawayStage.ready);

  List<OrderItem> get active => items.where((i) => i.status != OrderItemStatus.cancelled).toList();

  int get totalGrosze => feeGrosze + active.fold(0, (sum, i) => sum + i.totalGrosze);

  factory TakeawayOrder.fromJson(Map<String, dynamic> json) => TakeawayOrder(
    id: json['id'] as String,
    kind: OrderKind.from(json['kind']),
    number: _toInt(json['number']),
    stage: TakeawayStage.from(json['fulfillment']),
    openedAt: _toDate(json['opened_at']),
    customerName: json['customer_name'] as String? ?? '',
    customerPhone: json['customer_phone'] as String? ?? '',
    address: json['delivery_address'] as String?,
    addressNote: (json['address_note'] as String?)?.ifEmpty,
    note: json['delivery_note'] as String?,
    items: [
      for (final i in json['order_items'] as List? ?? const []) OrderItem.fromJson(i as Map<String, dynamic>),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    feeGrosze: _toInt(json['delivery_fee_grosze']),
    cash: json['payment_choice'] == 'cash',
    cardOnDelivery: json['payment_choice'] == 'card_on_delivery',
    paid: json['payment_status'] == 'paid',
    testPayment: json['payment_test'] == true,
    promisedAt: _toDateOrNull(json['promised_at']),
    acceptedAt: _toDateOrNull(json['accepted_at']),
    pickedUpAt: _toDateOrNull(json['picked_up_at']),
    closedAt: _toDateOrNull(json['closed_at']),
    courierId: json['courier_member'] as String?,
    courierName: (json['courier'] as Map<String, dynamic>?)?['name'] as String?,
    rejectReason: json['reject_reason'] as String?,
    courseId: json['course_id'] as String?,
    company: (json['customer_company'] as String?)?.ifEmpty,
    nip: (json['customer_nip'] as String?)?.ifEmpty,
    staffNote: (json['staff_note'] as String?)?.ifEmpty,
    street: json['address_street'] as String?,
    house: json['address_house'] as String?,
    city: json['address_city'] as String?,
    prepaid: json['payment_choice'] == 'prepaid',
    fromApp: json['guest_id'] != null,
    scheduledFor: _toDateOrNull(json['scheduled_for']),
    kitchenAt: _toDateOrNull(json['kitchen_at']),
  );

  /// Imię i nazwisko (bez nazwy firmy, gdy jest tylko ona).
  String? get personName => company != null && customerName == company ? null : customerName.ifEmpty;

  /// Dane do formularza zamówienia z panelu.
  TakeawayCustomer get customer => TakeawayCustomer(
    name: personName ?? '',
    company: company ?? '',
    nip: nip ?? '',
    phone: customerPhone,
    street: street ?? '',
    house: house ?? '',
    city: city ?? '',
    note: note ?? '',
    addressNote: addressNote ?? '',
    staffNote: staffNote ?? '',
    paid: prepaid || (paid && !cash && !cardOnDelivery),
    cardOnDelivery: cardOnDelivery,
    scheduledFor: scheduledFor,
  );

  /// Płaci przy dostawie albo odbiorze (gotówką albo kartą), a nie z góry.
  bool get payOnDelivery => (cash || cardOnDelivery) && !prepaid;

  /// Jak gość płaci, np. „Gotówka u dostawcy”, „Karta przy odbiorze”, „Karta online · opłacone”.
  String get paymentLabel {
    final at = kind == OrderKind.delivery ? 'u dostawcy' : 'przy odbiorze';
    if (prepaid) return 'Opłacone wcześniej (przyjęte w panelu)';
    if (cash) return 'Gotówka $at';
    if (cardOnDelivery) return 'Karta $at';
    return 'Karta online · opłacone${testPayment ? ' (test)' : ''}';
  }
}

/// Dane klienta zamówienia przyjmowanego w panelu. Wymagane: imię i nazwisko albo nazwa lokalu, telefon,
/// opłacone albo do opłacenia, a przy dostawie ulica, numer domu albo lokalu i miasto.
class TakeawayCustomer {
  const TakeawayCustomer({
    this.name = '',
    this.company = '',
    this.nip = '',
    this.phone = '',
    this.street = '',
    this.house = '',
    this.city = '',
    this.note = '',
    this.addressNote = '',
    this.staffNote = '',
    this.paid,
    this.cardOnDelivery = false,
    this.scheduledFor,
  });

  final String name;
  final String company;
  final String nip;
  final String phone;
  final String street;
  final String house;
  final String city;

  /// Komentarz do zamówienia (dla kuchni i dostawcy) i komentarz tylko dla pracowników.
  final String note;
  final String staffNote;

  /// Uwagi do adresu (kod do klatki, piętro), tylko przy dostawie.
  final String addressNote;

  /// Null: jeszcze nie wybrano.
  final bool? paid;

  /// Do opłacenia kartą przy dostawie/odbiorze (inaczej gotówką).
  final bool cardOnDelivery;

  /// Na którą godzinę (odbiór albo dostawa). Null: jak najszybciej.
  final DateTime? scheduledFor;

  static String digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');

  /// Czego brakuje, żeby przyjąć zamówienie. Pusta lista: wszystko jest.
  List<String> missing(OrderKind kind) => [
    if (name.trim().isEmpty && company.trim().isEmpty) 'imię i nazwisko albo nazwa lokalu',
    if (digits(phone).length < 9) 'telefon',
    if (nip.trim().isNotEmpty && digits(nip).length != 10) 'NIP (10 cyfr)',
    if (kind == OrderKind.delivery && street.trim().isEmpty) 'ulica',
    if (kind == OrderKind.delivery && house.trim().isEmpty) 'numer domu albo lokalu',
    if (kind == OrderKind.delivery && city.trim().isEmpty) 'miasto',
    if (paid == null) 'opłacone czy do opłacenia',
  ];

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'company': company.trim(),
    'nip': digits(nip),
    'phone': phone.trim(),
    'street': street.trim(),
    'house': house.trim(),
    'city': city.trim(),
    'note': note.trim(),
    'address_note': addressNote.trim(),
    'staff_note': staffNote.trim(),
    'paid': paid,
    'payment': cardOnDelivery ? 'card_on_delivery' : 'cash',
    'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
  };
}

/// Wcześniejsze zamówienia klienta po numerze telefonu i dane z ostatniego.
class CustomerLookup {
  const CustomerLookup({
    this.orders = 0,
    this.spentGrosze = 0,
    this.lastAt,
    this.name,
    this.company,
    this.nip,
    this.street,
    this.house,
    this.city,
    this.address,
  });

  final int orders;
  final int spentGrosze;
  final DateTime? lastAt;
  final String? name;
  final String? company;
  final String? nip;
  final String? street;
  final String? house;
  final String? city;

  /// Adres z zamówienia z aplikacji (bez rozbicia na ulicę i numer).
  final String? address;

  bool get known => name != null || company != null;

  factory CustomerLookup.fromJson(Map<String, dynamic> json) => CustomerLookup(
    orders: _toInt(json['orders']),
    spentGrosze: _toInt(json['spent_grosze']),
    lastAt: _toDateOrNull(json['last_at']),
    name: (json['name'] as String?)?.ifEmpty,
    company: (json['company'] as String?)?.ifEmpty,
    nip: (json['nip'] as String?)?.ifEmpty,
    street: (json['street'] as String?)?.ifEmpty,
    house: (json['house'] as String?)?.ifEmpty,
    city: (json['city'] as String?)?.ifEmpty,
    address: (json['address'] as String?)?.ifEmpty,
  );
}

/// Dostawca na zmianie w kolejce lokalu.
class Courier {
  const Courier({required this.memberId, required this.name, required this.busy});

  final String memberId;
  final String name;
  final bool busy;

  factory Courier.fromJson(Map<String, dynamic> json) =>
      Courier(memberId: json['member_id'] as String, name: json['name'] as String, busy: json['busy'] == true);
}

/// Bilecik na ekranie kuchni: pozycje jednego stolika wysłane za jednym razem.
class KitchenTicket {
  const KitchenTicket({
    required this.orderId,
    required this.sentAt,
    required this.items,
    this.tableId,
    this.waiter,
    this.takeawayLabel,
    this.address,
    this.customer,
    this.note,
    this.scheduledFor,
  });

  final String orderId;
  final String? tableId;

  /// Zamówienie na godzinę: na którą ma być gotowe (odbiór) albo u klienta (dostawa).
  final DateTime? scheduledFor;

  /// Zamówienie na godzinę, którego pora wejścia do kuchni ([sentAt]) jeszcze nie przyszła.
  bool upcomingAt(DateTime now) => scheduledFor != null && sentAt.isAfter(now);

  /// Komentarz do zamówienia na wynos i komentarz tylko dla pracowników, razem.
  final String? note;

  /// „Dostawa #12” albo „Na wynos #12” zamiast stolika.
  final String? takeawayLabel;

  /// Adres dostawy (zamówienie z dostawą), żeby kuchnia wiedziała, dokąd jedzie paczka.
  final String? address;

  /// Imię gościa przy zamówieniu na wynos (dostawa i odbiór osobisty).
  final String? customer;
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
          takeawayLabel: switch (list.first['orders'] as Map<String, dynamic>?) {
            final o? when o['kind'] != null && o['kind'] != 'dine_in' =>
              '${OrderKind.from(o['kind']).label} #${o['number'] ?? '?'}',
            _ => null,
          },
          address: switch (list.first['orders'] as Map<String, dynamic>?) {
            final o? when o['kind'] == 'delivery' => (o['delivery_address'] as String?)?.ifEmpty,
            _ => null,
          },
          customer: switch (list.first['orders'] as Map<String, dynamic>?) {
            final o? when o['kind'] != null && o['kind'] != 'dine_in' =>
              (o['customer_company'] as String?)?.ifEmpty ?? (o['customer_name'] as String?)?.ifEmpty,
            _ => null,
          },
          note: switch (list.first['orders'] as Map<String, dynamic>?) {
            final o? when o['kind'] != null && o['kind'] != 'dine_in' => [
              ?(o['delivery_note'] as String?)?.ifEmpty,
              ?(o['staff_note'] as String?)?.ifEmpty,
            ].join(' · ').ifEmpty,
            _ => null,
          },
          sentAt: _toDate(list.first['sent_at']),
          scheduledFor: _toDateOrNull((list.first['orders'] as Map<String, dynamic>?)?['scheduled_for']),
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

/// Rodzaj pojazdu we flocie.
enum VehicleKind {
  car('car', 'Samochód'),
  scooter('scooter', 'Skuter'),
  bike('bike', 'Rower'),
  other('other', 'Inny');

  const VehicleKind(this.db, this.label);
  final String db;
  final String label;

  static VehicleKind from(Object? value) => values.firstWhere((k) => k.db == value, orElse: () => VehicleKind.other);
}

/// Pojazd dostawcy we flocie lokalu.
class Vehicle {
  const Vehicle({
    required this.id,
    required this.kind,
    required this.name,
    required this.active,
    this.plate,
    this.vin,
    this.memberId,
    this.note,
  });

  final String id;
  final VehicleKind kind;
  final String name;

  /// Numer rejestracyjny, np. „BI 12345”. Rower nie ma.
  final String? plate;

  /// Numer VIN: 17 znaków, litery i cyfry bez I, O, Q.
  final String? vin;

  /// Dostawca, który jeździ tym pojazdem.
  final String? memberId;
  final String? note;
  final bool active;

  factory Vehicle.fromJson(Map<String, dynamic> json) => Vehicle(
    id: json['id'] as String,
    kind: VehicleKind.from(json['kind']),
    name: json['name'] as String? ?? '',
    plate: json['plate'] as String?,
    vin: json['vin'] as String?,
    memberId: json['member_id'] as String?,
    note: json['note'] as String?,
    active: json['active'] != false,
  );
}

/// Auto dostawcy na dany dzień (Grafik albo Dostawy; dostawca sam wybiera je przy kontroli auta).
class VehicleDay {
  const VehicleDay({required this.day, required this.vehicleId, required this.memberId});

  final DateTime day;
  final String vehicleId;
  final String memberId;

  factory VehicleDay.fromJson(Map<String, dynamic> json) => VehicleDay(
    day: DateTime.parse(json['day'] as String),
    vehicleId: json['vehicle_id'] as String,
    memberId: json['member_id'] as String,
  );
}

/// Kontrola auta z aplikacji dostawcy: przebieg i cztery zdjęcia dookoła na początku albo na końcu zmiany.
class VehicleCheck {
  const VehicleCheck({
    required this.id,
    required this.vehicleId,
    required this.day,
    required this.start,
    required this.createdAt,
    this.memberName,
    this.odometerKm,
    this.photos = const [],
  });

  final String id;
  final String vehicleId;
  final DateTime day;

  /// Początek zmiany (przed pierwszym kursem). Fałsz: koniec zmiany.
  final bool start;
  final DateTime createdAt;
  final String? memberName;
  final int? odometerKm;

  /// Ścieżki zdjęć w zasobniku `vehicle-photos`: przód, tył, lewy bok, prawy bok.
  final List<String> photos;

  factory VehicleCheck.fromJson(Map<String, dynamic> json) => VehicleCheck(
    id: json['id'] as String,
    vehicleId: json['vehicle_id'] as String,
    day: DateTime.parse(json['day'] as String),
    start: json['kind'] == 'start',
    createdAt: _toDate(json['created_at']),
    memberName: json['member_name'] as String?,
    odometerKm: json['odometer_km'] == null ? null : _toInt(json['odometer_km']),
    photos: [for (final p in json['photos'] as List? ?? const []) '$p'],
  );
}

/// Gość lokalu w bazie klientów: z rezerwacji i zamówień na wynos.
class Customer {
  const Customer({
    required this.key,
    required this.name,
    required this.fromApp,
    required this.visits,
    required this.reservations,
    required this.noShows,
    required this.cancelled,
    required this.orders,
    required this.spentGrosze,
    this.phone,
    this.firstSeen,
    this.lastVisit,
    this.nextReservation,
    this.company,
    this.nip,
    this.address,
  });

  final String key;
  final String name;
  final String? phone;

  /// Z zamówień na wynos (baza dopisuje klienta sama): firma, NIP i ostatni adres dostawy.
  final String? company;
  final String? nip;
  final String? address;

  /// Gość ma konto w aplikacji Table.
  final bool fromApp;

  /// Rezerwacje, na które przyszedł (przy stoliku albo zakończone).
  final int visits;
  final int reservations;
  final int noShows;
  final int cancelled;

  /// Dostarczone i odebrane zamówienia na wynos.
  final int orders;
  final int spentGrosze;
  final DateTime? firstSeen;
  final DateTime? lastVisit;
  final DateTime? nextReservation;

  /// Wrócił co najmniej drugi raz.
  bool get returning => visits + orders >= 2;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    key: json['key'] as String,
    name: json['name'] as String? ?? 'Gość',
    phone: json['phone'] as String?,
    fromApp: json['from_app'] == true,
    visits: _toInt(json['visits']),
    reservations: _toInt(json['reservations']),
    noShows: _toInt(json['no_shows']),
    cancelled: _toInt(json['cancelled']),
    orders: _toInt(json['orders']),
    spentGrosze: _toInt(json['spent_grosze']),
    firstSeen: _toDateOrNull(json['first_seen']),
    lastVisit: _toDateOrNull(json['last_visit']),
    nextReservation: _toDateOrNull(json['next_reservation']),
    company: (json['company'] as String?)?.ifEmpty,
    nip: (json['nip'] as String?)?.ifEmpty,
    address: (json['address'] as String?)?.ifEmpty,
  );
}

/// Statystyki jednej osoby z zespołu w wybranym okresie.
class TeamStat {
  const TeamStat({
    required this.memberId,
    required this.name,
    required this.active,
    required this.seconds,
    required this.shifts,
    required this.ordersOpened,
    required this.ordersClosed,
    required this.revenueGrosze,
    required this.items,
    required this.deliveries,
    this.position,
    this.rateGrosze,
    this.earningsGrosze,
    this.contract = Contract.zlecenie,
    this.tipsCashGrosze = 0,
    this.tipsCardGrosze = 0,
    this.guests = 0,
    this.guestsSkipped = 0,
  });

  final String memberId;
  final String name;
  final String? position;
  final bool active;

  /// Napiwki z płatności, które przyjął pracownik: gotówką i kartą (z innymi).
  final int tipsCashGrosze;
  final int tipsCardGrosze;

  /// Goście przy stolikach, które otworzył, i ile razy pominął wpisanie ich liczby.
  final int guests;
  final int guestsSkipped;

  /// Stawka i zarobek brutto w miesiącu. Null bez stawki albo bez uprawnienia „Pracownicy”.
  final int? rateGrosze;
  final int? earningsGrosze;
  final Contract contract;
  final int seconds;
  final int shifts;
  final int ordersOpened;
  final int ordersClosed;
  final int revenueGrosze;
  final int items;
  final int deliveries;

  bool get hasActivity => seconds > 0 || ordersOpened > 0 || ordersClosed > 0 || items > 0 || deliveries > 0;

  factory TeamStat.fromJson(Map<String, dynamic> json) => TeamStat(
    memberId: json['member_id'] as String,
    name: json['name'] as String? ?? '',
    position: json['position_name'] as String?,
    active: json['active'] != false,
    seconds: _toInt(json['seconds']),
    shifts: _toInt(json['shifts']),
    ordersOpened: _toInt(json['orders_opened']),
    ordersClosed: _toInt(json['orders_closed']),
    revenueGrosze: _toInt(json['revenue']),
    items: _toInt(json['items']),
    deliveries: _toInt(json['deliveries']),
    rateGrosze: json['rate'] == null ? null : _toInt(json['rate']),
    earningsGrosze: json['earnings'] == null ? null : _toInt(json['earnings']),
    contract: Contract.from(json['contract']),
    tipsCashGrosze: _toInt(json['tips_cash']),
    tipsCardGrosze: _toInt(json['tips_card']),
    guests: _toInt(json['guests']),
    guestsSkipped: _toInt(json['guests_skipped']),
  );
}

/// Okres statystyk zespołu.
enum TeamPeriod {
  today('Dzisiaj'),
  week('7 dni'),
  twoWeeks('14 dni'),
  month('W tym miesiącu');

  const TeamPeriod(this.label);
  final String label;
}

/// Całość okresu w statystykach zespołu: obrót lokalu, goście, pominięcia i napiwki.
class TeamSummary {
  const TeamSummary({
    this.revenueGrosze = 0,
    this.tables = 0,
    this.guests = 0,
    this.skipped = 0,
    this.tipsCashGrosze = 0,
    this.tipsCardGrosze = 0,
  });

  final int revenueGrosze;

  /// Rachunki stolików (bez części rachunku).
  final int tables;
  final int guests;

  /// Rachunki, przy których pominięto liczbę gości.
  final int skipped;
  final int tipsCashGrosze;
  final int tipsCardGrosze;

  factory TeamSummary.fromJson(Map<String, dynamic> json) => TeamSummary(
    revenueGrosze: _toInt(json['revenue']),
    tables: _toInt(json['tables']),
    guests: _toInt(json['guests']),
    skipped: _toInt(json['skipped']),
    tipsCashGrosze: _toInt(json['tips_cash']),
    tipsCardGrosze: _toInt(json['tips_card']),
  );
}

/// Rodzaj umowy pracownika. Od niego zależy, ile z brutto zostaje na rękę.
enum Contract {
  zlecenie('zlecenie', 'Umowa zlecenie'),
  student('zlecenie_student', 'Zlecenie – student do 26 lat'),
  praca('praca', 'Umowa o pracę');

  const Contract(this.db, this.label);
  final String db;
  final String label;

  static Contract from(Object? value) => values.firstWhere((c) => c.db == value, orElse: () => Contract.zlecenie);
}

/// Stawka pracownika: brutto za godzinę i rodzaj umowy.
class StaffRate {
  const StaffRate({required this.grossGrosze, required this.contract});

  final int grossGrosze;
  final Contract contract;

  int get netGrosze => Payroll.hourlyNet(contract, grossGrosze);
}

/// Przeliczanie brutto ↔ netto (2026, w przybliżeniu, bez indywidualnych ulg, PPK i progu 32%).
/// Składki pracownika: emerytalna 9,76%, rentowa 1,5%, chorobowa 2,45% (razem 13,71%), zdrowotna 9% od podstawy
/// po składkach, PIT 12%. Zlecenie: koszty 20% podstawy. Umowa o pracę: koszty 250 zł i kwota zmniejszająca 300 zł
/// miesięcznie, więc stawkę godzinową liczymy dla pełnego etatu (168 h), a zarobek z całego miesiąca.
/// Student do 26 lat na zleceniu: bez składek i PIT, netto = brutto.
abstract final class Payroll {
  static const fullTimeHours = 168;

  /// Netto z brutto za miesiąc, w groszach.
  static int monthlyNet(Contract contract, int gross) {
    if (contract == Contract.student || gross <= 0) return gross < 0 ? 0 : gross;
    final social = gross * 0.1371;
    final base = gross - social;
    final health = base * 0.09;
    final double pit;
    if (contract == Contract.zlecenie) {
      pit = base * 0.8 * 0.12;
    } else {
      // Podstawa i podatek zaokrąglone do pełnych złotych, jak w PIT.
      final taxBase = ((base - 25000) / 100).round() * 100;
      pit = taxBase <= 0 ? 0 : ((taxBase * 0.12 - 30000) / 100).round() * 100.0;
    }
    final net = gross - social - health - (pit < 0 ? 0 : pit);
    return net.round();
  }

  /// Netto za godzinę z brutto za godzinę.
  static int hourlyNet(Contract contract, int grossHourly) => contract == Contract.praca
      ? (monthlyNet(contract, grossHourly * fullTimeHours) / fullTimeHours).round()
      : monthlyNet(contract, grossHourly);

  /// Brutto za godzinę, które da podane netto za godzinę (najmniejsze takie brutto).
  static int hourlyGross(Contract contract, int netHourly) {
    if (netHourly <= 0) return 0;
    if (contract == Contract.student) return netHourly;
    var low = netHourly;
    var high = netHourly * 3;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (hourlyNet(contract, mid) < netHourly) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}

/// Notatka przy kliencie albo pojeździe: treść, kto i kiedy napisał.
class Note {
  const Note({required this.id, required this.body, required this.createdAt, this.author, this.parentId});

  final String id;
  final String body;
  final String? author;
  final DateTime createdAt;

  /// Pojazd albo klucz klienta, do którego należy notatka.
  final String? parentId;

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    body: json['body'] as String? ?? '',
    author: json['author_name'] as String?,
    createdAt: _toDate(json['created_at']),
    parentId: (json['vehicle_id'] ?? json['customer_key']) as String?,
  );
}

/// Wizyta albo zamówienie klienta w historii.
class CustomerEvent {
  const CustomerEvent({required this.at, required this.kind, required this.status, required this.spentGrosze, this.partySize});

  final DateTime at;

  /// reservation, delivery albo pickup.
  final String kind;
  final String status;
  final int? partySize;
  final int spentGrosze;

  factory CustomerEvent.fromJson(Map<String, dynamic> json) => CustomerEvent(
    at: _toDate(json['at']),
    kind: json['kind'] as String? ?? 'reservation',
    status: json['status'] as String? ?? '',
    partySize: json['party_size'] == null ? null : _toInt(json['party_size']),
    spentGrosze: _toInt(json['spent_grosze']),
  );
}

/// Dane właściciela lokalu. Widać je tylko w panelu, u kierownika i właściciela.
class OwnerDetails {
  const OwnerDetails({
    this.ownerName,
    this.ownerPhone,
    this.ownerEmail,
    this.companyName,
    this.nip,
    this.companyAddress,
  });

  final String? ownerName;
  final String? ownerPhone;
  final String? ownerEmail;
  final String? companyName;
  final String? nip;
  final String? companyAddress;

  factory OwnerDetails.fromJson(Map<String, dynamic>? json) => OwnerDetails(
    ownerName: json?['owner_name'] as String?,
    ownerPhone: json?['owner_phone'] as String?,
    ownerEmail: json?['owner_email'] as String?,
    companyName: json?['company_name'] as String?,
    nip: json?['nip'] as String?,
    companyAddress: json?['company_address'] as String?,
  );
}

/// Karta na ekranie „Kompletowanie”: dania gotowe z kuchni dla jednego stolika albo zamówienie na wynos do spakowania.
class ServingTicket {
  const ServingTicket({
    required this.orderId,
    required this.items,
    required this.readySince,
    this.tableId,
    this.takeawayKind,
    this.takeawayNumber,
    this.promisedAt,
    this.waiter,
    this.cooking = 0,
  });

  final String orderId;
  final String? tableId;

  /// Dostawa albo odbiór osobisty. Null: rachunek na sali.
  final OrderKind? takeawayKind;
  final int? takeawayNumber;

  /// Na wynos: na którą lokal obiecał zamówienie.
  final DateTime? promisedAt;

  /// Na sali: gotowe pozycje do zaniesienia i te wydane w międzyczasie (wykreślone). Na wynos: wszystkie pozycje,
  /// także te jeszcze na kuchni.
  final List<OrderItem> items;

  /// Od kiedy czeka najstarsza gotowa pozycja.
  final DateTime readySince;

  /// Kto nabił zamówienie (kilka osób: po przecinku).
  final String? waiter;

  /// Na sali: ile sztuk z tego rachunku jest jeszcze na kuchni.
  final int cooking;

  bool get isTakeaway => takeawayKind != null;

  String? get takeawayLabel => takeawayKind == null ? null : '${takeawayKind!.label} #${takeawayNumber ?? '?'}';

  /// Na wynos: kuchnia zrobiła już wszystko, można pakować.
  bool get allReady => items.every((i) => i.status != OrderItemStatus.sent);

  List<String> get readyIds => [for (final i in items) if (i.status == OrderItemStatus.ready) i.id];

  /// Wiersze pozycji (z `orders` i `member`) zebrane w karty, najdłużej czekające pierwsze.
  /// Pokazują się rachunki, w których jest coś gotowego. Na wynos tylko zamówienia w przygotowaniu.
  /// Pozycje wydane, odkąd czeka najstarsza gotowa, zostają na karcie wykreślone (jak zbite na kuchni);
  /// wcześniejsze wydania (np. przystawki) nie.
  static List<ServingTicket> fromRows(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      groups.putIfAbsent(row['order_id'] as String, () => []).add(row);
    }
    final tickets = <ServingTicket>[];
    for (final list in groups.values) {
      final order = list.first['orders'] as Map<String, dynamic>? ?? const {};
      final kind = OrderKind.from(order['kind']);
      final takeaway = kind != OrderKind.dineIn;
      if (takeaway && order['fulfillment'] != 'accepted') continue;
      final items = list.map(OrderItem.fromJson).toList()
        ..sort((a, b) {
          final byCourse = a.course.compareTo(b.course);
          return byCourse != 0 ? byCourse : a.createdAt.compareTo(b.createdAt);
        });
      final all = [
        for (final i in items)
          if (i.status != OrderItemStatus.served) i,
      ];
      final ready = all.where((i) => i.status == OrderItemStatus.ready).toList();
      if (ready.isEmpty) continue;
      final since = ready
          .map((i) => i.readyAt ?? i.sentAt ?? i.createdAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final shown = [
        for (final i in items)
          if (i.status == OrderItemStatus.ready ||
              (i.status == OrderItemStatus.served && i.servedAt != null && !i.servedAt!.isBefore(since)))
            i,
      ];
      final waiter = {
        for (final r in list)
          if ((r['member'] as Map<String, dynamic>?)?['name'] case final String name) name,
      }.join(', ');
      tickets.add(
        ServingTicket(
          orderId: list.first['order_id'] as String,
          tableId: order['table_id'] as String?,
          takeawayKind: takeaway ? kind : null,
          takeawayNumber: takeaway ? _toInt(order['number']) : null,
          promisedAt: _toDateOrNull(order['promised_at']),
          items: takeaway ? all : shown,
          readySince: since,
          waiter: waiter.isNotEmpty
              ? waiter
              : (order['opener'] as Map<String, dynamic>?)?['name'] as String?,
          cooking: takeaway
              ? 0
              : all.where((i) => i.status == OrderItemStatus.sent).fold(0, (sum, i) => sum + i.quantity),
        ),
      );
    }
    return tickets..sort((a, b) => a.readySince.compareTo(b.readySince));
  }
}

/// Ustawienia ekranu kuchni: po ilu minutach bilecik żółknie i czerwienieje.
class KitchenConfig {
  const KitchenConfig({this.warnMinutes = 4, this.lateMinutes = 6, this.leadPickup = 20, this.leadDelivery = 40});

  final int warnMinutes;
  final int lateMinutes;

  /// Ile minut przed godziną zamówienie na godzinę wchodzi do kuchni: na wynos i z dostawą.
  final int leadPickup;
  final int leadDelivery;

  factory KitchenConfig.fromJson(Map<String, dynamic> json) => KitchenConfig(
    warnMinutes: _toInt(json['kitchen_warn_minutes'], 4),
    lateMinutes: _toInt(json['kitchen_late_minutes'], 6),
    leadPickup: _toInt(json['kitchen_lead_pickup_min'], 20),
    leadDelivery: _toInt(json['kitchen_lead_delivery_min'], 40),
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
    this.endedShiftStartedAt,
    this.shiftEndedAt,
  });

  final String memberId;
  final String name;
  final String? position;
  final Set<String> permissions;
  final DateTime? shiftStartedAt;

  /// Po „Zakończ zmianę”: od kiedy do kiedy trwała zakończona zmiana.
  final DateTime? endedShiftStartedAt;
  final DateTime? shiftEndedAt;

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
    endedShiftStartedAt: _toDateOrNull(json['ended_shift_started_at']),
    shiftEndedAt: _toDateOrNull(json['ended_at']),
  );
}

enum PlannedShiftStatus {
  pending('Czeka na decyzję'),
  accepted('Przyjęte'),
  rejected('Odrzucone'),
  off('Wolne'),

  /// Propozycja przełożonego: pracownik przyjmie ją albo odrzuci w aplikacji.
  proposed('Propozycja'),

  /// Pracownik nie może pracować (zgłosił to albo nie zgłosił dyspozycyjności).
  unavailable('Niedostępny');

  const PlannedShiftStatus(this.label);
  final String label;
}

/// Godziny w grafiku. Pracownik zgłasza w aplikacji, od której do której może pracować,
/// przełożony przyjmuje (także ze zmienionymi godzinami) albo odrzuca. Po decyzji pracownik
/// nie może już zmienić tego dnia. Przełożony może też wpisać godziny sam albo dać wolne.
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
    this.positionId,
  });

  final String id;
  final String memberId;
  final DateTime day;

  /// Stanowisko na ten dzień (pracownik może mieć kilka).
  final String? positionId;

  /// Godziny jako „HH:MM”: zgłoszone albo (po przyjęciu) zatwierdzone. Puste przy wolnym dniu.
  final String starts;
  final String ends;
  final PlannedShiftStatus status;

  /// Wolne dał przełożony. Wpis nie ma godzin.
  bool get off => status == PlannedShiftStatus.off;

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
    starts: _hm(json['starts']) ?? '',
    ends: _hm(json['ends']) ?? '',
    status: PlannedShiftStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => PlannedShiftStatus.pending,
    ),
    requestedStarts: _hm(json['requested_starts']),
    requestedEnds: _hm(json['requested_ends']),
    note: json['note'] as String?,
    answer: json['answer'] as String?,
    positionId: json['position_id'] as String?,
  );
}

/// Uwaga pracownika na tydzień (np. „w środę egzamin”), z aplikacji Table for employees.
class WeekNote {
  const WeekNote({required this.memberId, required this.weekStart, required this.note});

  final String memberId;
  final DateTime weekStart;
  final String note;

  factory WeekNote.fromJson(Map<String, dynamic> json) => WeekNote(
    memberId: json['member_id'] as String,
    weekStart: DateTime.parse(json['week_start'] as String),
    note: json['note'] as String,
  );
}

/// Okres grafiku lokalu (`restaurants.schedule_period`: week, two_weeks, month) przesunięty o [offset] okresów
/// od bieżącego. [to] to ostatni dzień okresu. Pary tygodni liczone od poniedziałku 5.01.2026, tak samo jak
/// w aplikacji Table for employees, żeby panel i telefon pokazywały ten sam okres.
({DateTime from, DateTime to}) schedulePeriod(String kind, int offset, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final monday = DateTime(today.year, today.month, today.day - (today.weekday - 1));
  switch (kind) {
    case 'month':
      final from = DateTime(today.year, today.month + offset);
      return (from: from, to: DateTime(from.year, from.month + 1, 0));
    case 'two_weeks':
      // Dni liczone w UTC, bo przejście na czas letni skraca lokalną różnicę o godzinę.
      final days = DateTime.utc(monday.year, monday.month, monday.day).difference(DateTime.utc(2026, 1, 5)).inDays;
      final index = (days / 14).floor() + offset;
      final from = DateTime(2026, 1, 5 + index * 14);
      return (from: from, to: DateTime(from.year, from.month, from.day + 13));
    default:
      final from = DateTime(monday.year, monday.month, monday.day + offset * 7);
      return (from: from, to: DateTime(from.year, from.month, from.day + 6));
  }
}

/// Poniedziałki tygodni, które obejmują okres (miesiąc zaczyna się i kończy w środku tygodnia).
List<DateTime> periodWeeks(({DateTime from, DateTime to}) period) {
  final first = DateTime(period.from.year, period.from.month, period.from.day - (period.from.weekday - 1));
  return [
    for (var w = first; !w.isAfter(period.to); w = DateTime(w.year, w.month, w.day + 7)) w,
  ];
}

/// Co przełożony zmienia w grafiku w trybie edycji. Zmiany czekają na „Zapisz” (`panel_save_schedule`).
enum ScheduleAction { accept, reject, add, propose, off, delete }

/// Klucz dnia pracownika w grafiku.
String scheduleKey(String memberId, DateTime day) => '$memberId@${day.year}-${day.month}-${day.day}';

/// Niezapisana zmiana jednego dnia pracownika.
class ScheduleChange {
  const ScheduleChange(
    this.action, {
    required this.memberId,
    required this.day,
    this.id,
    this.starts,
    this.ends,
    this.answer,
    this.positionId,
  });

  final ScheduleAction action;
  final String memberId;
  final DateTime day;

  /// Stanowisko na ten dzień.
  final String? positionId;

  /// Wpis w bazie, którego dotyczy zmiana (przyjęcie, odrzucenie, usunięcie).
  final String? id;
  final String? starts;
  final String? ends;
  final String? answer;

  String get key => scheduleKey(memberId, day);

  Map<String, dynamic> toJson() => {
    'action': action.name,
    'id': id,
    'member_id': memberId,
    'day': '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
    'starts': starts,
    'ends': ends,
    'answer': answer?.trim().ifEmpty,
    'position_id': positionId,
  };

  /// Jak dzień będzie wyglądał po zapisie (podgląd w grafiku). Null: dzień bez wpisu.
  PlannedShift? apply(PlannedShift? entry) {
    PlannedShift shift(PlannedShiftStatus status, {String starts = '', String ends = ''}) => PlannedShift(
      id: entry?.id ?? '',
      memberId: memberId,
      day: day,
      starts: starts,
      ends: ends,
      status: status,
      requestedStarts: entry?.requestedStarts,
      requestedEnds: entry?.requestedEnds,
      note: entry?.note,
      answer: answer?.trim().ifEmpty,
      positionId: positionId ?? entry?.positionId,
    );
    return switch (action) {
      ScheduleAction.delete => null,
      ScheduleAction.reject => shift(
        PlannedShiftStatus.rejected,
        starts: entry?.requestedStarts ?? entry?.starts ?? '',
        ends: entry?.requestedEnds ?? entry?.ends ?? '',
      ),
      ScheduleAction.accept || ScheduleAction.add => shift(
        PlannedShiftStatus.accepted,
        starts: starts ?? entry?.starts ?? '',
        ends: ends ?? entry?.ends ?? '',
      ),
      ScheduleAction.propose => shift(
        PlannedShiftStatus.proposed,
        starts: starts ?? entry?.starts ?? '',
        ends: ends ?? entry?.ends ?? '',
      ),
      ScheduleAction.off => shift(PlannedShiftStatus.off),
    };
  }
}

/// Tryb edycji grafiku: kto edytuje (numer pracownika, '' dla konta restauracji) i niezapisane zmiany.
class ScheduleDraft {
  const ScheduleDraft({this.editing = false, this.editor, this.changes = const {}});

  final bool editing;
  final String? editor;
  final Map<String, ScheduleChange> changes;
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
    this.rateGrosze,
    this.earningsGrosze,
    this.contract = Contract.zlecenie,
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

  /// Stawka brutto za godzinę i zarobek brutto w okresie (godziny × stawka). Null: bez stawki.
  final int? rateGrosze;
  final int? earningsGrosze;
  final Contract contract;

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
    rateGrosze: json['rate'] == null ? null : _toInt(json['rate']),
    earningsGrosze: json['earnings'] == null ? null : _toInt(json['earnings']),
    contract: Contract.from(json['contract']),
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
    this.originalStartedAt,
    this.originalEndedAt,
    this.editedAt,
  });

  final String id;
  final String memberId;
  final DateTime startedAt;
  final DateTime? endedAt;

  /// scan: kod QR, panel: wpisana ręcznie przez kierownika.
  final String source;

  /// Godziny przed pierwszą poprawką w panelu. Null: zmiany nikt nie poprawiał.
  final DateTime? originalStartedAt;
  final DateTime? originalEndedAt;
  final DateTime? editedAt;

  bool get isOpen => endedAt == null;

  bool get isEdited => editedAt != null && originalStartedAt != null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  /// Czas zmiany przed poprawką. Null: nie było poprawki albo zmiana wtedy jeszcze trwała.
  Duration? get originalDuration =>
      isEdited && originalEndedAt != null ? originalEndedAt!.difference(originalStartedAt!) : null;

  /// O ile poprawka wydłużyła (plus) albo skróciła (minus) zmianę.
  Duration? get editDifference => originalDuration == null || endedAt == null ? null : duration - originalDuration!;

  factory StaffShift.fromJson(Map<String, dynamic> json) => StaffShift(
    id: json['id'] as String,
    memberId: json['member_id'] as String,
    startedAt: _toDate(json['started_at']),
    endedAt: _toDateOrNull(json['ended_at']),
    source: json['source'] as String? ?? 'scan',
    originalStartedAt: _toDateOrNull(json['original_started_at']),
    originalEndedAt: _toDateOrNull(json['original_ended_at']),
    editedAt: _toDateOrNull(json['edited_at']),
  );
}

/// Punkt wykresu sprzedaży: dzień, godzina albo dzień tygodnia.
class SalesPoint {
  const SalesPoint(this.key, this.revenue, this.orders, {this.dineIn = 0, this.delivery = 0, this.pickup = 0});

  final int key;
  final int revenue;
  final int orders;

  /// Godziny: ile zamówień na sali, z dostawą i z odbiorem osobistym.
  final int dineIn;
  final int delivery;
  final int pickup;
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
    this.kindCounts = const [],
    this.memberCounts = const [],
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

  /// Rachunki okresu bez filtrów, do pól wyboru w panelu Statystyk: rodzaj zamówienia (dine_in, delivery,
  /// pickup) i liczba.
  final List<(String, int)> kindCounts;

  /// Jak [kindCounts], według tego, kto otworzył rachunek: id pracownika ('' bez przypisania), imię, liczba.
  final List<(String, String, int)> memberCounts;

  int get averageCheck => orders == 0 ? 0 : revenue ~/ orders;

  factory SalesStats.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => (j[k] as List? ?? const []).cast<Map<String, dynamic>>();
    List<Map<String, dynamic>> facets(String k) =>
        ((j['facets'] as Map?)?[k] as List? ?? const []).cast<Map<String, dynamic>>();
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
      hourly: [
        for (final h in list('hourly'))
          SalesPoint(
            _toInt(h['hour']),
            _toInt(h['revenue']),
            _toInt(h['orders']),
            dineIn: _toInt(h['dine_in']),
            delivery: _toInt(h['delivery']),
            pickup: _toInt(h['pickup']),
          ),
      ],
      weekdays: [
        for (final w in list('weekdays')) SalesPoint(_toInt(w['weekday']), _toInt(w['revenue']), _toInt(w['orders'])),
      ],
      topItems: [for (final t in list('top_items')) (t['name'] as String, _toInt(t['quantity']), _toInt(t['revenue']))],
      payments: [
        for (final p in list('payments')) (PaymentMethod.fromDb(p['method']), _toInt(p['amount']), _toInt(p['orders'])),
      ],
      vat: [for (final v in list('vat')) (_toInt(v['rate']), _toInt(v['gross']))],
      staff: [for (final s in list('staff')) (s['name'] as String, _toInt(s['revenue']), _toInt(s['orders']))],
      kindCounts: [
        for (final k in facets('kinds')) (k['kind'] as String, _toInt(k['orders'])),
      ],
      memberCounts: [
        for (final m in facets('members')) (m['id'] as String, m['name'] as String, _toInt(m['orders'])),
      ],
    );
  }
}

extension IfEmptyText on String {
  /// Pusty napis zamienia na null.
  String? get ifEmpty => isEmpty ? null : this;
}

// ---------------------------------------------------------------
// Inwentaryzacja
// ---------------------------------------------------------------

/// Jednostka pojemności składnika.
enum InventoryUnit {
  ml('ml', 'ml'),
  l('l', 'l'),
  g('g', 'g'),
  kg('kg', 'kg'),
  szt('szt', 'szt.');

  const InventoryUnit(this.key, this.label);

  final String key;
  final String label;

  static InventoryUnit fromKey(Object? key) =>
      values.firstWhere((u) => u.key == key, orElse: () => InventoryUnit.szt);

  /// Jednostki, w których można wpisać zużycie tego składnika: litry i mililitry, kilogramy i gramy.
  List<InventoryUnit> get compatible => switch (this) {
    InventoryUnit.l || InventoryUnit.ml => const [InventoryUnit.ml, InventoryUnit.l],
    InventoryUnit.kg || InventoryUnit.g => const [InventoryUnit.g, InventoryUnit.kg],
    InventoryUnit.szt => const [InventoryUnit.szt],
  };

  /// Mniejsza jednostka do wpisywania porcji: ml dla litrów, g dla kilogramów.
  InventoryUnit get portion => switch (this) {
    InventoryUnit.l => InventoryUnit.ml,
    InventoryUnit.kg => InventoryUnit.g,
    _ => this,
  };

  /// Ile mniejszych jednostek w jednej: 1000 dla l i kg, 1 dla pozostałych.
  double get portionFactor => this == InventoryUnit.l || this == InventoryUnit.kg ? 1000 : 1;
}

/// Składnik w recepturze dania: ile zużywa jedna porcja, w jednostce [unit].
class RecipeLine {
  const RecipeLine({required this.itemId, required this.amount, required this.unit, this.name});

  final String itemId;
  final double amount;
  final InventoryUnit unit;

  /// Nazwa składnika z inwentaryzacji (do zmian przy nabijaniu: „bez cebuli”).
  final String? name;

  Map<String, dynamic> toJson() => {'item_id': itemId, 'amount': amount, 'unit': unit.key};

  factory RecipeLine.fromJson(Map<String, dynamic> json) => RecipeLine(
    itemId: json['item_id'] as String,
    amount: _toDouble(json['amount']) ?? 0,
    unit: InventoryUnit.fromKey(json['unit']),
    name: (json['inventory_items'] as Map<String, dynamic>?)?['name'] as String?,
  );
}

/// Zmiana składnika w pozycji: „bez cebuli” albo „więcej sera”. [itemId] tylko dla składnika z receptury.
class ItemChange {
  const ItemChange(this.name, {required this.extra, this.itemId});

  final String name;

  /// true: więcej składnika, false: bez składnika.
  final bool extra;
  final String? itemId;

  String get label => extra ? 'więcej: ${name.toLowerCase()}' : 'bez: ${name.toLowerCase()}';

  Map<String, dynamic> toJson() => {'name': name, 'kind': extra ? 'extra' : 'without', 'item_id': itemId};

  static List<ItemChange> listFrom(Object? json) => [
    for (final c in json is List ? json : const [])
      if (c is Map && c['name'] is String)
        ItemChange(c['name'] as String, extra: c['kind'] == 'extra', itemId: c['item_id'] as String?),
  ];
}

/// Stan składnika teraz: ostatnia inwentaryzacja, w której go policzono, minus sprzedaż od tej chwili.
class InventoryStock {
  const InventoryStock({
    required this.itemId,
    required this.used,
    this.delivered = 0,
    this.removed = 0,
    this.counted,
    this.countedAt,
    this.stock,
  });

  final String itemId;

  /// Ilość z inwentaryzacji w jednostce składnika. Null: jeszcze go nie liczono.
  final double? counted;
  final DateTime? countedAt;

  /// Zużycie ze sprzedaży od inwentaryzacji (albo od dodania składnika).
  final double used;

  /// Dostawy i usunięcia od inwentaryzacji (0071).
  final double delivered;
  final double removed;

  /// Stan teraz. Null: bez inwentaryzacji nie wiadomo, od czego odjąć.
  final double? stock;

  factory InventoryStock.fromJson(Map<String, dynamic> json) => InventoryStock(
    itemId: json['item_id'] as String,
    counted: _toDouble(json['counted']),
    countedAt: _toDateOrNull(json['counted_at']),
    used: _toDouble(json['used']) ?? 0,
    delivered: _toDouble(json['delivered']) ?? 0,
    removed: _toDouble(json['removed']) ?? 0,
    stock: _toDouble(json['stock']),
  );
}

/// Co ile lokal robi inwentaryzację.
const inventoryPeriods = [
  ('day', 'Codziennie'),
  ('week', 'Co tydzień'),
  ('two_weeks', 'Co 2 tygodnie'),
  ('month', 'Co miesiąc'),
];

String inventoryPeriodLabel(String period) =>
    inventoryPeriods.firstWhere((p) => p.$1 == period, orElse: () => inventoryPeriods[1]).$2;

/// Ten sam dzień miesiąc później, a gdy go nie ma, ostatni dzień następnego miesiąca
/// (31 stycznia → 28 lutego, 31 marca → 30 kwietnia).
DateTime _addMonth(DateTime d) {
  final lastDay = DateTime(d.year, d.month + 2, 0).day;
  return DateTime(d.year, d.month + 1, d.day > lastDay ? lastDay : d.day);
}

/// Pierwszy dzień miesiąca daty [d].
DateTime monthStart(DateTime d) => DateTime(d.year, d.month);

/// Dzień następnej inwentaryzacji według okresu, licząc od dnia ostatniej. Null: jeszcze żadnej nie było.
DateTime? nextInventoryDay(String period, DateTime? last) {
  if (last == null) return null;
  return switch (period) {
    'day' => DateTime(last.year, last.month, last.day + 1),
    'two_weeks' => DateTime(last.year, last.month, last.day + 14),
    'month' => _addMonth(last),
    _ => DateTime(last.year, last.month, last.day + 7),
  };
}

/// Składnik lokalu. Ilość w spisie wpisuje się w opakowaniach (zgrzewki, worki, puszki) i resztą,
/// np. 11 zgrzewek po 12 szt. i 9 butelek.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.capacity,
    this.sort = 0,
    this.location,
    this.packName,
    this.containerId,
  });

  final String id;
  final String name;
  final InventoryUnit unit;

  /// Pojemność jednego opakowania w jednostce.
  final double capacity;
  final int sort;

  /// Gdzie stoi w lokalu, np. „Chłodnia”, „Magazyn suchy”, „Bar” (spis jest pogrupowany po lokalizacji).
  final String? location;

  /// Nazwa opakowania: zgrzewka, worek, puszka. Null: „op.”.
  final String? packName;

  /// Zwykły pojemnik do ważenia reszty (g, kg). Null: bez pojemnika.
  final String? containerId;

  /// Ważony w gramach (tylko wtedy pojemnik odejmuje się od wagi).
  bool get weighed => unit == InventoryUnit.g || unit == InventoryUnit.kg;

  /// Opakowanie, np. „zgrzewka 12 szt.”, „worek 25 kg” albo „0,7 l”.
  String get package => [?packName, '${inventoryNumber(capacity)} ${unit.label}'].join(' ');

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
    id: json['id'] as String,
    name: json['name'] as String,
    unit: InventoryUnit.fromKey(json['unit']),
    capacity: _toDouble(json['capacity']) ?? 0,
    sort: _toInt(json['sort']),
    location: json['location'] as String?,
    packName: json['pack_name'] as String?,
    containerId: json['container_id'] as String?,
  );
}

/// Pojemnik do ważenia (mały, średni, duży). Przy „ważone w pojemniku” jego waga odejmuje się sama.
class InventoryContainer {
  const InventoryContainer({required this.id, required this.name, required this.tareG});

  final String id;
  final String name;

  /// Waga pustego pojemnika w gramach.
  final double tareG;

  String get label => '$name (${inventoryGrouped(tareG)} g)';

  factory InventoryContainer.fromJson(Map<String, dynamic> json) => InventoryContainer(
    id: json['id'] as String,
    name: json['name'] as String,
    tareG: _toDouble(json['tare_g']) ?? 0,
  );
}

/// Powód usunięcia składnika z lokalu (nie sprzedaż).
enum RemovalReason {
  transfer('transfer', 'Przekazanie do innego lokalu'),
  giveBack('return', 'Zwrot do dostawcy'),
  loss('loss', 'Strata (zepsute, zbite)'),
  staff('staff', 'Posiłek pracowniczy'),
  other('other', 'Inny powód');

  const RemovalReason(this.key, this.label);

  final String key;
  final String label;

  static RemovalReason? fromKey(Object? key) {
    for (final r in values) {
      if (r.key == key) return r;
    }
    return null;
  }
}

/// Składnik w dostawie albo usunięciu.
class InventoryDocLine {
  const InventoryDocLine({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.capacity,
    required this.amount,
    this.packName,
    this.packages,
    this.loose,
  });

  final String itemId;
  final String name;
  final InventoryUnit unit;
  final double capacity;
  final String? packName;
  final double? packages;
  final double? loose;

  /// Razem w jednostce składnika.
  final double amount;

  /// „2 worki + 1500 g = 51,5 kg”.
  String get text {
    final parts = [
      if ((packages ?? 0) > 0) packCount(packages!, packName),
      if ((loose ?? 0) > 0) '${inventoryGrouped(loose!)} ${unit.portion.label}',
    ];
    final total = '${inventoryNumber(amount)} ${unit.label}';
    if (parts.isEmpty || (parts.length == 1 && parts.first == total)) return total;
    return '${parts.join(' + ')} = $total';
  }

  factory InventoryDocLine.fromJson(Map<String, dynamic> json) => InventoryDocLine(
    itemId: json['item_id'] as String,
    name: json['name'] as String,
    unit: InventoryUnit.fromKey(json['unit']),
    capacity: _toDouble(json['capacity']) ?? 0,
    amount: _toDouble(json['amount']) ?? 0,
    packName: json['pack_name'] as String?,
    packages: _toDouble(json['packages']),
    loose: _toDouble(json['loose']),
  );
}

/// Dostawa (kiedy przyjechała, co przyjechało) albo usunięcie (powód i wyjaśnienie). Zmienia stan od razu.
class InventoryDoc {
  const InventoryDoc({
    required this.id,
    required this.delivery,
    required this.happenedAt,
    required this.lines,
    this.reason,
    this.supplier,
    this.documentNo,
    this.note,
    this.createdBy,
  });

  final String id;

  /// Dostawa. Fałsz: usunięcie.
  final bool delivery;
  final DateTime happenedAt;
  final RemovalReason? reason;
  final String? supplier;
  final String? documentNo;
  final String? note;
  final String? createdBy;
  final List<InventoryDocLine> lines;

  /// „Dostawa · Makro · FV 12/10” albo „Usunięcie · Przekazanie do innego lokalu”.
  String get title => delivery
      ? ['Dostawa', ?supplier, ?documentNo].join(' · ')
      : ['Usunięcie', if (reason != null) reason!.label].join(' · ');

  factory InventoryDoc.fromJson(Map<String, dynamic> json) => InventoryDoc(
    id: json['id'] as String,
    delivery: json['kind'] == 'delivery',
    happenedAt: _toDate(json['happened_at']),
    reason: RemovalReason.fromKey(json['reason']),
    supplier: json['supplier'] as String?,
    documentNo: json['document_no'] as String?,
    note: json['note'] as String?,
    createdBy: json['created_by'] as String?,
    lines: [for (final l in json['lines'] as List? ?? const []) InventoryDocLine.fromJson(l as Map<String, dynamic>)],
  );
}

/// Ilość składnika w spisie. Jednostka i pojemność z chwili spisu.
class InventoryLine {
  const InventoryLine({
    required this.itemId,
    required this.name,
    required this.unit,
    required this.capacity,
    required this.quantity,
    this.packages,
    this.loose,
    this.countedBy,
    this.used,
    this.expected,
    this.previous,
    this.delivered,
    this.removed,
    this.location,
    this.packName,
    this.container,
    this.containerId,
    this.tare,
    this.gross,
  });

  final String itemId;
  final String name;
  final InventoryUnit unit;
  final double capacity;

  /// Liczba opakowań razem z resztą (np. 1,05 przy 1 opakowaniu 50 kg i 2500 g).
  final double quantity;

  /// Wpisane osobno: pełne opakowania i reszta w mniejszej jednostce ([InventoryUnit.portion]).
  /// Starsze spisy mają tylko [quantity].
  final double? packages;
  final double? loose;

  /// Razem w mniejszej jednostce, np. „52 500 g”.
  String get portionTotalText => '${inventoryGrouped(quantity * capacity * unit.portionFactor)} ${unit.portion.label}';
  final String? countedBy;

  /// Zużycie ze sprzedaży od poprzedniej inwentaryzacji, w jednostce pozycji. Null: nie było poprzedniej.
  final double? used;

  /// Stan wynikający z poprzedniej inwentaryzacji, sprzedaży, dostaw i usunięć („powinno być”).
  final double? expected;

  /// Poprzednia inwentaryzacja, dostawy i usunięcia od niej (w jednostce pozycji).
  final double? previous;
  final double? delivered;
  final double? removed;
  final String? location;
  final String? packName;

  /// Ważone w pojemniku: nazwa, waga pojemnika i waga z pojemnikiem (g). [loose] jest już bez pojemnika.
  final String? container;
  final String? containerId;
  final double? tare;
  final double? gross;

  double get total => quantity * capacity;

  /// Ile jest więcej (plus) albo mniej (minus), niż wynika ze sprzedaży. Null: nie było poprzedniej.
  double? get difference => expected == null ? null : total - expected!;

  /// Razem w jednostce, np. „1,75 l”.
  String get totalText => '${inventoryNumber(total)} ${unit.label}';

  factory InventoryLine.fromJson(Map<String, dynamic> json) => InventoryLine(
    itemId: json['item_id'] as String,
    name: json['name'] as String,
    unit: InventoryUnit.fromKey(json['unit']),
    capacity: _toDouble(json['capacity']) ?? 0,
    quantity: _toDouble(json['quantity']) ?? 0,
    packages: _toDouble(json['packages']),
    loose: _toDouble(json['loose']),
    countedBy: json['counted_by'] as String?,
    used: _toDouble(json['used']),
    expected: _toDouble(json['expected']),
    previous: _toDouble(json['previous']),
    delivered: _toDouble(json['delivered']),
    removed: _toDouble(json['removed']),
    location: json['location'] as String?,
    packName: json['pack_name'] as String?,
    container: json['container'] as String?,
    containerId: json['container_id'] as String?,
    tare: _toDouble(json['tare']),
    gross: _toDouble(json['gross']),
  );
}

/// Spis inwentaryzacji. Otwarty (bez [finishedAt]) może być najwyżej jeden na lokal.
class InventoryCount {
  const InventoryCount({
    required this.id,
    required this.startedAt,
    required this.lines,
    this.finishedAt,
    this.startedBy,
    this.finishedBy,
    this.periodFrom,
    this.docs = const [],
  });

  final String id;

  /// Koniec poprzedniej inwentaryzacji (początek okresu dostaw i usunięć w [docs]).
  final DateTime? periodFrom;

  /// Dostawy i usunięcia od poprzedniej inwentaryzacji do tej, od najstarszych.
  final List<InventoryDoc> docs;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? startedBy;
  final String? finishedBy;
  final List<InventoryLine> lines;

  bool get open => finishedAt == null;

  InventoryLine? line(String itemId) {
    for (final l in lines) {
      if (l.itemId == itemId) return l;
    }
    return null;
  }

  factory InventoryCount.fromJson(Map<String, dynamic> json) => InventoryCount(
    id: json['id'] as String,
    startedAt: _toDate(json['started_at']),
    finishedAt: _toDateOrNull(json['finished_at']),
    startedBy: json['started_by'] as String?,
    finishedBy: json['finished_by'] as String?,
    periodFrom: _toDateOrNull(json['period_from']),
    docs: [for (final d in json['docs'] as List? ?? const []) InventoryDoc.fromJson(d as Map<String, dynamic>)],
    lines: [
      for (final l in json['lines'] as List? ?? const []) InventoryLine.fromJson(l as Map<String, dynamic>),
    ],
  );
}

/// Wpis w petty cash: wydatek z kasy (np. cytryny) albo wpłata do kasy (np. drobne).
class PettyEntry {
  const PettyEntry({
    required this.id,
    required this.out,
    required this.description,
    required this.amountGrosze,
    required this.createdAt,
    this.author,
  });

  final String id;

  /// Wydatek (pieniądze wyszły z kasy). False: wpłata do kasy.
  final bool out;
  final String description;
  final int amountGrosze;
  final DateTime createdAt;
  final String? author;

  factory PettyEntry.fromJson(Map<String, dynamic> json) => PettyEntry(
    id: json['id'] as String,
    out: json['kind'] != 'in',
    description: json['description'] as String? ?? '',
    amountGrosze: _toInt(json['amount_grosze']),
    createdAt: _toDate(json['created_at']),
    author: json['author_name'] as String?,
  );
}

/// Raport z terminala płatniczego na koniec dnia.
class TerminalReport {
  const TerminalReport(this.name, this.grosze);

  final String name;
  final int grosze;

  Map<String, dynamic> toJson() => {'name': name, 'grosze': grosze};

  static List<TerminalReport> listFrom(Object? value) => [
    for (final t in (value as List? ?? const []).cast<Map<String, dynamic>>())
      TerminalReport(t['name'] as String? ?? 'Terminal', _toInt(t['grosze'])),
  ];
}

/// Raporty wpisane na koniec dnia: kasa fiskalna, terminale, policzona gotówka i notatka.
class DayReport {
  const DayReport({
    this.fiscalGrosze,
    this.terminals = const [],
    this.cashCountedGrosze,
    this.note,
    this.updatedAt,
    this.updatedBy,
    this.platforms = const [],
  });

  final int? fiscalGrosze;
  final List<TerminalReport> terminals;

  /// Sprzedaż z platform dostaw (nazwa i kwota), osobno od kasy fiskalnej.
  final List<TerminalReport> platforms;
  final int? cashCountedGrosze;
  final String? note;
  final DateTime? updatedAt;
  final String? updatedBy;

  int get terminalsGrosze => terminals.fold(0, (s, t) => s + t.grosze);

  factory DayReport.fromJson(Map<String, dynamic> json) => DayReport(
    fiscalGrosze: json['fiscal_grosze'] == null ? null : _toInt(json['fiscal_grosze']),
    terminals: TerminalReport.listFrom(json['terminals']),
    cashCountedGrosze: json['cash_counted_grosze'] == null ? null : _toInt(json['cash_counted_grosze']),
    note: json['note'] as String?,
    updatedAt: _toDateOrNull(json['updated_at']),
    updatedBy: json['updated_by_name'] as String?,
    platforms: TerminalReport.listFrom(json['platforms']),
  );
}

/// Dzień lokalu: sprzedaż według płatności, petty cash i raporty z końca dnia.
class DaySummary {
  const DaySummary({
    required this.revenueGrosze,
    required this.orders,
    required this.dineIn,
    required this.takeaway,
    required this.cashGrosze,
    required this.cardGrosze,
    required this.cardOnlineGrosze,
    required this.otherGrosze,
    required this.cancelled,
    required this.pettyOutGrosze,
    required this.pettyInGrosze,
    required this.petty,
    this.tipsGrosze = 0,
    this.tipsCashGrosze = 0,
    this.tipsCardGrosze = 0,
    this.discountsGrosze = 0,
    this.depositsGrosze = 0,
    this.report,
  });

  /// Zadatki z rezerwacji odjęte od rachunków (w karcie online).
  final int depositsGrosze;

  /// Napiwki ze wszystkich płatności, w tym gotówką i kartą (karta przechodzi przez terminal).
  final int tipsGrosze;
  final int tipsCashGrosze;
  final int tipsCardGrosze;

  /// Rabaty z kodów rezerwacji odjęte od rachunków.
  final int discountsGrosze;

  final int revenueGrosze;
  final int orders;
  final int dineIn;
  final int takeaway;
  final int cashGrosze;

  /// Karta na terminalu w lokalu.
  final int cardGrosze;

  /// Karta online w aplikacji Table (zamówienia na wynos), poza terminalami.
  final int cardOnlineGrosze;
  final int otherGrosze;
  final int cancelled;
  final int pettyOutGrosze;
  final int pettyInGrosze;
  final List<PettyEntry> petty;
  final DayReport? report;

  /// Gotówka, która powinna być w kasie: sprzedaż i napiwki gotówką, minus wydatki z petty, plus wpłaty.
  int get expectedCashGrosze => cashGrosze + tipsCashGrosze - pettyOutGrosze + pettyInGrosze;

  /// Kwota z terminali: płatności kartą z napiwkami.
  int get expectedCardGrosze => cardGrosze + tipsCardGrosze;

  factory DaySummary.fromJson(Map<String, dynamic> json) => DaySummary(
    revenueGrosze: _toInt(json['revenue']),
    orders: _toInt(json['orders']),
    dineIn: _toInt(json['dine_in']),
    takeaway: _toInt(json['takeaway']),
    cashGrosze: _toInt(json['cash']),
    cardGrosze: _toInt(json['card']),
    cardOnlineGrosze: _toInt(json['card_online']),
    otherGrosze: _toInt(json['other']),
    cancelled: _toInt(json['cancelled']),
    pettyOutGrosze: _toInt(json['petty_out']),
    pettyInGrosze: _toInt(json['petty_in']),
    tipsGrosze: _toInt(json['tips']),
    tipsCashGrosze: _toInt(json['tips_cash']),
    tipsCardGrosze: _toInt(json['tips_card']),
    discountsGrosze: _toInt(json['discounts']),
    depositsGrosze: _toInt(json['deposits']),
    petty: [for (final e in (json['petty'] as List? ?? const [])) PettyEntry.fromJson(e as Map<String, dynamic>)],
    report: json['report'] == null ? null : DayReport.fromJson(json['report'] as Map<String, dynamic>),
  );
}

/// Gość na liście oczekujących: dzień, liczba osób, przedział godzin i propozycja lokalu.
class WaitlistEntry {
  const WaitlistEntry({
    required this.id,
    required this.partySize,
    required this.from,
    required this.to,
    required this.offered,
    required this.guestName,
    required this.createdAt,
    this.note,
    this.offeredTime,
    this.guestPhone,
    this.guestVisits = 0,
  });

  final String id;
  final int partySize;

  /// Godziny jako „18:00”.
  final String from;
  final String to;
  final String? note;

  /// Lokal zaproponował już godzinę ([offeredTime]).
  final bool offered;
  final String? offeredTime;
  final String guestName;
  final String? guestPhone;
  final int guestVisits;
  final DateTime createdAt;

  static String _hm(Object? v) => v == null ? '' : (v as String).substring(0, 5);

  factory WaitlistEntry.fromJson(Map<String, dynamic> json) => WaitlistEntry(
    id: json['id'] as String,
    partySize: _toInt(json['party_size']),
    from: _hm(json['time_from']),
    to: _hm(json['time_to']),
    note: json['note'] as String?,
    offered: json['status'] == 'offered',
    offeredTime: json['offered_time'] == null ? null : _hm(json['offered_time']),
    guestName: json['guest_name'] as String? ?? 'Gość',
    guestPhone: json['guest_phone'] as String?,
    guestVisits: _toInt(json['guest_visits']),
    createdAt: _toDate(json['created_at']),
  );
}

/// Jeden sygnał analizy oszustw, np. „Dużo jednego dania: 9 × Tatar.” (punkty dodają się do oceny).
class RiskFlag {
  const RiskFlag({required this.code, required this.points, required this.text});

  final String code;
  final int points;
  final String text;

  factory RiskFlag.fromJson(Map<String, dynamic> json) =>
      RiskFlag(code: '${json['code']}', points: _toInt(json['points']), text: '${json['text']}');
}

enum RiskLevel { low, medium, high }

/// Ocena ryzyka zamówienia z aplikacji Table (0070, `panel_order_risks`): wzorce zamówień gościa, nieudane
/// płatności, wspólne IP i numer, adres IP z ipinfo.io. 0–100 punktów.
class OrderRisk {
  const OrderRisk({
    required this.orderId,
    required this.number,
    required this.kind,
    required this.fulfillment,
    required this.openedAt,
    required this.customerName,
    required this.customerPhone,
    required this.totalGrosze,
    required this.paymentChoice,
    required this.score,
    required this.ipChecked,
    this.clientIp,
    this.ipInfo = const {},
    this.flags = const [],
  });

  final String orderId;
  final int number;
  final OrderKind kind;
  final String fulfillment;
  final DateTime openedAt;
  final String customerName;
  final String customerPhone;
  final int totalGrosze;
  final String paymentChoice;
  final int score;
  final bool ipChecked;
  final String? clientIp;

  /// ipinfo.io: city, region, country, org, privacy, distance_km.
  final Map<String, dynamic> ipInfo;
  final List<RiskFlag> flags;

  RiskLevel get level => score >= 50
      ? RiskLevel.high
      : score >= 25
      ? RiskLevel.medium
      : RiskLevel.low;

  /// „Białystok, PL · 12 km od lokalu · AS5617 Orange Polska”.
  String? get ipPlace {
    if (ipInfo.isEmpty) return null;
    final place = [?ipInfo['city'] as String?, ?ipInfo['country'] as String?].join(', ');
    final km = ipInfo['distance_km'];
    return [
      if (place.isNotEmpty) place,
      if (km != null) '${_toInt(km)} km od lokalu',
      ?ipInfo['org'] as String?,
    ].join(' · ');
  }

  factory OrderRisk.fromJson(Map<String, dynamic> json) => OrderRisk(
    orderId: json['order_id'] as String,
    number: _toInt(json['number']),
    kind: json['kind'] == 'pickup' ? OrderKind.pickup : OrderKind.delivery,
    fulfillment: '${json['fulfillment']}',
    openedAt: _toDate(json['opened_at']),
    customerName: '${json['customer_name'] ?? ''}',
    customerPhone: '${json['customer_phone'] ?? ''}',
    totalGrosze: _toInt(json['total_grosze']),
    paymentChoice: '${json['payment_choice'] ?? ''}',
    score: _toInt(json['score']),
    ipChecked: json['ip_checked'] == true,
    clientIp: json['client_ip'] as String?,
    ipInfo: (json['ip_info'] as Map?)?.cast<String, dynamic>() ?? const {},
    flags: [for (final f in json['flags'] as List? ?? const []) RiskFlag.fromJson((f as Map).cast<String, dynamic>())],
  );
}

// ---------------------------------------------------------------
// Logi i Time Machine (0072)
// ---------------------------------------------------------------

/// Pozycja rachunku w wybranej chwili (stan z tamtej chwili: new, sent, ready, served, cancelled).
class TmItem {
  const TmItem({required this.name, required this.quantity, required this.price, required this.status, this.variant});

  final String name;
  final String? variant;
  final int quantity;
  final int price;
  final String status;

  factory TmItem.fromJson(Map<String, dynamic> json) => TmItem(
    name: '${json['name']}',
    variant: json['variant'] as String?,
    quantity: _toInt(json['quantity']),
    price: _toInt(json['price']),
    status: '${json['status']}',
  );
}

class TmBill {
  const TmBill({
    required this.orderId,
    required this.label,
    required this.openedAt,
    required this.paid,
    required this.items,
    this.tableId,
    this.openedBy,
    this.guests,
  });

  final String orderId;
  final String? tableId;
  final String label;
  final DateTime openedAt;
  final String? openedBy;
  final int? guests;

  /// Wpłacone do tamtej chwili.
  final int paid;
  final List<TmItem> items;

  int get total => items.where((i) => i.status != 'cancelled').fold(0, (s, i) => s + i.price * i.quantity);

  factory TmBill.fromJson(Map<String, dynamic> json) => TmBill(
    orderId: json['order_id'] as String,
    tableId: json['table_id'] as String?,
    label: '${json['label']}',
    openedAt: _toDate(json['opened_at']),
    openedBy: json['opened_by'] as String?,
    guests: json['guests'] == null ? null : _toInt(json['guests']),
    paid: _toInt(json['paid']),
    items: [for (final i in json['items'] as List? ?? const []) TmItem.fromJson(i as Map<String, dynamic>)],
  );
}

class TmReservation {
  const TmReservation({
    required this.name,
    required this.party,
    required this.startsAt,
    required this.endsAt,
    required this.seated,
    required this.tableIds,
  });

  final String name;
  final int party;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool seated;
  final List<String> tableIds;

  factory TmReservation.fromJson(Map<String, dynamic> json) => TmReservation(
    name: '${json['name']}',
    party: _toInt(json['party']),
    startsAt: _toDate(json['starts_at']),
    endsAt: _toDate(json['ends_at']),
    seated: json['seated'] == true,
    tableIds: [for (final t in json['table_ids'] as List? ?? const []) '$t'],
  );
}

class TmTakeaway {
  const TmTakeaway({
    required this.orderId,
    required this.label,
    required this.stage,
    required this.total,
    this.customer,
    this.kind,
    this.openedAt,
  });

  final String orderId;
  final String label;
  final String? customer;

  /// delivery albo pickup (null w starym `panel_time_machine`).
  final String? kind;
  final DateTime? openedAt;

  /// placed, accepted, ready, on_the_way.
  final String stage;
  final int total;

  String get stageLabel => switch (stage) {
    'accepted' => 'w przygotowaniu',
    'ready' => 'gotowe',
    'on_the_way' => 'w drodze',
    'delivered' => 'wydane',
    _ => 'czeka na przyjęcie',
  };

  factory TmTakeaway.fromJson(Map<String, dynamic> json) => TmTakeaway(
    orderId: json['order_id'] as String,
    label: '${json['label']}',
    customer: json['customer'] as String?,
    stage: '${json['stage']}',
    total: _toInt(json['total']),
  );
}

/// Stan lokalu w wybranej chwili (`panel_time_machine`): rachunki przy stolikach, rezerwacje, zamówienia na wynos
/// i osoby na zmianie.
class TimeMachine {
  const TimeMachine({
    required this.at,
    this.bills = const [],
    this.reservations = const [],
    this.takeaway = const [],
    this.staff = const [],
  });

  final DateTime at;
  final List<TmBill> bills;
  final List<TmReservation> reservations;
  final List<TmTakeaway> takeaway;

  /// Imię i od kiedy na zmianie.
  final List<(String, DateTime)> staff;

  TmBill? billAt(String tableId) => bills.where((b) => b.tableId == tableId).firstOrNull;
  TmReservation? reservationAt(String tableId) => reservations.where((r) => r.tableIds.contains(tableId)).firstOrNull;

  factory TimeMachine.fromJson(Map<String, dynamic> json) => TimeMachine(
    at: _toDate(json['at']),
    bills: [for (final b in json['bills'] as List? ?? const []) TmBill.fromJson(b as Map<String, dynamic>)],
    reservations: [
      for (final r in json['reservations'] as List? ?? const []) TmReservation.fromJson(r as Map<String, dynamic>),
    ],
    takeaway: [for (final t in json['takeaway'] as List? ?? const []) TmTakeaway.fromJson(t as Map<String, dynamic>)],
    staff: [
      for (final s in json['staff'] as List? ?? const [])
        ('${(s as Map)['name']}', _toDate(s['since'])),
    ],
  );
}

/// Chwila z JSON-a albo null.
DateTime? _tmDate(Object? value) => value == null ? null : _toDate(value);

/// Czy chwila [t] już nastąpiła w [at] (null: jeszcze nie).
bool _done(DateTime? t, DateTime at) => t != null && !t.isAfter(at);

/// Pozycja rachunku z chwilami etapów (Time Machine bez czekania, 0073).
class TmItemTrack {
  const TmItemTrack({
    required this.name,
    required this.quantity,
    required this.price,
    required this.createdAt,
    this.variant,
    this.sentAt,
    this.readyAt,
    this.servedAt,
    this.cancelledAt,
    this.cancelledEarlier = false,
  });

  final String name;
  final String? variant;
  final int quantity;
  final int price;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? readyAt;
  final DateTime? servedAt;
  final DateTime? cancelledAt;

  /// Anulowana przed 0072 (bez chwili anulowania): anulowana od początku.
  final bool cancelledEarlier;

  String statusAt(DateTime at) {
    if (cancelledEarlier || _done(cancelledAt, at)) return 'cancelled';
    if (_done(servedAt, at)) return 'served';
    if (_done(readyAt, at)) return 'ready';
    if (_done(sentAt, at)) return 'sent';
    return 'new';
  }

  factory TmItemTrack.fromJson(Map<String, dynamic> json) => TmItemTrack(
    name: '${json['name']}',
    variant: json['variant'] as String?,
    quantity: _toInt(json['quantity']),
    price: _toInt(json['price']),
    createdAt: _toDate(json['created_at']),
    sentAt: _tmDate(json['sent_at']),
    readyAt: _tmDate(json['ready_at']),
    servedAt: _tmDate(json['served_at']),
    cancelledAt: _tmDate(json['cancelled_at']),
    cancelledEarlier: json['cancelled'] == true,
  );
}

class TmBillTrack {
  const TmBillTrack({
    required this.orderId,
    required this.label,
    required this.openedAt,
    this.closedAt,
    this.tableId,
    this.openedBy,
    this.guests,
    this.payments = const [],
    this.items = const [],
  });

  final String orderId;
  final String? tableId;
  final String label;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String? openedBy;
  final int? guests;

  /// Chwila i kwota każdej płatności.
  final List<(DateTime, int)> payments;
  final List<TmItemTrack> items;

  bool openAt(DateTime at) => !openedAt.isAfter(at) && (closedAt == null || closedAt!.isAfter(at));

  TmBill at(DateTime at) => TmBill(
    orderId: orderId,
    tableId: tableId,
    label: label,
    openedAt: openedAt,
    openedBy: openedBy,
    guests: guests,
    paid: payments.where((p) => !p.$1.isAfter(at)).fold(0, (s, p) => s + p.$2),
    items: [
      for (final i in items)
        if (!i.createdAt.isAfter(at))
          TmItem(name: i.name, variant: i.variant, quantity: i.quantity, price: i.price, status: i.statusAt(at)),
    ],
  );

  factory TmBillTrack.fromJson(Map<String, dynamic> json) => TmBillTrack(
    orderId: json['order_id'] as String,
    tableId: json['table_id'] as String?,
    label: '${json['label']}',
    openedAt: _toDate(json['opened_at']),
    closedAt: _tmDate(json['closed_at']),
    openedBy: json['opened_by'] as String?,
    guests: json['guests'] == null ? null : _toInt(json['guests']),
    payments: [
      for (final p in json['payments'] as List? ?? const []) (_toDate((p as Map)['at']), _toInt(p['amount'])),
    ],
    items: [for (final i in json['items'] as List? ?? const []) TmItemTrack.fromJson(i as Map<String, dynamic>)],
  );
}

class TmReservationTrack {
  const TmReservationTrack({
    required this.name,
    required this.party,
    required this.startsAt,
    required this.endsAt,
    required this.createdAt,
    required this.tableIds,
    this.seatedAt,
  });

  final String name;
  final int party;
  final DateTime startsAt;
  final DateTime endsAt;
  final DateTime createdAt;
  final DateTime? seatedAt;
  final List<String> tableIds;

  bool activeAt(DateTime at) => !startsAt.isAfter(at) && endsAt.isAfter(at) && !createdAt.isAfter(at);

  TmReservation at(DateTime at) => TmReservation(
    name: name,
    party: party,
    startsAt: startsAt,
    endsAt: endsAt,
    seated: _done(seatedAt, at),
    tableIds: tableIds,
  );

  factory TmReservationTrack.fromJson(Map<String, dynamic> json) => TmReservationTrack(
    name: '${json['name']}',
    party: _toInt(json['party']),
    startsAt: _toDate(json['starts_at']),
    endsAt: _toDate(json['ends_at']),
    createdAt: _toDate(json['created_at']),
    seatedAt: _tmDate(json['seated_at']),
    tableIds: [for (final t in json['table_ids'] as List? ?? const []) '$t'],
  );
}

class TmTakeawayTrack {
  const TmTakeawayTrack({
    required this.orderId,
    required this.label,
    required this.kind,
    required this.fulfillment,
    required this.openedAt,
    required this.total,
    this.customer,
    this.acceptedAt,
    this.readyAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.closedAt,
  });

  final String orderId;
  final String label;
  final String? customer;

  /// delivery albo pickup.
  final String kind;
  final String fulfillment;
  final DateTime openedAt;
  final DateTime? acceptedAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? closedAt;
  final int total;

  /// W toku w chwili [at]: złożone, jeszcze nie wydane ani nie dostarczone; odrzucone, anulowane i nieopłacone
  /// tylko, jeśli wtedy jeszcze trwały (tak samo jak w `panel_time_machine`).
  bool activeAt(DateTime at) {
    if (openedAt.isAfter(at)) return false;
    final end = deliveredAt ?? closedAt;
    if (end != null && !end.isAfter(at)) return false;
    const stopped = {'rejected', 'cancelled', 'awaiting_payment'};
    return !stopped.contains(fulfillment) || (closedAt != null && closedAt!.isAfter(at));
  }

  TmTakeaway at(DateTime at) => TmTakeaway(
    orderId: orderId,
    label: label,
    customer: customer,
    stage: _done(deliveredAt, at)
        ? 'delivered'
        : _done(pickedUpAt, at)
        ? 'on_the_way'
        : _done(readyAt, at)
        ? 'ready'
        : _done(acceptedAt, at)
        ? 'accepted'
        : 'placed',
    total: total,
    kind: kind,
    openedAt: openedAt,
  );

  factory TmTakeawayTrack.fromJson(Map<String, dynamic> json) => TmTakeawayTrack(
    orderId: json['order_id'] as String,
    label: '${json['label']}',
    customer: json['customer'] as String?,
    kind: '${json['kind']}',
    fulfillment: '${json['fulfillment']}',
    openedAt: _toDate(json['opened_at']),
    acceptedAt: _tmDate(json['accepted_at']),
    readyAt: _tmDate(json['ready_at']),
    pickedUpAt: _tmDate(json['picked_up_at']),
    deliveredAt: _tmDate(json['delivered_at']),
    closedAt: _tmDate(json['closed_at']),
    total: _toInt(json['total']),
  );
}

/// Dane Time Machine z całej doby (`panel_time_machine_day`, 0073): pobierane raz, a stan lokalu w dowolnej chwili
/// liczy [at] bez pytania bazy, więc przewijanie osi czasu jest natychmiastowe.
class TimeMachineDay {
  const TimeMachineDay({
    this.bills = const [],
    this.reservations = const [],
    this.takeaway = const [],
    this.shifts = const [],
  });

  final List<TmBillTrack> bills;
  final List<TmReservationTrack> reservations;
  final List<TmTakeawayTrack> takeaway;

  /// Imię, początek i koniec zmiany (null: trwa).
  final List<(String, DateTime, DateTime?)> shifts;

  TimeMachine at(DateTime at) => TimeMachine(
    at: at,
    bills: [
      for (final b in bills)
        if (b.openAt(at)) b.at(at),
    ],
    reservations: [
      for (final r in reservations)
        if (r.activeAt(at)) r.at(at),
    ],
    takeaway: [
      for (final t in takeaway)
        if (t.activeAt(at)) t.at(at),
    ],
    staff: [
      for (final (name, from, to) in shifts)
        if (!from.isAfter(at) && (to == null || to.isAfter(at))) (name, from),
    ],
  );

  factory TimeMachineDay.fromJson(Map<String, dynamic> json) => TimeMachineDay(
    bills: [for (final b in json['bills'] as List? ?? const []) TmBillTrack.fromJson(b as Map<String, dynamic>)],
    reservations: [
      for (final r in json['reservations'] as List? ?? const [])
        TmReservationTrack.fromJson(r as Map<String, dynamic>),
    ],
    takeaway: [
      for (final t in json['takeaway'] as List? ?? const []) TmTakeawayTrack.fromJson(t as Map<String, dynamic>),
    ],
    shifts: [
      for (final s in json['staff'] as List? ?? const [])
        ('${(s as Map)['name']}', _toDate(s['started_at']), _tmDate(s['ended_at'])),
    ],
  );
}
