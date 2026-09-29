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
    this.permissions = const {},
    this.position,
    this.shiftStartedAt,
  });

  final String memberId;
  final String restaurantId;
  final String restaurantName;
  final String memberName;
  final String? position;

  /// Uprawnienia stanowiska, np. „orders” odblokowuje nabijanie zamówień w aplikacji.
  final Set<String> permissions;

  bool get canTakeOrders => permissions.contains('orders');

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
    permissions: {for (final p in j['permissions'] as List? ?? const []) p.toString()},
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
  const ScanResult({
    required this.restaurant,
    required this.member,
    required this.startedNow,
    this.openedPanel = false,
    this.startedAt,
  });

  final String restaurant;
  final String member;
  final bool startedNow;

  /// Skan zalogował mnie też w panelu na komputerze (nikt inny nie użył tego kodu).
  final bool openedPanel;
  final DateTime? startedAt;
}

/// Moje godziny w grafiku. Zgłaszam, od której do której mogę pracować, przełożony przyjmuje
/// (czasem ze zmienionymi godzinami) albo odrzuca. Po decyzji nie mogę już zmienić tego dnia.
class PlannedShift {
  const PlannedShift({
    required this.id,
    required this.memberId,
    required this.restaurantName,
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
  final String restaurantName;
  final DateTime day;

  /// Godziny jako „HH:MM”: zgłoszone albo (po przyjęciu) zatwierdzone.
  final String starts;
  final String ends;

  /// pending: czeka na przełożonego, accepted: przyjęte, rejected: odrzucone.
  final String status;

  /// Co zgłosiłem. Null: godziny wpisał przełożony.
  final String? requestedStarts;
  final String? requestedEnds;
  final String? note;
  final String? answer;

  bool get pending => status == 'pending';
  bool get accepted => status == 'accepted';
  bool get rejected => status == 'rejected';

  /// Przyjęte, ale z innymi godzinami, niż zgłosiłem.
  bool get changed => accepted && requestedStarts != null && (requestedStarts != starts || requestedEnds != ends);

  static String? _hm(Object? v) => v == null ? null : (v as String).substring(0, 5);

  factory PlannedShift.fromJson(Map<String, dynamic> j) => PlannedShift(
    id: j['id'] as String,
    memberId: j['member_id'] as String,
    restaurantName: j['restaurant_name'] as String,
    day: DateTime.parse(j['day'] as String),
    starts: _hm(j['starts'])!,
    ends: _hm(j['ends'])!,
    status: j['status'] as String,
    requestedStarts: _hm(j['requested_starts']),
    requestedEnds: _hm(j['requested_ends']),
    note: j['note'] as String?,
    answer: j['answer'] as String?,
  );
}

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
      openedPanel: j['opened_panel'] == true,
      startedAt: _date(j['shift_started_at']),
    );
  });

  /// Mój grafik na najbliższe 8 tygodni.
  Future<List<PlannedShift>> schedule() => _guard(() async {
    final today = DateTime.now();
    final rows = await _db.rpc<List<dynamic>>('staff_my_schedule', params: {
      'p_from': _isoDay(today),
      'p_to': _isoDay(today.add(const Duration(days: 56))),
    });
    return [for (final r in rows) PlannedShift.fromJson(r as Map<String, dynamic>)];
  });

  /// Zgłaszam, od której do której mogę pracować w danym dniu ([starts], [ends] jako „HH:MM”).
  /// Poprawić mogę tylko zgłoszenie, o którym przełożony jeszcze nie zdecydował.
  Future<void> submitHours({
    required String memberId,
    required DateTime day,
    required String starts,
    required String ends,
    String? note,
  }) =>
      _guard(() => _db.rpc<void>('staff_submit_hours', params: {
        'p_member_id': memberId,
        'p_day': _isoDay(day),
        'p_starts': starts,
        'p_ends': ends,
        'p_note': (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      }));

  Future<void> deleteHours(String id) => _guard(() => _db.rpc<void>('staff_delete_hours', params: {'p_id': id}));

  /// Moje czterocyfrowe kody do panelu według numeru pracownika.
  Future<Map<String, String>> codes() => _guard(() async {
    final rows = await _db.rpc<List<dynamic>>('staff_my_codes');
    return {
      for (final r in rows.cast<Map<String, dynamic>>()) r['member_id'] as String: r['code'] as String,
    };
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

final scheduleProvider = FutureProvider.autoDispose<List<PlannedShift>>((ref) {
  if (ref.watch(sessionProvider) == null) return Future.value(const []);
  return ref.watch(staffRepositoryProvider).schedule();
});

final codesProvider = FutureProvider.autoDispose<Map<String, String>>((ref) {
  if (ref.watch(sessionProvider) == null) return Future.value(const {});
  return ref.watch(staffRepositoryProvider).codes();
});

final shiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) {
  if (ref.watch(sessionProvider) == null) return Future.value(const []);
  return ref.watch(staffRepositoryProvider).shifts();
});
