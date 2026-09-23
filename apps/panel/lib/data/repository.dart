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
    final channel = _db
        .channel('panel-rezerwacje-$restaurantId')
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
            'opening_hours(weekday, opens, closes)',
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
            'menu_items(id, section_id, name, description, price_grosze, allergens, position)',
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

  Future<void> saveItem({
    String? id,
    required String sectionId,
    required String name,
    String? description,
    required int priceGrosze,
    required List<String> allergens,
    required int position,
  }) {
    final row = {
      'section_id': sectionId,
      'name': name.trim(),
      'description': (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      'price_grosze': priceGrosze,
      'allergens': allergens,
      'position': position,
    };
    return _guard(
      () => id == null
          ? _db.from('menu_items').insert(row)
          : _db.from('menu_items').update(row).eq('id', id),
    );
  }

  Future<void> deleteItem(String itemId) {
    return _guard(() => _db.from('menu_items').delete().eq('id', itemId));
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

  Future<void> saveStaffMember({
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
    return _guard(
      () => id == null
          ? _db.from('staff_members').insert(row)
          : _db.from('staff_members').update(row).eq('id', id),
    );
  }

  Future<void> deleteStaffMember(String id) {
    return _guard(() => _db.from('staff_members').delete().eq('id', id));
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
  // Karty podarunkowe
  // -------------------------------------------------------------

  Future<List<GiftCard>> giftCards(String restaurantId, {String? code}) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'panel_gift_cards',
        params: {'p_restaurant_id': restaurantId, 'p_code': code},
      );
      return rows
          .map((e) => GiftCard.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Pobiera kwotę z karty. Zwraca saldo po operacji w groszach.
  Future<int> redeemGiftCard(String cardId, int amountGrosze) {
    return _guard(
      () => _db.rpc<int>(
        'panel_redeem_gift_card',
        params: {'p_card_id': cardId, 'p_amount_grosze': amountGrosze},
      ),
    );
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
