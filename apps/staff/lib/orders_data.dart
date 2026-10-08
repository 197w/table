import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';

int _toInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Stolik lokalu.
class WTable {
  const WTable({required this.id, required this.label, required this.seats, required this.zone, required this.isSeat});

  final String id;
  final String label;
  final int seats;
  final String zone;
  final bool isSeat;

  String get title => '${isSeat ? 'Miejsce' : 'Stolik'} $label';

  factory WTable.fromJson(Map<String, dynamic> j) => WTable(
    id: j['id'] as String,
    label: j['label'] as String,
    seats: _toInt(j['seats']),
    zone: j['zone'] as String? ?? '',
    isSeat: j['kind'] == 'seat',
  );
}

/// Wariant albo dodatek dania.
class WOption {
  const WOption(this.name, this.priceGrosze);

  final String name;
  final int priceGrosze;

  static List<WOption> listFrom(Object? v) => [
    for (final e in (v as List? ?? const []).cast<Map<String, dynamic>>()) WOption(e['name'] as String, _toInt(e['price_grosze'])),
  ];
}

/// Zmiana składnika w pozycji: „bez cebuli” albo „więcej sera”. [itemId] tylko dla składnika z receptury.
class WChange {
  const WChange(this.name, {required this.extra, this.itemId});

  final String name;
  final bool extra;
  final String? itemId;

  String get label => extra ? 'więcej: ${name.toLowerCase()}' : 'bez: ${name.toLowerCase()}';

  Map<String, dynamic> toJson() => {'name': name, 'kind': extra ? 'extra' : 'without', 'item_id': itemId};

  static List<WChange> listFrom(Object? v) => [
    for (final c in v is List ? v : const [])
      if (c is Map && c['name'] is String)
        WChange(c['name'] as String, extra: c['kind'] == 'extra', itemId: c['item_id'] as String?),
  ];
}

/// Składnik z receptury dania (z inwentaryzacji): do zmian „bez” i „więcej”.
class WIngredient {
  const WIngredient(this.id, this.name);

  final String id;
  final String name;
}

class WMenuItem {
  const WMenuItem({
    required this.id,
    required this.name,
    required this.priceGrosze,
    required this.variants,
    required this.addons,
    required this.available,
    this.description,
    this.ingredients = const [],
  });

  final String id;
  final String name;
  final String? description;
  final int priceGrosze;
  final List<WOption> variants;
  final List<WOption> addons;
  final bool available;
  final List<WIngredient> ingredients;

  bool get hasOptions => variants.isNotEmpty || addons.isNotEmpty;

  /// Najniższa cena: przy wariantach najtańszy z nich.
  int get fromPrice => variants.isEmpty ? priceGrosze : variants.map((v) => v.priceGrosze).reduce((a, b) => a < b ? a : b);

  /// Warianty mają różne ceny, więc cena zaczyna się „od”. Jeden wariant (np. Tonic 200 ml) ma jedną cenę.
  bool get priceVaries => variants.map((v) => v.priceGrosze).toSet().length > 1;

  factory WMenuItem.fromJson(Map<String, dynamic> j) => WMenuItem(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
    priceGrosze: _toInt(j['price_grosze']),
    variants: WOption.listFrom(j['variants']),
    addons: WOption.listFrom(j['addons']),
    available: j['available'] != false,
    ingredients: [
      for (final r in (j['menu_item_ingredients'] as List? ?? const []).cast<Map<String, dynamic>>())
        if ((r['inventory_items'] as Map<String, dynamic>?)?['name'] case final String name)
          WIngredient(r['item_id'] as String, name),
    ],
  );
}

