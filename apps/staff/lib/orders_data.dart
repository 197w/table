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

class WMenuItem {
  const WMenuItem({
    required this.id,
    required this.name,
    required this.priceGrosze,
    required this.variants,
    required this.addons,
    required this.available,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final int priceGrosze;
  final List<WOption> variants;
  final List<WOption> addons;
  final bool available;

  bool get hasOptions => variants.isNotEmpty || addons.isNotEmpty;

  factory WMenuItem.fromJson(Map<String, dynamic> j) => WMenuItem(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String?,
    priceGrosze: _toInt(j['price_grosze']),
    variants: WOption.listFrom(j['variants']),
    addons: WOption.listFrom(j['addons']),
    available: j['available'] != false,
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
  });

  final String id;
  final String name;
  final String? variant;
  final List<WOption> addons;
  final int unitPriceGrosze;
  final int quantity;
  final String? note;
  final LineStatus status;
  final DateTime createdAt;

  int get total => unitPriceGrosze * quantity;

  String? get details {
    final parts = [?variant, for (final a in addons) '+ ${a.name.toLowerCase()}'];
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory WLine.fromJson(Map<String, dynamic> j) => WLine(
    id: j['id'] as String,
    name: j['name'] as String,
    variant: j['variant'] as String?,
    addons: WOption.listFrom(j['addons']),
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
        .select('id, name, position, menu_items(id, name, description, price_grosze, variants, addons, available, position)')
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

  Future<String> openOrder(String restaurantId, String tableId, String memberId) => _guard(
    () => _db.rpc<String>('panel_open_order', params: {
      'p_restaurant_id': restaurantId,
      'p_table_id': tableId,
      'p_member_id': memberId,
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

final openOrdersProvider = FutureProvider.autoDispose.family<List<WOrder>, String>((ref, id) {
  ref.watch(ordersLiveProvider(id));
  if (ref.watch(sessionProvider) == null) return Future.value(const []);
  return ref.watch(waiterRepositoryProvider).openOrders(id);
});
