import 'dart:async';

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

  /// Wywołuje [onChange] przy każdej zmianie rezerwacji lokalu.
  /// Zwraca funkcję, która kończy nasłuchiwanie.
  void Function() watchReservations(String restaurantId, void Function() onChange) {
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
          callback: (_) => onChange(),
        )
        .subscribe();
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
          .order('position');
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

  /// Zapisuje cały układ sali: najpierw usuwa, potem zmienia i dodaje.
  Future<void> saveFloor({
    required String restaurantId,
    required List<FloorZone> zones,
    required List<String> deletedZoneIds,
    required List<DiningTable> tables,
    required List<String> deletedTableIds,
  }) {
    return _guard(() async {
      if (deletedTableIds.isNotEmpty) {
        await _db.from('dining_tables').delete().inFilter('id', deletedTableIds);
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
            'id, name, cuisine, description, address, city, phone, slot_interval_min, price_level, '
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