class WMenuSection {
  const WMenuSection({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<WMenuItem> items;
}

enum LineStatus { fresh, sent, ready, served, cancelled }

LineStatus _status(Object? v) => switch (v) {
  'sent' => LineStatus.sent,
  'ready' => LineStatus.ready,
  'served' => LineStatus.served,
  'cancelled' => LineStatus.cancelled,
  _ => LineStatus.fresh,
};

/// Pozycja na rachunku.
class WLine {
  const WLine({
    required this.id,
    required this.name,
    required this.unitPriceGrosze,
    required this.quantity,
    required this.status,
    required this.createdAt,
    this.variant,
    this.addons = const [],
    this.note,
    this.changes = const [],
  });

  final String id;
  final String name;
  final String? variant;
  final List<WOption> addons;
  final List<WChange> changes;
  final int unitPriceGrosze;
  final int quantity;
  final String? note;
  final LineStatus status;
  final DateTime createdAt;

  int get total => unitPriceGrosze * quantity;

  String? get details {
    final parts = [?variant, for (final a in addons) '+ ${a.name.toLowerCase()}', for (final c in changes) c.label];
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory WLine.fromJson(Map<String, dynamic> j) => WLine(
    id: j['id'] as String,
    name: j['name'] as String,
    variant: j['variant'] as String?,
    addons: WOption.listFrom(j['addons']),
    changes: WChange.listFrom(j['changes']),
    unitPriceGrosze: _toInt(j['unit_price_grosze']),
    quantity: _toInt(j['quantity']),
    note: j['note'] as String?,
    status: _status(j['status']),
    createdAt: DateTime.parse(j['created_at'] as String),
  );
}

/// Otwarty rachunek stolika.
class WOrder {
  const WOrder({required this.id, required this.tableId, required this.lines});

  final String id;
  final String? tableId;
  final List<WLine> lines;

  int get total => lines.where((l) => l.status != LineStatus.cancelled).fold(0, (s, l) => s + l.total);
  int get unsent => lines.where((l) => l.status == LineStatus.fresh).length;
  int get ready => lines.where((l) => l.status == LineStatus.ready).length;

  factory WOrder.fromJson(Map<String, dynamic> j) => WOrder(
    id: j['id'] as String,
    tableId: j['table_id'] as String?,
    lines: [for (final l in (j['order_items'] as List? ?? const [])) WLine.fromJson(l as Map<String, dynamic>)]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );
}

enum WPayment {
  cash('cash', 'Gotówka'),
  card('card', 'Karta'),
  other('other', 'Inne');

  const WPayment(this.db, this.label);
  final String db;
  final String label;
}

/// Jedna płatność rachunku: forma, kwota bez napiwku i napiwek.
class WPart {
  const WPart(this.method, this.amount, {this.tip = 0});

  final WPayment method;
  final int amount;
  final int tip;

  Map<String, dynamic> toJson() => {'method': method.db, 'amount': amount, 'tip': tip};
}

/// Ile do zapłaty: suma, rabat z kodu rezerwacji i kwota po rabacie.
class WDue {
  const WDue({
    required this.total,
    required this.discount,
    required this.due,
    this.deposit = 0,
    this.label,
    this.percent,
    this.code,
    this.reservationCode,
  });

  final int total;
  final int discount;

  /// Kod rabatowy wpisany przy rachunku (zastępuje kod z rezerwacji).
  final String? code;

  /// Kod z rezerwacji gościa.
  final String? reservationCode;

  /// Zadatek z rezerwacji odjęty od rachunku (przy zamknięciu całości).
  final int deposit;
  final int due;
  final String? label;

  /// Rabat procentowy liczy się też od części rachunku. Null: brak albo kwotowy.
  final int? percent;

  /// Rabat i kwota do zapłaty za część rachunku o wartości [part].
  (int discount, int due) forPart(int part) {
    final p = percent;
    final discount = p == null ? 0 : (part * p / 100).round().clamp(0, part);
    return (discount, part - discount);
  }

  factory WDue.fromJson(Map<String, dynamic> j) => WDue(
    total: _toInt(j['total']),
    discount: _toInt(j['discount']),
    deposit: _toInt(j['deposit']),
    due: _toInt(j['due']),
    label: j['discount_label'] as String?,
    percent: j['discount_percent'] == null ? null : _toInt(j['discount_percent']),
    code: j['discount_code'] as String?,
    reservationCode: j['reservation_code'] as String?,
  );
}

/// Podpowiedź kodu rabatowego: kod lokalu działający dziś.
class WDiscountHint {
  const WDiscountHint({required this.code, required this.percent, required this.value, this.note});

  final String code;
  final bool percent;
  final int value;
  final String? note;

  String get valueText => percent ? '−$value%' : '−${(value / 100).toStringAsFixed(2).replaceAll('.', ',')} zł';

  factory WDiscountHint.fromJson(Map<String, dynamic> j) => WDiscountHint(
    code: j['code'] as String,
    percent: j['kind'] == 'percent',
    value: _toInt(j['value']),
    note: (j['note'] as String?)?.trim().isEmpty ?? true ? null : j['note'] as String,
  );
}

/// Podział kwoty na [people] równych części; grosze reszty dostają pierwsze osoby.
List<int> splitEqually(int amount, int people) {
  final n = people < 1 ? 1 : people;
  final base = amount ~/ n;
  final rest = amount % n;
  return [for (var i = 0; i < n; i++) base + (i < rest ? 1 : 0)];
}

/// Zamówienia z telefonu kelnera. Te same funkcje bazy co w panelu: cenę liczy baza z menu,
/// a pracownik musi mieć trwającą zmianę.
class WaiterRepository {
  WaiterRepository(this._db);

  final SupabaseClient _db;
  static int _seq = 0;

  Future<List<WTable>> tables(String restaurantId) => _guard(() async {
    final rows = await _db
        .from('dining_tables')
        .select('id, label, seats, zone, kind, active')
        .eq('restaurant_id', restaurantId)
        .order('zone')
        .order('label');
    return [for (final r in rows) WTable.fromJson(r)];
  });

  Future<List<WMenuSection>> menu(String restaurantId) => _guard(() async {
    final rows = await _db
        .from('menu_sections')
        .select(
          'id, name, position, menu_items(id, name, description, price_grosze, variants, addons, available, position, '
          'menu_item_ingredients(item_id, inventory_items(name)))',
        )
        .eq('restaurant_id', restaurantId)
        .order('position');
    return [
      for (final s in rows)
        WMenuSection(
          id: s['id'] as String,
          name: s['name'] as String,
          items: [
            for (final i in ((s['menu_items'] as List? ?? const []).cast<Map<String, dynamic>>()
              ..sort((a, b) => _toInt(a['position']).compareTo(_toInt(b['position'])))))
              WMenuItem.fromJson(i),
          ],
        ),
    ];
  });

  Future<List<WOrder>> openOrders(String restaurantId) => _guard(() async {
    final rows = await _db
        .from('orders')
        .select('id, table_id, order_items(*)')
        .eq('restaurant_id', restaurantId)
        .eq('kind', 'dine_in')
        .eq('status', 'open');
    return [for (final r in rows) WOrder.fromJson(r)];
  });

  /// Zmiany rachunków lokalu na żywo (panel, kuchnia i inni kelnerzy).
  void Function() watch(String restaurantId, void Function() onChange) {
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'restaurant_id', value: restaurantId);
    final channel = _db
        .channel('kelner-$restaurantId-${_seq++}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'orders', filter: filter, callback: (_) => onChange())
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'order_items', filter: filter, callback: (_) => onChange())
        .subscribe();
    return () => unawaited(_db.removeChannel(channel));
  }

  /// Otwiera rachunek stolika (albo zwraca otwarty). [guests]: liczba gości; [skipGuests]: kelner pominął pytanie.
  Future<String> openOrder(String restaurantId, String tableId, String memberId, {int? guests, bool skipGuests = false}) =>
      _guard(
        () => _db.rpc<String>('panel_open_order', params: {
          'p_restaurant_id': restaurantId,
          'p_table_id': tableId,
          'p_member_id': memberId,
          'p_guests': guests,
          'p_skip_guests': skipGuests,
        }),
      );

  Future<void> addItem({
    required String orderId,
    required String menuItemId,
    required String memberId,
    String? variant,
    List<String> addons = const [],
    int quantity = 1,
    String? note,
    List<WChange> changes = const [],
  }) => _guard(
    () => _db.rpc<String>('panel_add_order_item', params: {
      'p_order_id': orderId,
      'p_menu_item_id': menuItemId,
      'p_variant': variant,
      'p_addons': addons,
      'p_quantity': quantity,
      'p_note': note,
      'p_course': 1,
      'p_member_id': memberId,
      if (changes.isNotEmpty) 'p_changes': [for (final c in changes) c.toJson()],
    }),
  );

  /// Zmiana ilości albo stanu pozycji. Anulowana nowa pozycja znika z rachunku.
  Future<void> updateItem(String itemId, {int? quantity, String? status}) => _guard(
    () => _db.rpc<void>('panel_update_order_item', params: {
      'p_item_id': itemId,
      'p_quantity': quantity,
      'p_note': null,
      'p_status': status,
    }),
  );

  Future<int> send(String orderId) =>
      _guard(() => _db.rpc<int>('panel_send_order', params: {'p_order_id': orderId}));

  Future<void> close(String orderId, WPayment method, String memberId) => _guard(
    () => _db.rpc<void>('panel_close_order', params: {
      'p_order_id': orderId,
      'p_payment_method': method.db,
      'p_member_id': memberId,
    }),
  );

  Future<WDue> due(String orderId) => _guard(() async {
    final json = await _db.rpc<Map<String, dynamic>>('panel_order_due', params: {'p_order_id': orderId});
    return WDue.fromJson(json);
  });

  /// Kod rabatowy przy rachunku; null usuwa wpisany.
  Future<WDue> setDiscount(String orderId, String? code, String memberId) => _guard(() async {
    final json = await _db.rpc<Map<String, dynamic>>('panel_order_set_discount', params: {
      'p_order_id': orderId,
      'p_code': code,
      'p_member_id': memberId,
    });
    return WDue.fromJson(json);
  });

  /// Kody rabatowe lokalu działające dziś, pasujące do wpisanego tekstu.
  Future<List<WDiscountHint>> discountHints(String restaurantId, String query) => _guard(() async {
    final rows = await _db.rpc<List<dynamic>>(
      'panel_discount_suggestions',
      params: {'p_restaurant_id': restaurantId, 'p_query': query},
    );
    return [for (final r in rows) WDiscountHint.fromJson(r as Map<String, dynamic>)];
  });

  /// Zamknięcie całego rachunku: jedna albo kilka płatności (np. równy podział), z napiwkami.
  Future<void> settle(String orderId, List<WPart> payments, String memberId) => _guard(
    () => _db.rpc<Map<String, dynamic>>('panel_settle_order', params: {
      'p_order_id': orderId,
      'p_payments': [for (final p in payments) p.toJson()],
      'p_member_id': memberId,
    }),
  );

  /// Gość płaci za wybrane pozycje (id → ilość); reszta zostaje na stoliku.
  Future<void> payItems(String orderId, Map<String, int> items, List<WPart> payments, String memberId) => _guard(
    () => _db.rpc<Map<String, dynamic>>('panel_pay_items', params: {
      'p_order_id': orderId,
      'p_items': [
        for (final e in items.entries)
          if (e.value > 0) {'id': e.key, 'quantity': e.value},
      ],
      'p_payments': [for (final p in payments) p.toJson()],
      'p_member_id': memberId,
    }),
  );

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code == 'P0001' && e.message.isNotEmpty) throw AppFailure(e.message);
      if (e.code == '42501') throw const AppFailure('Twoje stanowisko nie ma uprawnienia do zamówień.');
      throw const AppFailure('Nie udało się zapisać ani pobrać danych. Spróbuj ponownie.');
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure('Brak połączenia z serwerem. Sprawdź internet.');
    }
  }
}

