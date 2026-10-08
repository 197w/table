import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'models.dart';

/// Jedyne miejsce, które rozmawia z Supabase.
/// Każdy błąd zamienia na AppFailure z polskim komunikatem.
class Repository {
  Repository(this._db);

  final SupabaseClient _db;

  // -------------------------------------------------------------
  // Logowanie i rejestracja
  // -------------------------------------------------------------

  Session? get session => _db.auth.currentSession;

  Future<void> signUp({required String phone, required String password}) {
    return _guard(
      () => _db.auth.signUp(
        phone: phone,
        password: password,
        channel: OtpChannel.sms,
      ),
    );
  }

  Future<void> verifySmsCode({required String phone, required String code}) {
    return _guard(
      () => _db.auth.verifyOTP(type: OtpType.sms, token: code, phone: phone),
    );
  }

  /// Nie zdradza, czy numer ma konto: przy nieznanym numerze kończy się bez błędu,
  /// a gość po prostu nie dostaje SMS-a.
  Future<void> sendLoginCode(String phone) {
    return _guard(() async {
      try {
        await _db.auth.signInWithOtp(phone: phone, shouldCreateUser: false);
      } on AuthException catch (e) {
        final code = e.code ?? '';
        final message = e.message.toLowerCase();
        final unknownNumber =
            code == 'otp_disabled' ||
            code == 'user_not_found' ||
            code == 'signup_disabled' ||
            message.contains('signups not allowed');
        if (!unknownNumber) rethrow;
      }
    });
  }

  Future<void> resendSignupCode(String phone) {
    return _guard(() => _db.auth.resend(type: OtpType.sms, phone: phone));
  }

  Future<void> signInWithPassword({
    required String phone,
    required String password,
  }) {
    return _guard(
      () => _db.auth.signInWithPassword(phone: phone, password: password),
    );
  }

  Future<void> signOut() => _guard(() => _db.auth.signOut());

  // -------------------------------------------------------------
  // Odkrywanie lokali
  // -------------------------------------------------------------

