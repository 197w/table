import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'models.dart';

/// Jedyne miejsce panelu, które rozmawia z Supabase.
/// Każdy błąd zamienia na AppFailure z polskim komunikatem.
class PanelRepository {
  PanelRepository(this._db);

  final SupabaseClient _db;

  /// Numer kolejnego kanału na żywo.
  static int _channelSeq = 0;

  // -------------------------------------------------------------
  // Logowanie
  // -------------------------------------------------------------

  Session? get session => _db.auth.currentSession;

  String? get email => _db.auth.currentUser?.email;

  Future<void> signIn({required String email, required String password}) {
    return _guard(
      () => _db.auth.signInWithPassword(email: email.trim(), password: password),
    );
  }

  /// Konto restauracji zakładane mailem firmowym. Supabase wysyła link potwierdzający.
  Future<void> signUp({required String email, required String password}) {
    return _guard(() => _db.auth.signUp(email: email.trim(), password: password));
  }

  /// Tworzy lokal dla zalogowanego konta firmowego. Goście zobaczą go po weryfikacji.
  Future<String> createRestaurant({
    required String name,
    required String nip,
    required String city,
    required String address,
    required String phone,
    required String cuisine,
  }) {
    return _guard(
      () => _db.rpc<String>(
        'panel_create_restaurant',
        params: {
          'p_name': name.trim(),
          'p_nip': nip,
          'p_city': city.trim(),
          'p_address': address.trim(),
          'p_phone': phone.trim(),
          'p_cuisine': cuisine,
        },
      ),
    );
  }

  /// Sprawdza hasło konta restauracji, np. przed wyjściem z trybu obsługi.
  Future<void> confirmPassword(String password) {
    final email = _db.auth.currentUser?.email;
    if (email == null) return Future.error(const AppFailure('Zaloguj się ponownie.'));
    return _guard(() => _db.auth.signInWithPassword(email: email, password: password));
  }

  Future<void> sendPasswordReset(String email) {
    return _guard(() => _db.auth.resetPasswordForEmail(email.trim()));
  }

  Future<void> signOut() => _guard(() => _db.auth.signOut());

  Future<List<PanelRestaurant>> myRestaurants() {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('panel_my_restaurants');
      return rows
          .map((e) => PanelRestaurant.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  // -------------------------------------------------------------
  // Rezerwacje
  // -------------------------------------------------------------

  Future<List<PanelReservation>> reservations({
    required String restaurantId,
    required DateTime from,
    required DateTime to,
  }) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_reservations',
        params: {
          'p_restaurant_id': restaurantId,
          'p_from': from.toUtc().toIso8601String(),
          'p_to': to.toUtc().toIso8601String(),
        },
      );
      return rows
          .map((e) => PanelReservation.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<String> createReservation(String restaurantId, NewReservation r) {
    return _guard(
      () => _db.rpc<String>(
        'panel_create_reservation',
        params: {
          'p_restaurant_id': restaurantId,
          'p_starts_at': r.startsAt.toUtc().toIso8601String(),
          'p_party_size': r.partySize,
          'p_source': r.source.db,
          'p_guest_name': r.guestName,
          'p_guest_phone': r.guestPhone,
          'p_occasion': r.occasion?.name,
          'p_message': r.message,
          'p_staff_note': r.staffNote,
          'p_table_ids': r.tableIds,
          'p_duration_min': r.durationMinutes,
        },
      ),
    );
  }

  Future<void> setStatus(String reservationId, ReservationStatus status) {
    return _guard(
      () => _db.rpc<void>(
        'panel_set_reservation_status',
        params: {'p_reservation_id': reservationId, 'p_status': status.db},
      ),
    );
  }

  Future<void> moveReservation(String reservationId, List<String> tableIds) {
    return _guard(
      () => _db.rpc<void>(
        'panel_move_reservation',
        params: {'p_reservation_id': reservationId, 'p_table_ids': tableIds},
      ),
    );
  }

  Future<void> setStaffNote(String reservationId, String note) {
    return _guard(
      () => _db.rpc<void>(
        'panel_set_staff_note',
        params: {'p_reservation_id': reservationId, 'p_note': note},
      ),
    );
  }

  /// Wywołuje [onChange] przy każdej zmianie rezerwacji lokalu. Przy nowej rezerwacji
  /// dostaje jej wiersz, przy zmianie istniejącej null. [onStatus] mówi, czy połączenie
  /// działa. Zwraca funkcję, która kończy nasłuchiwanie.
  void Function() watchReservations(
    String restaurantId, {
    required void Function(Map<String, dynamic>? inserted) onChange,
    required void Function(LiveStatus status) onStatus,
  }) {
    // Każde połączenie ma własną nazwę: przy ponownym łączeniu stary kanał jeszcze się zamyka,
    // a nowy nie może trafić na jego nazwę.
    final channel = _db
        .channel('panel-rezerwacje-$restaurantId-${_channelSeq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'reservations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (payload) => onChange(
            payload.eventType == PostgresChangeEvent.insert ? payload.newRecord : null,
          ),
        )
        .subscribe((status, _) {
          onStatus(switch (status) {
            RealtimeSubscribeStatus.subscribed => LiveStatus.live,
            RealtimeSubscribeStatus.channelError ||
            RealtimeSubscribeStatus.timedOut ||
            RealtimeSubscribeStatus.closed => LiveStatus.offline,
          });
        });
    return () => unawaited(_db.removeChannel(channel));
  }

  // -------------------------------------------------------------
  // Plan sali
  // -------------------------------------------------------------

  Future<List<FloorZone>> zones(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('floor_zones')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('position')
          .order('name');
      return rows.map(FloorZone.fromJson).toList();
    });
  }