final waiterRepositoryProvider = Provider<WaiterRepository>((ref) => WaiterRepository(Supabase.instance.client));

/// Numer zmiany rachunków lokalu: każda zmiana w bazie odświeża listy.
class OrdersLive extends Notifier<int> {
  OrdersLive(this.restaurantId);

  final String restaurantId;

  @override
  int build() {
    final stop = ref.watch(waiterRepositoryProvider).watch(restaurantId, () => state++);
    ref.onDispose(stop);
    return 0;
  }
}

final ordersLiveProvider = NotifierProvider.autoDispose.family<OrdersLive, int, String>(OrdersLive.new);

final tablesProvider = FutureProvider.autoDispose.family<List<WTable>, String>(
  (ref, id) => ref.watch(waiterRepositoryProvider).tables(id),
);

final menuProvider = FutureProvider.autoDispose.family<List<WMenuSection>, String>(
  (ref, id) => ref.watch(waiterRepositoryProvider).menu(id),
);

/// Kwota do zapłaty za rachunek z rabatem z kodu rezerwacji.
final orderDueProvider = FutureProvider.autoDispose.family<WDue, String>(
  (ref, orderId) => ref.watch(waiterRepositoryProvider).due(orderId),
);

final openOrdersProvider = FutureProvider.autoDispose.family<List<WOrder>, String>((ref, id) {
  ref.watch(ordersLiveProvider(id));
  if (ref.watch(sessionProvider) == null) return Future.value(const []);
  return ref.watch(waiterRepositoryProvider).openOrders(id);
});