  /// Z miastem pokazuje wszystkie lokale w mieście, bez miasta lokale w promieniu od punktu.
  /// Odległość zawsze liczy się od podanego punktu.
  Future<List<RestaurantSummary>> search({
    required double lat,
    required double lng,
    double radiusKm = 10,
    String? city,
    String? cuisine,
    String sort = 'ranking',
    String? query,
  }) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'search_restaurants',
        params: {
          'p_lat': lat,
          'p_lng': lng,
          'p_radius_km': radiusKm,
          'p_cuisine': cuisine,
          'p_sort': sort,
          'p_city': city,
          'p_query': query,
        },
      );
      return rows
          .map((e) => RestaurantSummary.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  Future<List<City>> cities() {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('restaurant_cities');
      return rows.map((e) => City.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  Future<List<CuisineRow>> cuisineRows() {
    return _guard(() async {
      final rows = await _db.from('restaurants').select('city, cuisine');
      return [
        for (final r in rows)
          (city: r['city'] as String, cuisine: r['cuisine'] as String),
      ];
    });
  }

  /// Null, gdy rezerwacja nie istnieje albo należy do innego konta.
  Future<ReservationDetail?> reservationDetail(String reservationId) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'reservation_details',
        params: {'p_reservation_id': reservationId},
      );
      if (rows.isEmpty) return null;
      return ReservationDetail.fromJson(rows.first as Map<String, dynamic>);
    });
  }

  Future<RestaurantDetail> restaurant(String id) {
    return _guard(() async {
      // Oba zapytania startują równocześnie, a rekord zachowuje ich typy.
      final (json, ratingRows) = await (
        _db
            .from('restaurants')
            .select(
              'id, name, cuisine, price_level, description, address, city, phone, plan, is_example, logo_url, max_party_size, '
              'deposit_min_party, deposit_per_person_grosze, '
              'delivery_enabled, pickup_enabled, takeaway_cash, delivery_fee_grosze, delivery_min_grosze, delivery_area, '
              'kitchen_lead_pickup_min, kitchen_lead_delivery_min, '
              'opening_hours(weekday, opens, closes), '
              'menu_sections(id, name, position, menu_items(id, name, description, price_grosze, allergens, position, variants, addons, available, photo_url))',
            )
            .eq('id', id)
            .single(),
        _db.rpc<List<dynamic>>(
          'restaurant_rating',
          params: {'p_restaurant_id': id},
        ),
      ).wait;
      final rating = ratingRows.isEmpty
          ? Rating.empty
          : Rating.fromJson(ratingRows.first as Map<String, dynamic>);
      return RestaurantDetail.fromJson(json, rating);
    });
  }

  Future<List<Review>> reviews(
    String restaurantId, {
    int limit = 20,
    int offset = 0,
  }) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'restaurant_reviews',
        params: {
          'p_restaurant_id': restaurantId,
          'p_limit': limit,
          'p_offset': offset,
        },
      );
      return rows
          .map((e) => Review.fromJson(e as Map<String, dynamic>))
          .toList();
    });
  }

  /// Statystyki nie mogą blokować gościa, więc błędy są pomijane.
  Future<void> logEvent(String restaurantId, String kind) async {
    try {
      await _db.rpc<void>(
        'log_restaurant_event',
        params: {'p_restaurant_id': restaurantId, 'p_kind': kind},
      );
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // Rezerwacje
  // -------------------------------------------------------------

  Future<List<DateTime>> availableSlots({
    required String restaurantId,
    required DateTime date,
    required int partySize,
  }) {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>(
        'available_slots',
        params: {
          'p_restaurant_id': restaurantId,
          'p_date': DateFormat('yyyy-MM-dd').format(date),
          'p_party_size': partySize,
        },
      );
      return rows
          .map(
            (e) => DateTime.parse(
              (e as Map<String, dynamic>)['slot_start'] as String,
            ),
          )
          .toList();
    });
  }

  Future<String> book({
    required String restaurantId,
    required DateTime startsAt,
    required int partySize,
    Occasion? occasion,
    String? message,
    String? diet,
    bool dietConsent = false,
    String? discountCode,
  }) {
    return _guard(() async {
      final id = await _db.rpc<String>(
        'book_table',
        params: {
          'p_restaurant_id': restaurantId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_party_size': partySize,
          'p_occasion': occasion?.name,
          'p_message': message,
          'p_diet': diet,
          'p_diet_consent': dietConsent,
          'p_discount_code': (discountCode == null || discountCode.trim().isEmpty) ? null : discountCode.trim(),
        },
      );
      return id;
    });
  }

  /// Sprawdza kod rabatowy lokalu na dzień wizyty. Błąd, gdy kod nie działa.
  Future<GuestDiscount> checkDiscount(String restaurantId, String code, {DateTime? startsAt}) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>>(
        'guest_check_discount',
        params: {
          'p_restaurant_id': restaurantId,
          'p_code': code.trim(),
          'p_starts_at': startsAt?.toUtc().toIso8601String(),
        },
      );
      return GuestDiscount.fromJson(json);
    });
  }

  Future<List<Reservation>> myReservations() {
    return _guard(() async {
      final rows = await _db
          .from('reservations')
          .select(
            'id, restaurant_id, party_size, starts_at, ends_at, status, occasion, message, '
            'restaurants(name, address, phone, logo_url)',
          )
          .order('starts_at', ascending: false)
          .limit(100);
      return rows.map(Reservation.fromJson).toList();
    });
  }

  Future<Set<String>> myReviewedReservations() {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('my_reviewed_reservations');
      return rows.map((e) {
        if (e is Map) return e.values.first as String;
        return e as String;
      }).toSet();
    });
  }

  Future<void> cancelReservation(String id) {
    return _guard(
      () =>
          _db.rpc<void>('cancel_reservation', params: {'p_reservation_id': id}),
    );
  }

  // -------------------------------------------------------------
  // Opinie
  // -------------------------------------------------------------

  Future<void> submitReview({
    required String restaurantId,
    required int food,
    required int service,
    required int ambience,
    String? body,
    String? reservationId,
    int? pricePerPerson,
  }) {
    return _guard(
      () => _db.rpc<String>(
        'submit_review',
        params: {
          'p_restaurant_id': restaurantId,
          'p_food': food,
          'p_service': service,
          'p_ambience': ambience,
          'p_body': body,
          'p_reservation_id': reservationId,
          'p_price_per_person': pricePerPerson,
        },
      ),
    );
  }

  // -------------------------------------------------------------
  // Profil
  // -------------------------------------------------------------

  Future<Profile?> myProfile() {
    return _guard(() async {
      final user = _db.auth.currentUser;
      if (user == null) return null;
      final row = await _db
          .from('profiles')
          .select('id, first_name, full_name')
          .eq('id', user.id)
          .maybeSingle();
      return Profile(
        id: user.id,
        firstName: row?['first_name'] as String?,
        fullName: row?['full_name'] as String?,
        phone: user.phone,
      );
    });
  }

  Future<void> updateNames({
    required String firstName,
    required String fullName,
  }) {
    return _guard(() async {
      final user = _db.auth.currentUser;
      if (user == null) {
        throw const AppFailure('Zaloguj się, żeby zmienić profil.');
      }
      String? clean(String value) {
        final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
        return trimmed.isEmpty ? null : trimmed;
      }

      await _db
          .from('profiles')
          .update({
            'first_name': clean(firstName),
            'full_name': clean(fullName),
          })
          .eq('id', user.id);
    });
  }

  /// Sprawdza obecne hasło, żeby odblokowany telefon nie wystarczył do przejęcia konta.
  Future<void> _confirmPassword(String password) async {
    final phone = _db.auth.currentUser?.phone;
    if (phone == null || phone.isEmpty) {
      throw const AppFailure('Zaloguj się ponownie i spróbuj jeszcze raz.');
    }
    try {
      await _db.auth.signInWithPassword(phone: '+$phone', password: password);
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials' ||
          e.message.toLowerCase().contains('invalid login')) {
        throw const AppFailure('Obecne hasło jest nieprawidłowe.');
      }
      rethrow;
    }
  }

  /// Wysyła kod SMS na nowy numer. Numer zmienia się dopiero po wpisaniu kodu.
  Future<void> requestPhoneChange({
    required String newPhone,
    required String currentPassword,
  }) {
    return _guard(() async {
      final current = _db.auth.currentUser?.phone ?? '';
      if ('+$current' == newPhone) {
        throw const AppFailure('To jest twój obecny numer.');
      }
      await _confirmPassword(currentPassword);
      try {
        await _db.auth.updateUser(UserAttributes(phone: newPhone));
      } on AuthException catch (e) {
        if (e.code == 'phone_exists' ||
            e.message.toLowerCase().contains('already')) {
          throw const AppFailure(
            'Ten numer jest już przypisany do innego konta.',
          );
        }
        rethrow;
      }
    });
  }

  Future<void> verifyPhoneChange({
    required String phone,
    required String code,
  }) {
    return _guard(
      () => _db.auth.verifyOTP(
        type: OtpType.phoneChange,
        token: code,
        phone: phone,
      ),
    );
  }

  Future<void> resendPhoneChangeCode(String phone) {
    return _guard(
      () => _db.auth.resend(type: OtpType.phoneChange, phone: phone),
    );
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    return _guard(() async {
      await _confirmPassword(currentPassword);
      try {
        await _db.auth.updateUser(UserAttributes(password: newPassword));
      } on AuthException catch (e) {
        if (e.code == 'same_password') {
          throw const AppFailure('Nowe hasło musi różnić się od obecnego.');
        }
        rethrow;
      }
    });
  }

  /// Bez zapisanego wiersza zwraca ustawienia domyślne.
  Future<NotificationPreferences> notificationPreferences() {
    return _guard(() async {
      final user = _db.auth.currentUser;
      if (user == null) return const NotificationPreferences();
      final row = await _db
          .from('notification_preferences')
          .select(
            'reservation_reminders, reservation_updates, review_requests, news',
          )
          .eq('user_id', user.id)
          .maybeSingle();
      return row == null
          ? const NotificationPreferences()
          : NotificationPreferences.fromJson(row);
    });
  }

  Future<void> saveNotificationPreferences(NotificationPreferences prefs) {
    return _guard(() async {
      final user = _db.auth.currentUser;
      if (user == null) {
        throw const AppFailure('Zaloguj się, żeby zmienić powiadomienia.');
      }
      await _db.from('notification_preferences').upsert({
        'user_id': user.id,
        ...prefs.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> reportBug({
    required String message,
    required String appVersion,
    required String platform,
  }) {
    return _guard(
      () => _db.from('bug_reports').insert({
        'user_id': _db.auth.currentUser?.id,
        'message': message,
        'app_version': appVersion,
        'platform': platform,
      }),
    );
  }

  Future<void> deleteAccount() {
    return _guard(() async {
      await _db.rpc<void>('delete_my_account');
      await _db.auth.signOut();
    });
  }

  // -------------------------------------------------------------
  // Błędy
  // -------------------------------------------------------------

  // -------------------------------------------------------------
  // Zamówienia z dostawą i na wynos
  // -------------------------------------------------------------

  static const _orderColumns =
      'id, restaurant_id, kind, number, fulfillment, opened_at, delivery_address, delivery_fee_grosze, '
      'payment_choice, payment_status, payment_test, promised_at, reject_reason, scheduled_for, '
      'restaurants(name, phone, address, city), order_items(name, quantity, unit_price_grosze, variant, addons, note, status)';

  /// Składa zamówienie. Ceny liczy baza z menu. Zwraca numer zamówienia.
  /// [scheduledFor]: na godzinę (odbiór albo dostawa). Null: jak najszybciej.
  Future<String> placeOrder({
    required String restaurantId,
    required OrderKind kind,
    required List<CartLine> lines,
    required PaymentChoice payment,
    required String name,
    required String phone,
    String? address,
    String? note,
    DateTime? scheduledFor,
  }) {
    return _guard(() async {
      final json = await _db.rpc<Map<String, dynamic>>('guest_place_order', params: {
        'p_restaurant_id': restaurantId,
        'p_kind': kind.db,
        'p_items': [for (final l in lines) l.toJson()],
        'p_payment': payment.db,
        'p_name': name,
        'p_phone': phone,
        'p_address': address,
        'p_note': note,
        'p_scheduled_for': scheduledFor?.toUtc().toIso8601String(),
      });
      return json['id'] as String;
    });
  }

  /// Tryb testowy płatności kartą: zamówienie jest opłacone bez pobierania pieniędzy.
  /// Zapis na listę oczekujących: dzień, liczba osób i przedział godzin.
  Future<void> joinWaitlist({
    required String restaurantId,
    required DateTime day,
    required int partySize,
    required String from,
    required String to,
    String? note,
  }) {
    final date = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return _guard(
      () => _db.rpc<String>('guest_join_waitlist', params: {
        'p_restaurant_id': restaurantId,
        'p_day': date,
        'p_party_size': partySize,
        'p_from': from == '24:00' ? '23:59' : from,
        'p_to': to == '24:00' ? '23:59' : to,
        'p_note': note,
      }),
    );
  }

  Future<void> leaveWaitlist(String id) {
    return _guard(() => _db.rpc<void>('guest_leave_waitlist', params: {'p_id': id}));
  }

  Future<List<GuestWaitlist>> myWaitlist() {
    return _guard(() async {
      final rows = await _db.rpc<List<dynamic>>('guest_my_waitlist');
      return [for (final r in rows) GuestWaitlist.fromJson(r as Map<String, dynamic>)];
    });
  }

  /// Pozycja dostawcy i lokalu, gdy zamówienie jest w drodze. Null: nie w drodze.
  Future<Map<String, dynamic>?> courierPosition(String orderId) {
    return _guard(() => _db.rpc<Map<String, dynamic>?>('guest_courier_position', params: {'p_order_id': orderId}));
  }

  /// Testowa płatność zadatku za rezerwację (bez operatora nic nie jest pobierane).
  Future<void> payDepositTest(String reservationId) {
    return _guard(() => _db.rpc<void>('guest_pay_deposit_test', params: {'p_reservation_id': reservationId}));
  }

  Future<void> payOrderTest(String orderId) {
    return _guard(() => _db.rpc<void>('guest_pay_order_test', params: {'p_order_id': orderId}));
  }

  Future<void> cancelOrder(String orderId) {
    return _guard(() => _db.rpc<void>('guest_cancel_order', params: {'p_order_id': orderId}));
  }

  Future<List<GuestOrder>> myOrders() {
    return _guard(() async {
      final user = _db.auth.currentUser;
      if (user == null) return const [];
      final rows = await _db
          .from('orders')
          .select(_orderColumns)
          .eq('guest_id', user.id)
          .order('opened_at', ascending: false)
          .limit(50);
      return rows.map(GuestOrder.fromJson).toList();
    });
  }

  Future<GuestOrder?> order(String orderId) {
    return _guard(() async {
      final row = await _db.from('orders').select(_orderColumns).eq('id', orderId).maybeSingle();
      return row == null ? null : GuestOrder.fromJson(row);
    });
  }

  /// Zmiany zamówienia na żywo: lokal przyjął, gotowe, dostawca w drodze.
  void Function() watchOrder(String orderId, void Function() onChange) {
    final channel = _db
        .channel('zamowienie-$orderId-${_orderChannels++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: orderId),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => _db.removeChannel(channel);
  }

  static int _orderChannels = 0;

  Future<bool> paymentsTestMode() {
    return _guard(() async => await _db.rpc<bool>('payments_test_mode'));
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AppFailure(_authMessage(e));
    } on PostgrestException catch (e) {
      // Komunikaty z funkcji w bazie są już po polsku i przeznaczone dla gościa.
      if (e.code == 'P0001' && e.message.isNotEmpty) {
        throw AppFailure(e.message);
      }
      throw const AppFailure('Nie udało się pobrać danych. Spróbuj ponownie.');
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
      return 'Nieprawidłowy numer lub hasło.';
    }
    if (code == 'otp_expired' ||
        message.contains('token has expired') ||
        message.contains('invalid')) {
      return 'Kod jest nieprawidłowy albo wygasł. Wyślij nowy kod.';
    }
    if (code == 'weak_password' || message.contains('password should')) {
      return 'Hasło musi mieć co najmniej 8 znaków.';
    }
    if (code.contains('rate_limit') ||
        message.contains('rate limit') ||
        e.statusCode == '429') {
      return 'Za dużo prób. Odczekaj minutę i spróbuj ponownie.';
    }
    if (code == 'user_already_exists' ||
        code == 'phone_exists' ||
        message.contains('already registered')) {
      return 'Nie udało się założyć konta. Jeśli masz już konto, zaloguj się.';
    }
    if (code == 'otp_disabled' ||
        code == 'user_not_found' ||
        message.contains('signups not allowed')) {
      return 'Nie udało się wysłać kodu. Jeśli nie masz konta, zarejestruj się.';
    }
    if (code == 'phone_provider_disabled' || code == 'sms_send_failed') {
      return 'Nie udało się wysłać SMS-a. Spróbuj za chwilę.';
    }
    return 'Nie udało się zalogować. Spróbuj ponownie.';
  }
}
