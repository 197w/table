import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

int _toInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// Zamienia wpisany numer na format +48XXXXXXXXX. Na start tylko polskie numery.
String? normalizePolishPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 9) return '+48$digits';
  if (digits.length == 11 && digits.startsWith('48')) return '+$digits';
  return null;
}

/// Lokal, w którym pracuję: kierownik dodał mój numer w panelu (zakładka „Pracownicy”).
class Job {
  const Job({
    required this.memberId,
    required this.restaurantId,
    required this.restaurantName,
    required this.memberName,
    required this.weekSeconds,
    this.position,
    this.shiftStartedAt,
  });

  final String memberId;
  final String restaurantId;
  final String restaurantName;
  final String memberName;
  final String? position;

  /// Początek trwającej zmiany. Null: jestem poza pracą.
  final DateTime? shiftStartedAt;

  /// Przepracowane sekundy w tym tygodniu (z trwającą zmianą).
  final int weekSeconds;

  bool get working => shiftStartedAt != null;

  factory Job.fromJson(Map<String, dynamic> j) => Job(
    memberId: j['member_id'] as String,
    restaurantId: j['restaurant_id'] as String,
    restaurantName: j['restaurant_name'] as String,
    memberName: j['member_name'] as String,
    position: j['position_name'] as String?,
    shiftStartedAt: _date(j['shift_started_at']),
    weekSeconds: _toInt(j['week_seconds']),
  );
}

/// Moja zmiana z historii godzin.
class Shift {
  const Shift({required this.id, required this.restaurantName, required this.startedAt, this.endedAt});

  final String id;
  final String restaurantName;
  final DateTime startedAt;
  final DateTime? endedAt;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
    id: j['id'] as String,
    restaurantName: j['restaurant_name'] as String,
    startedAt: _date(j['started_at'])!,
    endedAt: _date(j['ended_at']),
  );
}

/// Wynik skanu kodu z panelu.
class ScanResult {
  const ScanResult({required this.restaurant, required this.member, required this.startedNow, this.startedAt});

  final String restaurant;
  final String member;
  final bool startedNow;
  final DateTime? startedAt;
}

/// Jedyne miejsce aplikacji, które rozmawia z Supabase. Błędy zamienia na polskie komunikaty.
class StaffRepository {
  StaffRepository(this._db);

  final SupabaseClient _db;

  Session? get session => _db.auth.currentSession;
  String? get phone => _db.auth.currentUser?.phone;

  /// Kod SMS do logowania. Nowy numer dostaje konto przy pierwszym logowaniu.
  Future<void> sendCode(String phone) =>
      _guard(() => _db.auth.signInWithOtp(phone: phone, shouldCreateUser: true));

  Future<void> verifyCode(String phone, String code) =>
      _guard(() => _db.auth.verifyOTP(type: OtpType.sms, phone: phone, token: code));

  Future<void> signOut() => _guard(() => _db.auth.signOut());

  Future<List<Job>> jobs() => _guard(() async {
    final rows = await _db.rpc<List<dynamic>>('staff_my_jobs');
    return [for (final r in rows) Job.fromJson(r as Map<String, dynamic>)];
  });

  Future<List<Shift>> shifts({int days = 31}) => _guard(() async {
    final rows = await _db.rpc<List<dynamic>>('staff_my_shifts', params: {'p_days': days});
    return [for (final r in rows) Shift.fromJson(r as Map<String, dynamic>)];
  });

  Future<ScanResult> scan(String code) => _guard(() async {
    final j = await _db.rpc<Map<String, dynamic>>('staff_scan', params: {'p_token': code});
    return ScanResult(
      restaurant: j['restaurant'] as String,
      member: j['member'] as String,
      startedNow: j['started_now'] == true,
      startedAt: _date(j['shift_started_at']),
    );
  });

  Future<void> endShift(String memberId) =>
      _guard(() => _db.rpc<void>('staff_end_shift', params: {'p_member_id': memberId}));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFailure {
      rethrow;
    } on AuthException catch (e) {
      final code = e.code ?? '';
      if (code.contains('otp_expired') || e.message.toLowerCase().contains('expired')) {
        throw const AppFailure('Kod jest nieprawidłowy albo wygasł. Poproś o nowy.');
      }
      if (code.contains('rate_limit') || e.statusCode == '429') {
        throw const AppFailure('Za dużo prób. Odczekaj minutę i spróbuj ponownie.');
      }
      throw const AppFailure('Nie udało się zalogować. Spróbuj ponownie.');
    } on PostgrestException catch (e) {
      // Komunikaty z funkcji w bazie są już po polsku.
      if (e.code == 'P0001' && e.message.isNotEmpty) throw AppFailure(e.message);
      throw const AppFailure('Nie udało się pobrać danych. Spróbuj ponownie.');
    } catch (_) {
      throw const AppFailure('Brak połączenia z serwerem. Sprawdź internet.');
    }
  }
}

final staffRepositoryProvider = Provider<StaffRepository>((ref) => StaffRepository(Supabase.instance.client));

/// Bieżąca sesja: zmiana logowania przebudowuje aplikację.
class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() {
    final auth = Supabase.instance.client.auth;
    final sub = auth.onAuthStateChange.listen((e) => state = e.session ?? auth.currentSession);
    ref.onDispose(sub.cancel);
    return auth.currentSession;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

final jobsProvider = FutureProvider.autoDispose<List<Job>>((ref) {
  if (ref.watch(sessionProvider) == null) return Future.value(const []);
  return ref.watch(staffRepositoryProvider).jobs();
});

final shiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) {
  if (ref.watch(sessionProvider) == null) return Future.value(const []);
  return ref.watch(staffRepositoryProvider).shifts();
});
