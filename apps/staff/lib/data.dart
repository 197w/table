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
    this.schedulePeriod = 'week',
    this.permissions = const {},
    this.courierTracking = false,
    this.isCourier = false,
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

  /// Okres grafiku ustawiony przez lokal w „Dane lokalu”: week, two_weeks albo month.
  final String schedulePeriod;

  bool get working => shiftStartedAt != null;

  /// Lokal wymaga lokalizacji dostawców przez całą zmianę (ustawia „Ustawienia lokalu” w panelu).
  final bool courierTracking;

  /// Stanowisko rozwozi zamówienia (Dostawca), więc dostaje kursy z kolejki.
  final bool isCourier;

  /// Ta zmiana wymaga udostępniania lokalizacji: dostawca w pracy w lokalu z wymogiem.
  bool get sharesLocation => working && isCourier && courierTracking;

  factory Job.fromJson(Map<String, dynamic> j) => Job(
    memberId: j['member_id'] as String,
    restaurantId: j['restaurant_id'] as String,
    restaurantName: j['restaurant_name'] as String,
    memberName: j['member_name'] as String,
    position: j['position_name'] as String?,
    permissions: {for (final p in j['permissions'] as List? ?? const []) p.toString()},
    shiftStartedAt: _date(j['shift_started_at']),
    weekSeconds: _toInt(j['week_seconds']),
    schedulePeriod: j['schedule_period'] as String? ?? 'week',
    courierTracking: j['courier_tracking'] == true,
    isCourier: j['is_courier'] == true,
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
    this.endedNow = false,
    this.endedAt,
  });

  final String restaurant;
  final String member;
  final bool startedNow;

  /// Skan zalogował mnie też w panelu na komputerze (nikt inny nie użył tego kodu).
  final bool openedPanel;

  /// Początek zmiany: trwającej albo (przy [endedNow]) właśnie zakończonej.
  final DateTime? startedAt;

  /// Kod z ekranu „Zakończ zmianę” w panelu: skan zakończył moją zmianę.
  final bool endedNow;
  final DateTime? endedAt;
}

/// Informacja od kierownika dla mnie (panel → Pracownicy → Informacje dla pracowników).
class StaffAnnouncement {
  const StaffAnnouncement({
    required this.id,
    required this.memberId,
    required this.restaurantName,
    required this.title,
    required this.body,
    required this.publishAt,
    this.authorName,
    this.read = false,
  });

  final String id;

  /// Ja w lokalu, z którego jest informacja (do oznaczenia jako przeczytanej).
  final String memberId;
  final String restaurantName;
  final String title;
  final String body;
  final DateTime publishAt;
  final String? authorName;
  final bool read;

  factory StaffAnnouncement.fromJson(Map<String, dynamic> json, Job job) => StaffAnnouncement(
    id: json['id'] as String,
    memberId: job.memberId,
    restaurantName: job.restaurantName,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    publishAt: _date(json['publish_at']) ?? DateTime.now(),
    authorName: json['author_name'] as String?,
    read: json['read'] == true,
  );
}