  Future<List<DiningTable>> tables(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('dining_tables')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('label');
      return rows.map(DiningTable.fromJson).toList();
    });
  }

  Future<List<FloorElement>> elements(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('floor_elements')
          .select()
          .eq('restaurant_id', restaurantId);
      return rows.map(FloorElement.fromJson).toList();
    });
  }

  /// Zapisuje cały układ sali: najpierw usuwa, potem zmienia i dodaje.
  Future<void> saveFloor({
    required String restaurantId,
    required List<FloorZone> zones,
    required List<String> deletedZoneIds,
    required List<DiningTable> tables,
    required List<String> deletedTableIds,
    required List<FloorElement> elements,
    required List<String> deletedElementIds,
  }) {
    return _guard(() async {
      if (deletedTableIds.isNotEmpty) {
        await _db.from('dining_tables').delete().inFilter('id', deletedTableIds);
      }
      if (deletedElementIds.isNotEmpty) {
        await _db.from('floor_elements').delete().inFilter('id', deletedElementIds);
      }

      final keptElements = elements.where((e) => e.id != null).toList();
      final newElements = elements.where((e) => e.id == null).toList();
      if (keptElements.isNotEmpty) {
        await _db
            .from('floor_elements')
            .upsert([for (final e in keptElements) e.toJson(restaurantId)]);
      }
      if (newElements.isNotEmpty) {
        await _db
            .from('floor_elements')
            .insert([for (final e in newElements) e.toJson(restaurantId)]);
      }

      for (var i = 0; i < zones.length; i++) {
        final z = zones[i];
        final row = {
          'restaurant_id': restaurantId,
          'name': z.name.trim(),
          'width_cm': z.widthCm,
          'height_cm': z.heightCm,
          'position': i,
        };
        if (z.id == null) {
          await _db.from('floor_zones').insert(row);
        } else {
          await _db.from('floor_zones').update(row).eq('id', z.id!);
        }
      }

      final existing = tables.where((t) => t.id != null).toList();
      final added = tables.where((t) => t.id == null).toList();
      if (existing.isNotEmpty) {
        await _db
            .from('dining_tables')
            .upsert([for (final t in existing) t.toJson(restaurantId)]);
      }
      if (added.isNotEmpty) {
        await _db
            .from('dining_tables')
            .insert([for (final t in added) t.toJson(restaurantId)]);
      }

      if (deletedZoneIds.isNotEmpty) {
        await _db.from('floor_zones').delete().inFilter('id', deletedZoneIds);
      }
    });
  }

  // -------------------------------------------------------------
  // Lokal i godziny
  // -------------------------------------------------------------

  Future<RestaurantProfile> profile(String restaurantId) {
    return _guard(() async {
      final row = await _db
          .from('restaurants')
          .select(
            'id, name, cuisine, description, address, city, phone, slot_interval_min, max_party_size, price_level, logo_url, '
            'schedule_period, inventory_period, delivery_enabled, pickup_enabled, takeaway_cash, '
            'delivery_fee_grosze, delivery_min_grosze, delivery_area, opening_hours(weekday, opens, closes)',
          )
          .eq('id', restaurantId)
          .single();
      return RestaurantProfile.fromJson(row);
    });
  }

  Future<void> updateProfile(String restaurantId, Map<String, dynamic> fields) {
    return _guard(() async {
      final rows = await _db
          .from('restaurants')
          .update(fields)
          .eq('id', restaurantId)
          .select('id');
      if (rows.isEmpty) {
        throw const AppFailure('Nie masz uprawnień do zmiany danych lokalu.');
      }
    });
  }

  /// Dni wyjątkowe od dziś w przód.
  Future<List<OpeningException>> exceptions(String restaurantId) {
    return _guard(() async {
      final today = DateTime.now();
      final from =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final rows = await _db
          .from('opening_exceptions')
          .select()
          .eq('restaurant_id', restaurantId)
          .gte('day', from)
          .order('day');
      return rows.map(OpeningException.fromJson).toList();
    });
  }

  Future<void> saveException(String restaurantId, OpeningException e) {
    return _guard(
      () => _db.from('opening_exceptions').upsert({
        'restaurant_id': restaurantId,
        'day': _dayOnly(e.day),
        'closed': e.closed,
        'opens': e.closed ? null : e.opens,
        'closes': e.closed ? null : e.closes,
        'note': (e.note == null || e.note!.trim().isEmpty) ? null : e.note!.trim(),
      }),
    );
  }

  Future<void> deleteException(String restaurantId, DateTime day) {
    return _guard(
      () => _db
          .from('opening_exceptions')
          .delete()
          .eq('restaurant_id', restaurantId)
          .eq('day', _dayOnly(day)),
    );
  }

  static String _dayOnly(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Odwołuje wskazane rezerwacje z podanym powodem. Zwraca, ile się udało.
  Future<int> cancelReservations(
    String restaurantId,
    List<String> ids, {
    String? reason,
  }) {
    return _guard(
      () => _db.rpc<int>(
        'panel_cancel_reservations',
        params: {'p_restaurant_id': restaurantId, 'p_ids': ids, 'p_reason': reason},
      ),
    );
  }

  /// Włącza albo wyłącza stolik. Zwraca liczbę nadchodzących rezerwacji na nim.
  Future<int> setTableActive(String tableId, bool active) {
    return _guard(
      () => _db.rpc<int>(
        'panel_set_table_active',
        params: {'p_table_id': tableId, 'p_active': active},
      ),
    );
  }

  /// Przenosi nadchodzące rezerwacje ze stolika na inne wolne stoliki.
  Future<({int moved, int failed})> reassignTable(String tableId) {
    return _guard(() async {
      final result = await _db.rpc<Map<String, dynamic>>(
        'panel_reassign_table',
        params: {'p_table_id': tableId},
      );
      return (
        moved: (result['moved'] as num).toInt(),
        failed: (result['failed'] as num).toInt(),
      );
    });
  }

  Future<void> setHours(String restaurantId, List<OpeningHours> hours) {
    return _guard(
      () => _db.rpc<void>(
        'panel_set_hours',
        params: {
          'p_restaurant_id': restaurantId,
          'p_hours': [for (final h in hours) h.toJson()],
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // Menu
  // -------------------------------------------------------------

  Future<List<MenuSection>> menu(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('menu_sections')
          .select(
            'id, name, position, '
            'menu_items(id, section_id, name, description, price_grosze, allergens, position, '
            'variants, addons, vat_rate, available, show_in_kitchen, photo_url, '
            'menu_item_ingredients(item_id, amount, unit))',
          )
          .eq('restaurant_id', restaurantId)
          .order('position');
      return rows.map(MenuSection.fromJson).toList();
    });
  }

  Future<void> addSection(String restaurantId, String name, int position) {
    return _guard(
      () => _db.from('menu_sections').insert({
        'restaurant_id': restaurantId,
        'name': name.trim(),
        'position': position,
      }),
    );
  }

  Future<void> renameSection(String sectionId, String name) {
    return _guard(
      () => _db
          .from('menu_sections')
          .update({'name': name.trim()})
          .eq('id', sectionId),
    );
  }

  Future<void> deleteSection(String sectionId) {
    return _guard(() => _db.from('menu_sections').delete().eq('id', sectionId));
  }

  /// Zapisuje nową kolejność sekcji albo pozycji.
  Future<void> reorder(String table, List<String> ids) {
    return _guard(() async {
      for (var i = 0; i < ids.length; i++) {
        await _db.from(table).update({'position': i}).eq('id', ids[i]);
      }
    });
  }

  /// Zapisuje pozycję menu i zwraca jej numer (także nowej).
  Future<String> saveItem({
    String? id,
    required String sectionId,
    required String name,
    String? description,
    required int priceGrosze,
    required List<String> allergens,
    required int position,
    List<MenuOption> variants = const [],
    List<MenuOption> addons = const [],
    int vatRate = 8,
    bool available = true,
    bool showInKitchen = true,
  }) {
    final row = {
      'section_id': sectionId,
      'name': name.trim(),
      'description': (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      'price_grosze': priceGrosze,
      'allergens': allergens,
      'position': position,
      'variants': [for (final v in variants) v.toJson()],
      'addons': [for (final a in addons) a.toJson()],
      'vat_rate': vatRate,
      'available': available,
      'show_in_kitchen': showInKitchen,
    };
    return _guard(() async {
      if (id != null) {
        await _db.from('menu_items').update(row).eq('id', id);
        return id;
      }
      final created = await _db.from('menu_items').insert(row).select('id').single();
      return created['id'] as String;
    });
  }

  /// Receptura dania: cała lista składników naraz.
  Future<void> setMenuItemIngredients(String menuItemId, List<RecipeLine> lines) {
    return _guard(
      () => _db.rpc<void>('panel_set_menu_item_ingredients', params: {
        'p_menu_item_id': menuItemId,
        'p_lines': [for (final l in lines) l.toJson()],
      }),
    );
  }

  Future<void> deleteItem(String itemId) {
    return _guard(() => _db.from('menu_items').delete().eq('id', itemId));
  }

  /// „Skończyło się”: może to zrobić także kelner i kuchnia, nie tylko kierownik.
  Future<void> setItemAvailable(String itemId, bool available) {
    return _guard(
      () => _db.rpc<void>(
        'panel_set_menu_item_available',
        params: {'p_item_id': itemId, 'p_available': available},
      ),
    );
  }

  // -------------------------------------------------------------
  // Zamówienia
  // -------------------------------------------------------------

  /// Uprawnienia zalogowanego konta w lokalu, np. {'orders', 'floor'}.
  Future<Set<String>> myPermissions(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_my_permissions',
        params: {'p_restaurant_id': restaurantId},
      );
      return {for (final e in rows) e.toString()};
    });
  }

  /// Otwarte rachunki lokalu razem z pozycjami.
  Future<List<PanelOrder>> openOrders(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('orders')
          .select('id, table_id, reservation_id, note, opened_at, order_items(*)')
          .eq('restaurant_id', restaurantId)
          .eq('kind', 'dine_in')
          .eq('status', 'open')
          .order('opened_at');
      return rows.map(PanelOrder.fromJson).toList();
    });
  }

  /// Wywołuje [onChange] przy każdej zmianie rachunków i ich pozycji w lokalu.
  void Function() watchOrders(
    String restaurantId, {
    required void Function() onChange,
    required void Function(LiveStatus status) onStatus,
  }) {
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'restaurant_id',
      value: restaurantId,
    );
    final channel = _db
        .channel('panel-zamowienia-$restaurantId-${_channelSeq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: filter,
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          filter: filter,
          callback: (_) => onChange(),
        )
        .subscribe((status, _) {
          onStatus(switch (status) {
            RealtimeSubscribeStatus.subscribed => LiveStatus.live,
            RealtimeSubscribeStatus.channelError ||
            RealtimeSubscribeStatus.timedOut ||
            RealtimeSubscribeStatus.closed => LiveStatus.offline,
          });
        });
    return () => unawaited(_db.removeChannel(channel));
  }

  // -------------------------------------------------------------
  // Dostawy i odbiór osobisty
  // -------------------------------------------------------------

  /// Zamówienia na wynos: aktywne i zakończone od [since].
  Future<List<TakeawayOrder>> takeawayOrders(String restaurantId, {required DateTime since}) {
    return _guard(() async {
      final rows = await _db
          .from('orders')
          .select(
            'id, kind, number, fulfillment, opened_at, closed_at, customer_name, customer_phone, delivery_address, '
            'delivery_note, delivery_fee_grosze, payment_choice, payment_status, payment_test, promised_at, accepted_at, '
            'picked_up_at, courier_member, reject_reason, courier:staff_members!orders_courier_member_fkey(name), order_items(*)',
          )
          .eq('restaurant_id', restaurantId)
          .neq('kind', 'dine_in')
          .neq('fulfillment', 'awaiting_payment')
          .or('closed_at.is.null,closed_at.gte.${since.toUtc().toIso8601String()}')
          .order('opened_at');
      return rows.map(TakeawayOrder.fromJson).toList();
    });
  }

  Future<List<Courier>> couriers(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('panel_couriers', params: {'p_restaurant_id': restaurantId});
      return [for (final r in rows) Courier.fromJson(r as Map<String, dynamic>)];
    });
  }

  Future<void> acceptTakeaway(String orderId, int minutes, {String? memberId}) => _guard(
    () => _db.rpc<void>('panel_takeaway_accept', params: {
      'p_order_id': orderId,
      'p_minutes': minutes,
      'p_member_id': memberId,
    }),
  );

  Future<void> rejectTakeaway(String orderId, {String? reason, String? memberId}) => _guard(
    () => _db.rpc<void>('panel_takeaway_reject', params: {
      'p_order_id': orderId,
      'p_reason': reason,
      'p_member_id': memberId,
    }),
  );

  Future<void> takeawayReady(String orderId) =>
      _guard(() => _db.rpc<void>('panel_takeaway_ready', params: {'p_order_id': orderId}));

  Future<void> takeawayHanded(String orderId, {String? memberId}) => _guard(
    () => _db.rpc<void>('panel_takeaway_handed', params: {'p_order_id': orderId, 'p_member_id': memberId}),
  );

  /// Ręczny przydział dostawcy. Null: kurs wraca do kolejki.
  Future<void> assignCourier(String orderId, String? courierId) => _guard(
    () => _db.rpc<void>('panel_takeaway_assign', params: {'p_order_id': orderId, 'p_courier': courierId}),
  );

  /// Bileciki na ekran kuchni: pozycje wysłane w ostatnich godzinach z otwartych rachunków.
  Future<List<KitchenTicket>> kitchenTickets(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('order_items')
          .select('*, menu_items(show_in_kitchen), member:staff_members(name), orders!inner(table_id, status, kind, number, opener:staff_members!opened_by_member(name))')
          .eq('restaurant_id', restaurantId)
          .inFilter('status', ['sent', 'ready', 'cancelled'])
          .eq('orders.status', 'open')
          .gte('sent_at', DateTime.now().subtract(const Duration(hours: 12)).toUtc().toIso8601String())
          .order('sent_at');
      return KitchenTicket.fromRows(rows);
    });
  }

  /// Dane właściciela lokalu, tylko do odczytu (kierownik i właściciel; inni dostają puste). Zmiana w Table Dev.
  Future<OwnerDetails> ownerDetails(String restaurantId) {
    return _guard(() async {
      final row = await _db
          .from('restaurant_owner_details')
          .select()
          .eq('restaurant_id', restaurantId)
          .maybeSingle();
      return OwnerDetails.fromJson(row);
    });
  }

  /// Pojazdy floty lokalu, najpierw aktywne.
  Future<List<Vehicle>> vehicles(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('vehicles')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('active', ascending: false)
          .order('created_at');
      return rows.map(Vehicle.fromJson).toList();
    });
  }

  /// Dodaje pojazd ([id] null) albo zmienia istniejący.
  Future<void> saveVehicle({
    required String restaurantId,
    String? id,
    required VehicleKind kind,
    required String name,
    String? plate,
    String? vin,
    String? memberId,
    String? note,
    bool active = true,
  }) {
    return _guard(
      () => _db.rpc<String>('panel_save_vehicle', params: {
        'p_vin': vin,
        'p_restaurant_id': restaurantId,
        'p_id': id,
        'p_kind': kind.db,
        'p_name': name,
        'p_plate': plate,
        'p_member_id': memberId,
        'p_note': note,
        'p_active': active,
      }),
    );
  }

  Future<void> deleteVehicle(String id) {
    return _guard(() => _db.rpc<void>('panel_delete_vehicle', params: {'p_id': id}));
  }

  /// Baza klientów: goście z rezerwacji i zamówień na wynos, ostatnio widziani pierwsi.
  Future<List<Customer>> customers(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('panel_customers', params: {'p_restaurant_id': restaurantId});
      return [for (final r in rows) Customer.fromJson(r as Map<String, dynamic>)];
    });
  }

  /// Statystyki zespołu za miesiąc kalendarzowy [month].
  Future<List<TeamStat>> teamStats(String restaurantId, DateTime month) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_team_stats',
        params: {'p_restaurant_id': restaurantId, 'p_month': _isoDay(monthStart(month))},
      );
      return [for (final r in rows) TeamStat.fromJson(r as Map<String, dynamic>)];
    });
  }

  /// Ekran „Wydanie”: pozycje z otwartych rachunków, które są na kuchni albo już gotowe.
  Future<List<ServingTicket>> servingTickets(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('order_items')
          .select(
            '*, member:staff_members(name), '
            'orders!inner(table_id, status, kind, number, fulfillment, promised_at, '
            'opener:staff_members!opened_by_member(name))',
          )
          .eq('restaurant_id', restaurantId)
          .inFilter('status', ['sent', 'ready'])
          .eq('orders.status', 'open')
          .gte('sent_at', DateTime.now().subtract(const Duration(hours: 12)).toUtc().toIso8601String())
          .order('sent_at');
      return ServingTicket.fromRows(rows);
    });
  }

  /// Gotowe pozycje zaniesione gościom (ready → served). [undo] cofa pomyłkę.
  Future<int> serveItems(List<String> ids, {bool undo = false}) {
    return _guard(
      () => _db.rpc<int>('panel_serve_items', params: {'p_item_ids': ids, 'p_undo': undo}),
    );
  }

  /// Progi czasu na ekranie kuchni.
  Future<KitchenConfig> kitchenConfig(String restaurantId) {
    return _guard(() async {
      final row = await _db
          .from('restaurants')
          .select('kitchen_warn_minutes, kitchen_late_minutes')
          .eq('id', restaurantId)
          .single();
      return KitchenConfig.fromJson(row);
    });
  }

  /// Zapisuje progi czasu i pozycje menu ukryte przed kuchnią.
  Future<void> setKitchenConfig({
    required String restaurantId,
    required int warnMinutes,
    required int lateMinutes,
    required List<String> hiddenItemIds,
  }) {
    return _guard(
      () => _db.rpc<void>(
        'panel_set_kitchen_config',
        params: {
          'p_restaurant_id': restaurantId,
          'p_warn_minutes': warnMinutes,
          'p_late_minutes': lateMinutes,
          'p_hidden_items': hiddenItemIds,
        },
      ),
    );
  }

  /// Średni czas przygotowania zamówień: dziś i w ostatniej godzinie.
  Future<KitchenStats> kitchenStats(String restaurantId) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>?>(
        'panel_kitchen_stats',
        params: {'p_restaurant_id': restaurantId},
      );
      return KitchenStats.fromJson(json);
    });
  }

  /// Sprzedaż z ostatnich [days] dni.
  Future<SalesStats> salesStats(String restaurantId, int days) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>>(
        'panel_sales_stats',
        params: {'p_restaurant_id': restaurantId, 'p_days': days},
      );
      return SalesStats.fromJson(json);
    });
  }

  // -------------------------------------------------------------
  // Czas pracy i logowanie pracowników kodem QR
  // -------------------------------------------------------------

  /// Nowy kod QR do zeskanowania aplikacją Table for employees.
  /// Kod QR do zeskanowania aplikacją: zaczyna zmianę i loguje, a z [endShiftOf] kończy zmianę tej osoby
  /// (zeskanować go może tylko ona).
  Future<String> newLoginToken(String restaurantId, {String? endShiftOf}) {
    return _guard(
      () => _db.rpc<String>('panel_new_login_token', params: {
        'p_restaurant_id': restaurantId,
        'p_purpose': endShiftOf == null ? 'login' : 'end_shift',
        'p_member_id': endShiftOf,
      }),
    );
  }

  /// Logowanie pracownika w panelu czterocyfrowym kodem. Zaczyna jego zmianę.
  Future<ActingMember> memberLogin({required String restaurantId, required String code}) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>>(
        'panel_member_login',
        params: {'p_restaurant_id': restaurantId, 'p_code': code},
      );
      if (json['error'] case final String problem) throw AppFailure(problem);
      return ActingMember.fromJson(json);
    });
  }

  /// „Zakończ zmianę” czterocyfrowym kodem pracownika [memberId] (kod innej osoby nie zadziała).
  /// Zwraca pracownika z godzinami zakończonej zmiany.
  Future<ActingMember> memberEndShift({required String restaurantId, required String code, String? memberId}) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>>(
        'panel_member_end_shift',
        params: {'p_restaurant_id': restaurantId, 'p_code': code, 'p_member_id': memberId},
      );
      if (json['error'] case final String problem) throw AppFailure(problem);
      return ActingMember.fromJson(json);
    });
  }

  // -------------------------------------------------------------
  // Kody pracowników, grafik i statystyki pracownika
  // -------------------------------------------------------------

  /// Czterocyfrowe kody pracowników lokalu według numeru pracownika (uprawnienie „Kody pracowników”).
  Future<Map<String, String>> staffCodes(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_staff_codes',
        params: {'p_restaurant_id': restaurantId},
      );
      return {
        for (final r in rows.cast<Map<String, dynamic>>()) r['member_id'] as String: r['code'] as String,
      };
    });
  }

  /// Nowy kod pracownika: wpisany (4 cyfry) albo wylosowany (puste). Stary przestaje działać.
  Future<String> setStaffCode(String memberId, {String? code}) {
    return _guard(
      () => _db.rpc<String>('panel_set_staff_code', params: {'p_member_id': memberId, 'p_code': code}),
    );
  }

  Future<List<PlannedShift>> plannedShifts(String restaurantId, {required DateTime from, required DateTime to}) {
    return _guard(() async {
      final rows = await _db
          .from('staff_schedule')
          .select()
          .eq('restaurant_id', restaurantId)
          .gte('day', _isoDay(from))
          .lt('day', _isoDay(to))
          .order('day')
          .order('starts');
      return rows.map(PlannedShift.fromJson).toList();
    });
  }

  /// Grafik na żywo: odpowiedź pracownika z aplikacji od razu widać w panelu.
  void Function() watchSchedule(String restaurantId, void Function() onChange) {
    final channel = _db
        .channel('panel-grafik-$restaurantId-${_channelSeq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'staff_schedule',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => _db.removeChannel(channel);
  }

  /// Przełożony wpisuje godziny sam. Wpis jest od razu przyjęty.
  Future<void> addHours({
    required String memberId,
    required DateTime day,
    required String starts,
    required String ends,
    String? answer,
  }) {
    return _guard(
      () => _db.rpc<void>('panel_add_hours', params: {
        'p_member_id': memberId,
        'p_day': _isoDay(day),
        'p_starts': starts,
        'p_ends': ends,
        'p_answer': answer,
      }),
    );
  }

  /// Decyzja o zgłoszeniu pracownika: przyjęcie (także ze zmienionymi godzinami) albo odrzucenie.
  Future<void> decideHours(String id, {required bool accept, String? starts, String? ends, String? answer}) {
    return _guard(
      () => _db.rpc<void>('panel_decide_hours', params: {
        'p_id': id,
        'p_accept': accept,
        'p_starts': starts,
        'p_ends': ends,
        'p_answer': answer,
      }),
    );
  }

  Future<void> deleteHours(String id) {
    return _guard(() => _db.rpc<void>('panel_delete_hours', params: {'p_id': id}));
  }

  // ---------------------------------------------------------------
  // Inwentaryzacja
  // ---------------------------------------------------------------

  Future<List<InventoryItem>> inventoryItems(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('inventory_items')
          .select('id, name, unit, capacity, sort')
          .eq('restaurant_id', restaurantId)
          .isFilter('deleted_at', null)
          .order('sort')
          .order('name');
      return rows.map(InventoryItem.fromJson).toList();
    });
  }

  /// Nowy składnik (bez [id]) albo zmiana istniejącego. Zwraca numer składnika.
  Future<String> saveInventoryItem(
    String restaurantId, {
    String? id,
    required String name,
    required InventoryUnit unit,
    required double capacity,
  }) {
    return _guard(() async {
      final fields = {'name': name.trim(), 'unit': unit.key, 'capacity': capacity};
      try {
        if (id == null) {
          final created = await _db
              .from('inventory_items')
              .insert({...fields, 'restaurant_id': restaurantId})
              .select('id')
              .single();
          return created['id'] as String;
        }
        final rows = await _db.from('inventory_items').update(fields).eq('id', id).select('id');
        if (rows.isEmpty) throw const AppFailure('Nie masz uprawnień do zmiany składników.');
        return id;
      } on PostgrestException catch (e) {
        if (e.code == '23505') throw const AppFailure('Składnik o tej nazwie już jest na liście.');
        rethrow;
      }
    });
  }

  /// Usunięty składnik znika z listy, ale zostaje w historii spisów.
  Future<void> deleteInventoryItem(String id) {
    return _guard(() async {
      final rows = await _db
          .from('inventory_items')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id)
          .select('id');
      if (rows.isEmpty) throw const AppFailure('Nie masz uprawnień do usuwania składników.');
    });
  }

  /// Stan składników teraz: z ostatniej inwentaryzacji minus sprzedaż.
  Future<List<InventoryStock>> inventoryStock(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('panel_inventory_stock', params: {'p_restaurant_id': restaurantId});
      return [for (final r in rows) InventoryStock.fromJson(r as Map<String, dynamic>)];
    });
  }

  Future<void> setInventoryPeriod(String restaurantId, String period) {
    return _guard(
      () => _db.rpc<void>('panel_set_inventory_period', params: {'p_restaurant_id': restaurantId, 'p_period': period}),
    );
  }

  /// Spisy od najnowszego. Trwający (jeśli jest) jest pierwszy.
  Future<List<InventoryCount>> inventoryCounts(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('panel_inventory_counts', params: {'p_restaurant_id': restaurantId});
      return [for (final r in rows) InventoryCount.fromJson(r as Map<String, dynamic>)];
    });
  }

  /// Zaczyna inwentaryzację albo zwraca tę, która już trwa.
  Future<String> startInventory(String restaurantId, {String? memberId}) {
    return _guard(
      () => _db.rpc<String>('panel_inventory_start', params: {'p_restaurant_id': restaurantId, 'p_member_id': memberId}),
    );
  }

  /// Ilość składnika w opakowaniach. Null czyści wpis.
  Future<void> setInventoryQuantity(String countId, String itemId, double? quantity, {String? memberId}) {
    return _guard(
      () => _db.rpc<void>('panel_inventory_set', params: {
        'p_count_id': countId,
        'p_item_id': itemId,
        'p_quantity': quantity,
        'p_member_id': memberId,
      }),
    );
  }

  Future<void> finishInventory(String countId, {String? memberId}) {
    return _guard(
      () => _db.rpc<void>('panel_inventory_finish', params: {'p_count_id': countId, 'p_member_id': memberId}),
    );
  }

  Future<void> discardInventory(String countId) {
    return _guard(() => _db.rpc<void>('panel_inventory_discard', params: {'p_count_id': countId}));
  }

  /// Przełożony daje wolne w danym dniu. Zastępuje zgłoszenie albo przyjęte godziny.
  Future<void> setDayOff({required String memberId, required DateTime day, String? answer}) {
    return _guard(
      () => _db.rpc<void>('panel_set_day_off', params: {
        'p_member_id': memberId,
        'p_day': _isoDay(day),
        'p_answer': answer,
      }),
    );
  }

  /// Statystyki pracownika za miesiąc kalendarzowy [month] (od 1. do ostatniego dnia, czas lokalu).
  Future<MemberStats> memberStats(String memberId, DateTime month) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>>(
        'panel_member_stats',
        params: {'p_member_id': memberId, 'p_month': _isoDay(monthStart(month))},
      );
      return MemberStats.fromJson(json);
    });
  }

  /// Pracownik, który zeskanował kod, albo null, gdy jeszcze nikt.
  Future<ActingMember?> loginTokenStatus(String token) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>?>(
        'panel_login_token_status',
        params: {'p_token': token},
      );
      if (json == null || json['claimed'] != true) return null;
      return ActingMember.fromJson(json);
    });
  }

  /// Zmiany pracowników lokalu, które zaczęły się w okresie albo nadal trwają.
  Future<List<StaffShift>> shifts(String restaurantId, {required DateTime from, required DateTime to}) {
    return _guard(() async {
      final rows = await _db
          .from('staff_shifts')
          .select()
          .eq('restaurant_id', restaurantId)
          .or('ended_at.is.null,started_at.gte.${from.toUtc().toIso8601String()}')
          .lt('started_at', to.toUtc().toIso8601String())
          .order('started_at');
      return rows.map(StaffShift.fromJson).toList();
    });
  }

  Future<void> endShift(String memberId) {
    return _guard(() => _db.rpc<void>('staff_end_shift', params: {'p_member_id': memberId}));
  }

  Future<void> saveShift({
    String? id,
    required String memberId,
    required DateTime startedAt,
    DateTime? endedAt,
  }) {
    return _guard(
      () => _db.rpc<void>(
        'panel_save_shift',
        params: {
          'p_id': id,
          'p_member_id': memberId,
          'p_started_at': startedAt.toUtc().toIso8601String(),
          'p_ended_at': endedAt?.toUtc().toIso8601String(),
        },
      ),
    );
  }

  Future<void> deleteShift(String id) {
    return _guard(() => _db.rpc<void>('panel_delete_shift', params: {'p_id': id}));
  }

  /// Wywołuje [onChange] przy każdej zmianie czasu pracy w lokalu.
  void Function() watchShifts(String restaurantId, void Function() onChange) {
    final channel = _db
        .channel('panel-zmiany-$restaurantId-${_channelSeq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'staff_shifts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'restaurant_id',
            value: restaurantId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => unawaited(_db.removeChannel(channel));
  }

  /// Zamknięte rachunki (opłacone i anulowane) z jednego dnia, najnowsze pierwsze.
  Future<List<PanelOrder>> orderHistory(String restaurantId, DateTime day) {
    return _guard(() async {
      final rows = await _db
          .from('orders')
          .select(
            'id, table_id, reservation_id, note, status, opened_at, closed_at, '
            'payment_method, gift_card_grosze, kind, number, order_items(*)',
          )
          .eq('restaurant_id', restaurantId)
          .inFilter('status', ['paid', 'cancelled'])
          .gte('closed_at', day.toUtc().toIso8601String())
          .lt('closed_at', DateTime(day.year, day.month, day.day + 1).toUtc().toIso8601String())
          .order('closed_at', ascending: false);
      return rows.map(PanelOrder.fromJson).toList();
    });
  }

  /// Kuchnia oznacza pozycje jako gotowe albo cofa to.
  Future<int> kitchenSet(List<String> itemIds, {required bool done}) {
    return _guard(
      () => _db.rpc<int>(
        'panel_kitchen_set',
        params: {'p_item_ids': itemIds, 'p_done': done},
      ),
    );
  }

  /// Otwiera rachunek przy stoliku albo zwraca już otwarty. [memberId] to pracownik
  /// zalogowany kodem QR, zapisany jako ten, kto rachunek otworzył.
  Future<String> openOrder(String restaurantId, String tableId, {String? memberId}) {
    return _guard(
      () => _db.rpc<String>(
        'panel_open_order',
        params: {'p_restaurant_id': restaurantId, 'p_table_id': tableId, 'p_member_id': memberId},
      ),
    );
  }

  Future<void> addOrderItem({
    required String orderId,
    required String menuItemId,
    String? variant,
    List<String> addons = const [],
    int quantity = 1,
    String? note,
    int course = 1,
    String? memberId,
  }) {
    return _guard(
      () => _db.rpc<String>(
        'panel_add_order_item',
        params: {
          'p_order_id': orderId,
          'p_menu_item_id': menuItemId,
          'p_variant': variant,
          'p_addons': addons,
          'p_quantity': quantity,
          'p_note': note,
          'p_course': course,
          'p_member_id': memberId,
        },
      ),
    );
  }

  /// Zmienia ilość, uwagę albo stan pozycji. Anulowana nowa pozycja znika z rachunku.
  Future<void> updateOrderItem(
    String itemId, {
    int? quantity,
    String? note,
    OrderItemStatus? status,
  }) {
    return _guard(
      () => _db.rpc<void>(
        'panel_update_order_item',
        params: {
          'p_item_id': itemId,
          'p_quantity': quantity,
          'p_note': note,
          'p_status': status?.db,
        },
      ),
    );
  }

  /// Wysyła nowe pozycje na kuchnię. Zwraca ich liczbę.
  Future<int> sendOrder(String orderId) {
    return _guard(
      () => _db.rpc<int>('panel_send_order', params: {'p_order_id': orderId}),
    );
  }

  /// Zamyka rachunek płatnością [method].
  Future<void> closeOrder(String orderId, PaymentMethod method, {String? memberId}) {
    return _guard(
      () => _db.rpc<void>(
        'panel_close_order',
        params: {
          'p_order_id': orderId,
          'p_payment_method': method.db,
          'p_gift_card_id': null,
          'p_gift_amount': null,
          'p_member_id': memberId,
        },
      ),
    );
  }

  Future<void> cancelOrder(String orderId) {
    return _guard(
      () => _db.rpc<void>('panel_cancel_order', params: {'p_order_id': orderId}),
    );
  }

  Future<void> moveOrder(String orderId, String tableId) {
    return _guard(
      () => _db.rpc<void>(
        'panel_move_order',
        params: {'p_order_id': orderId, 'p_table_id': tableId},
      ),
    );
  }

  // -------------------------------------------------------------
  // Opinie i statystyki
  // -------------------------------------------------------------

  Future<List<PanelReview>> reviews(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_reviews',
        params: {'p_restaurant_id': restaurantId, 'p_limit': 200},
      );
      return rows
          .map((e) => PanelReview.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<void> replyToReview(String reviewId, String body) {
    return _guard(
      () => _db.rpc<void>(
        'panel_reply_review',
        params: {'p_review_id': reviewId, 'p_body': body},
      ),
    );
  }

  Future<List<OccasionStat>> occasionStats(String restaurantId, int days) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_occasion_stats',
        params: {'p_restaurant_id': restaurantId, 'p_days': days},
      );
      return rows
          .map((e) => OccasionStat.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<List<DayStat>> stats(String restaurantId, int days) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_stats',
        params: {'p_restaurant_id': restaurantId, 'p_days': days},
      );
      return rows
          .map((e) => DayStat.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  // -------------------------------------------------------------
  // Logo lokalu
  // -------------------------------------------------------------

  static const logoBucket = 'restaurant-logos';
  static const menuPhotoBucket = 'menu-photos';

  /// Wgrywa zdjęcie dania (już zmniejszone, JPG) i zapisuje jego adres przy pozycji menu.
  Future<String> uploadMenuPhoto({
    required String restaurantId,
    required String itemId,
    required Uint8List jpeg,
  }) {
    return _guard(() async {
      // Nowa nazwa przy każdej zmianie, żeby aplikacje nie pokazywały starego zdjęcia z pamięci podręcznej.
      final path = '$restaurantId/$itemId-${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _db.storage.from(menuPhotoBucket).uploadBinary(
        path,
        jpeg,
        fileOptions: const FileOptions(contentType: 'image/jpeg'),
      );
      final url = _db.storage.from(menuPhotoBucket).getPublicUrl(path);
      await _db.from('menu_items').update({'photo_url': url}).eq('id', itemId);
      return url;
    });
  }

  Future<void> removeMenuPhoto(String itemId) {
    return _guard(() => _db.from('menu_items').update({'photo_url': null}).eq('id', itemId));
  }

  /// Wgrywa logo do Storage i zapisuje jego publiczny adres w profilu lokalu.
  Future<String> uploadLogo({
    required String restaurantId,
    required Uint8List bytes,
    required String extension,
  }) {
    return _guard(() async {
      final ext = extension.toLowerCase() == 'jpeg' ? 'jpg' : extension.toLowerCase();
      final contentType = switch (ext) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      // Nowa nazwa przy każdej zmianie, żeby aplikacje nie pokazywały starego logo z pamięci podręcznej.
      final path = '$restaurantId/logo-${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _db.storage.from(logoBucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: contentType),
      );
      final url = _db.storage.from(logoBucket).getPublicUrl(path);
      await updateProfile(restaurantId, {'logo_url': url});
      return url;
    });
  }

  Future<void> removeLogo(String restaurantId) {
    return updateProfile(restaurantId, {'logo_url': null});
  }

  // -------------------------------------------------------------
  // Pracownicy i dyspozycyjność
  // -------------------------------------------------------------

  Future<List<StaffMember>> staff(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('staff_members')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('name');
      return rows.map(StaffMember.fromJson).toList();
    });
  }

  /// Zapisuje pracownika i zwraca jego numer (nowy przy dodaniu).
  Future<String> saveStaffMember({
    required String restaurantId,
    String? id,
    required String firstName,
    required String lastName,
    required StaffPosition position,
    required String phone,
    required int color,
    bool active = true,
  }) {
    final row = {
      'restaurant_id': restaurantId,
      'first_name': firstName.trim(),
      'last_name': lastName.trim(),
      // Pełne imię i nazwa stanowiska zostają też w starych polach dla list i starszych wersji panelu.
      'name': '${firstName.trim()} ${lastName.trim()}',
      'position_id': position.id,
      'position': position.name,
      'phone': phone.trim(),
      'color': color,
      'active': active,
    };
    return _guard(() async {
      if (id != null) {
        await _db.from('staff_members').update(row).eq('id', id);
        return id;
      }
      final created = await _db.from('staff_members').insert(row).select('id').single();
      return created['id'] as String;
    });
  }

  /// Stawki brutto za godzinę i rodzaje umów według numeru pracownika (tylko z uprawnieniem „Pracownicy”).
  Future<Map<String, StaffRate>> staffRates(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('staff_rates')
          .select('member_id, hourly_rate_grosze, contract')
          .eq('restaurant_id', restaurantId);
      return {
        for (final r in rows)
          r['member_id'] as String: StaffRate(
            grossGrosze: (r['hourly_rate_grosze'] as num).toInt(),
            contract: Contract.from(r['contract']),
          ),
      };
    });
  }

  /// Stawka brutto za godzinę w groszach i rodzaj umowy. Null usuwa stawkę.
  Future<void> setStaffRate(String memberId, int? grosze, Contract contract) {
    return _guard(
      () => _db.rpc<void>('panel_set_staff_rate', params: {
        'p_member_id': memberId,
        'p_rate_grosze': grosze,
        'p_contract': contract.db,
      }),
    );
  }

  /// Wizyty i zamówienia klienta, najnowsze pierwsze.
  Future<List<CustomerEvent>> customerHistory(String restaurantId, String key) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_customer_history',
        params: {'p_restaurant_id': restaurantId, 'p_key': key},
      );
      return [for (final r in rows) CustomerEvent.fromJson(r as Map<String, dynamic>)];
    });
  }

  /// Notatki o kliencie, najnowsze pierwsze.
  Future<List<Note>> customerNotes(String restaurantId, String key) {
    return _guard(() async {
      final rows = await _db
          .from('customer_notes')
          .select()
          .eq('restaurant_id', restaurantId)
          .eq('customer_key', key)
          .order('created_at', ascending: false);
      return rows.map(Note.fromJson).toList();
    });
  }

  Future<void> addCustomerNote(String restaurantId, String key, String body, {String? memberId}) {
    return _guard(
      () => _db.rpc<String>('panel_add_customer_note', params: {
        'p_restaurant_id': restaurantId,
        'p_key': key,
        'p_body': body,
        'p_member_id': memberId,
      }),
    );
  }

  Future<void> deleteCustomerNote(String id) {
    return _guard(() => _db.rpc<void>('panel_delete_customer_note', params: {'p_id': id}));
  }

  /// Notatki o pojazdach lokalu według pojazdu, najnowsze pierwsze.
  Future<Map<String, List<Note>>> vehicleNotes(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('vehicle_notes')
          .select()
          .eq('restaurant_id', restaurantId)
          .order('created_at', ascending: false);
      final notes = <String, List<Note>>{};
      for (final r in rows) {
        final note = Note.fromJson(r);
        notes.putIfAbsent(note.parentId ?? '', () => []).add(note);
      }
      return notes;
    });
  }

  Future<void> addVehicleNote(String vehicleId, String body, {String? memberId}) {
    return _guard(
      () => _db.rpc<String>('panel_add_vehicle_note', params: {
        'p_vehicle_id': vehicleId,
        'p_body': body,
        'p_member_id': memberId,
      }),
    );
  }

  Future<void> deleteVehicleNote(String id) {
    return _guard(() => _db.rpc<void>('panel_delete_vehicle_note', params: {'p_id': id}));
  }

  Future<void> deleteStaffMember(String id) {
    return _guard(() => _db.from('staff_members').delete().eq('id', id));
  }

  /// Adresy e-mail kont połączonych z pracownikami, według numeru pracownika.
  Future<Map<String, String>> staffAccounts(String restaurantId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_staff_accounts',
        params: {'p_restaurant_id': restaurantId},
      );
      return {
        for (final e in rows.cast<Map<String, dynamic>>())
          e['member_id'] as String: e['email'] as String,
      };
    });
  }

  /// Łączy pracownika z kontem założonym wcześniej w Supabase. Konto dostaje dostęp do lokalu.
  Future<void> linkStaffAccount(String memberId, String email) {
    return _guard(
      () => _db.rpc<void>(
        'panel_link_staff_account',
        params: {'p_member_id': memberId, 'p_email': email.trim()},
      ),
    );
  }

  Future<void> unlinkStaffAccount(String memberId) {
    return _guard(
      () => _db.rpc<void>(
        'panel_unlink_staff_account',
        params: {'p_member_id': memberId},
      ),
    );
  }

  /// Stanowiska systemowe i własne stanowiska lokalu.
  Future<List<StaffPosition>> positions(String restaurantId) {
    return _guard(() async {
      final rows = await _db
          .from('staff_positions')
          .select()
          .or('restaurant_id.is.null,restaurant_id.eq.$restaurantId')
          .order('sort')
          .order('name');
      return rows.map(StaffPosition.fromJson).toList();
    });
  }

  Future<void> savePosition({
    required String restaurantId,
    String? id,
    required String name,
    required List<StaffPermission> permissions,
  }) {
    final row = {
      'restaurant_id': restaurantId,
      'name': name.trim(),
      'permissions': [for (final p in permissions) p.key],
    };
    return _guard(
      () => id == null
          ? _db.from('staff_positions').insert(row)
          : _db.from('staff_positions').update(row).eq('id', id),
    );
  }

  Future<void> deletePosition(String id) {
    return _guard(() => _db.from('staff_positions').delete().eq('id', id));
  }

  Future<List<Availability>> availability({
    required String restaurantId,
    required DateTime from,
    required DateTime to,
  }) {
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return _guard(() async {
      final rows = await _db
          .from('staff_availability')
          .select()
          .eq('restaurant_id', restaurantId)
          .gte('day', d(from))
          .lt('day', d(to))
          .order('starts');
      return rows.map(Availability.fromJson).toList();
    });
  }

  Future<void> saveAvailability({
    required String restaurantId,
    String? id,
    required String memberId,
    required DateTime day,
    required String starts,
    required String ends,
    String? note,
  }) {
    final row = {
      'restaurant_id': restaurantId,
      'member_id': memberId,
      'day':
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      'starts': starts,
      'ends': ends,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    };
    return _guard(
      () => id == null
          ? _db.from('staff_availability').insert(row)
          : _db.from('staff_availability').update(row).eq('id', id),
    );
  }

  Future<void> deleteAvailability(String id) {
    return _guard(() => _db.from('staff_availability').delete().eq('id', id));
  }

  // -------------------------------------------------------------
  // Błędy
  // -------------------------------------------------------------

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AppFailure(_authMessage(e));
    } on PostgrestException catch (e) {
      // Komunikaty z funkcji w bazie są już po polsku.
      if (e.code == 'P0001' && e.message.isNotEmpty) {
        throw AppFailure(e.message);
      }
      if (e.code == '42501') {
        throw const AppFailure('Nie masz uprawnień do tej operacji.');
      }
      if (e.code == '23505') {
        throw const AppFailure('Taka nazwa już istnieje. Wybierz inną.');
      }
      if (e.code == '23514') {
        throw const AppFailure('Sprawdź wpisane wartości, któraś jest poza dozwolonym zakresem.');
      }
      throw const AppFailure('Nie udało się zapisać ani pobrać danych. Spróbuj ponownie.');
    } catch (_) {
      throw const AppFailure(
        'Brak połączenia z serwerem. Sprawdź internet i spróbuj ponownie.',
      );
    }
  }

  String _authMessage(AuthException e) {
    final code = e.code ?? '';
    final message = e.message.toLowerCase();
    if (code == 'invalid_credentials' || message.contains('invalid login')) {
      return 'Nieprawidłowy e-mail lub hasło.';
    }
    if (code == 'email_not_confirmed') {
      return 'Potwierdź adres e-mail, klikając link z wiadomości od nas.';
    }
    if (code.contains('rate_limit') || e.statusCode == '429') {
      return 'Za dużo prób. Odczekaj minutę i spróbuj ponownie.';
    }
    return 'Nie udało się zalogować. Spróbuj ponownie.';
  }
}

/// Dzień jako „RRRR-MM-DD” dla kolumn typu date.
String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