/// Moje godziny w grafiku. Zgłaszam, od której do której mogę pracować, przełożony przyjmuje
/// (czasem ze zmienionymi godzinami), odrzuca albo daje wolne. Po decyzji nie mogę już zmienić tego dnia.
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
    this.positionName,
  });

  final String id;
  final String memberId;
  final String restaurantName;
  final DateTime day;

  /// Stanowisko na ten dzień (gdy pracownik ma kilka).
  final String? positionName;

  /// Godziny jako „HH:MM”: zgłoszone albo (po przyjęciu) zatwierdzone. Puste przy wolnym dniu.
  final String starts;
  final String ends;

  /// pending: czeka na przełożonego, accepted: przyjęte, rejected: odrzucone, off: wolne,
  /// proposed: propozycja przełożonego (przyjmuję albo nie mogę), unavailable: nie mogę pracować.
  final String status;

  /// Co zgłosiłem. Null: godziny wpisał przełożony.
  final String? requestedStarts;
  final String? requestedEnds;
  final String? note;
  final String? answer;

  bool get pending => status == 'pending';
  bool get accepted => status == 'accepted';
  bool get rejected => status == 'rejected';
  bool get off => status == 'off';
  bool get proposed => status == 'proposed';
  bool get unavailable => status == 'unavailable';

  /// Przyjęte, ale z innymi godzinami, niż zgłosiłem.
  bool get changed => accepted && requestedStarts != null && (requestedStarts != starts || requestedEnds != ends);

  static String? _hm(Object? v) => v == null ? null : (v as String).substring(0, 5);

  factory PlannedShift.fromJson(Map<String, dynamic> j) => PlannedShift(
    id: j['id'] as String,
    memberId: j['member_id'] as String,
    restaurantName: j['restaurant_name'] as String,
    day: DateTime.parse(j['day'] as String),
    starts: _hm(j['starts']) ?? '',
    ends: _hm(j['ends']) ?? '',
    status: j['status'] as String,
    requestedStarts: _hm(j['requested_starts']),
    requestedEnds: _hm(j['requested_ends']),
    note: j['note'] as String?,
    answer: j['answer'] as String?,
    positionName: j['position_name'] as String?,
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
      startedAt: _date(j['shift_started_at'] ?? j['ended_shift_started_at']),
      endedNow: j['ended_now'] == true,
      endedAt: _date(j['ended_at']),
    );
  });

  /// Mój grafik w podanym okresie (najwyżej ok. 3 miesiące).
  Future<List<PlannedShift>> schedule({required DateTime from, required DateTime to}) => _guard(() async {
    final rows = await _db.rpc<List<dynamic>>('staff_my_schedule', params: {
      'p_from': _isoDay(from),
      'p_to': _isoDay(to),
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

  /// Nie mogę pracować w tym dniu.
  Future<void> markUnavailable({required String memberId, required DateTime day, String? note}) => _guard(
    () => _db.rpc<void>('staff_mark_unavailable', params: {
      'p_member_id': memberId,
      'p_day': _isoDay(day),
      'p_note': note,
    }),
  );

  /// Odpowiedź na propozycję przełożonego: przyjmuję albo nie mogę.
  Future<void> answerProposal(String id, {required bool accept, String? note}) => _guard(
    () => _db.rpc<void>('staff_answer_proposal', params: {'p_id': id, 'p_accept': accept, 'p_note': note}),
  );

  /// Do kiedy mogę zgłaszać dyspozycyjność na okres z dniem [day]. Null: lokal nie ustawił terminu.
  Future<DateTime?> scheduleDeadline(String memberId, DateTime day) => _guard(() async {
    final value = await _db.rpc<dynamic>('staff_schedule_deadline', params: {
      'p_member_id': memberId,
      'p_day': _isoDay(day),
    });
    return value is String ? DateTime.parse(value).toLocal() : null;
  });

  /// Moje uwagi na tygodnie od [from] do [to]: poniedziałek tygodnia → uwaga.
  Future<Map<DateTime, String>> weekNotes(DateTime from, DateTime to) => _guard(() async {
    final rows = await _db
        .from('staff_week_notes')
        .select('week_start, note')
        .gte('week_start', _isoDay(from))
        .lte('week_start', _isoDay(to));
    return {for (final r in rows) DateTime.parse(r['week_start'] as String): r['note'] as String};
  });

  Future<void> setWeekNote(String memberId, DateTime week, String note) => _guard(
    () => _db.rpc<void>('staff_set_week_note', params: {
      'p_member_id': memberId,
      'p_week': _isoDay(week),
      'p_note': note,
    }),
  );

  /// Moje czterocyfrowe kody do panelu według numeru pracownika.
  Future<Map<String, String>> codes() => _guard(() async {
    final rows = await _db.rpc<List<dynamic>>('staff_my_codes');
    return {
      for (final r in rows.cast<Map<String, dynamic>>()) r['member_id'] as String: r['code'] as String,
    };
  });

  /// Informacje od kierownika z ostatnich 60 dni we wszystkich moich lokalach, najnowsze pierwsze.
  Future<List<StaffAnnouncement>> announcements(List<Job> jobs) => _guard(() async {
    final lists = await Future.wait([
      for (final job in jobs)
        _db
            .rpc<List<dynamic>>('staff_announcements', params: {'p_member_id': job.memberId})
            .then((rows) => [for (final r in rows) StaffAnnouncement.fromJson(r as Map<String, dynamic>, job)]),
    ]);
    return [for (final l in lists) ...l]..sort((a, b) => b.publishAt.compareTo(a.publishAt));
  });

  Future<void> readAnnouncement(StaffAnnouncement a) => _guard(
    () => _db.rpc<void>('staff_read_announcement', params: {'p_member_id': a.memberId, 'p_id': a.id}),
  );

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

/// Mój grafik w okresie lokalu (tydzień, 2 tygodnie albo miesiąc), od pierwszego do ostatniego dnia.
final schedulePeriodProvider = FutureProvider.autoDispose
    .family<List<PlannedShift>, ({DateTime from, DateTime to})>((ref, period) {
      if (ref.watch(sessionProvider) == null) return Future.value(const []);
      return ref.watch(staffRepositoryProvider).schedule(from: period.from, to: period.to);
    });

/// Termin zgłaszania dyspozycyjności na okres (pierwszy dzień okresu) w moim lokalu.
final scheduleDeadlineProvider = FutureProvider.autoDispose.family<DateTime?, ({String memberId, DateTime day})>((ref, q) {
  if (ref.watch(sessionProvider) == null) return Future.value(null);
  return ref.watch(staffRepositoryProvider).scheduleDeadline(q.memberId, q.day);
});

/// Moje uwagi na tygodnie okresu grafiku.
final weekNotesProvider = FutureProvider.autoDispose.family<Map<DateTime, String>, ({DateTime from, DateTime to})>((ref, q) {
  if (ref.watch(sessionProvider) == null) return Future.value(const {});
  return ref.watch(staffRepositoryProvider).weekNotes(q.from, q.to);
});

/// Informacje od kierownika. Co 2 minuty od nowa, żeby zaplanowane pojawiały się o swojej porze.
final announcementsProvider = FutureProvider.autoDispose<List<StaffAnnouncement>>((ref) async {
  if (ref.watch(sessionProvider) == null) return const [];
  final timer = Timer(const Duration(minutes: 2), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  final jobs = await ref.watch(jobsProvider.future);
  if (jobs.isEmpty) return const [];
  return ref.watch(staffRepositoryProvider).announcements(jobs);
});

final codesProvider = FutureProvider.autoDispose<Map<String, String>>((ref) {
  if (ref.watch(sessionProvider) == null) return Future.value(const {});
  return ref.watch(staffRepositoryProvider).codes();
});

final shiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) {
  if (ref.watch(sessionProvider) == null) return Future.value(const []);
  // Ten miesiąc i trzy poprzednie, do „Moich godzin” liczonych od 1. do ostatniego dnia miesiąca.
  return ref.watch(staffRepositoryProvider).shifts(days: 125);
});
