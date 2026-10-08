import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'orders_data.dart';

int _toInt(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

/// Stan kursu: przyjęte przez lokal (kuchnia przygotowuje), gotowe do odbioru, w drodze.
enum CourseStage {
  preparing('W PRZYGOTOWANIU'),
  ready('GOTOWE DO ODBIORU'),
  onTheWay('W DRODZE');

  const CourseStage(this.label);
  final String label;

  static CourseStage from(Object? value) => switch (value) {
    'ready' => CourseStage.ready,
    'on_the_way' => CourseStage.onTheWay,
    _ => CourseStage.preparing,
  };
}

class CourseItem {
  const CourseItem({
    required this.name,
    required this.quantity,
    this.variant,
    this.addons = const [],
    this.note,
    this.changes = const [],
  });

  final String name;
  final int quantity;
  final String? variant;
  final List<String> addons;
  final String? note;

  /// Zmiany składników, np. „bez: cebula”.
  final List<String> changes;

  String? get details {
    final parts = [?variant, for (final a in addons) '+ ${a.toLowerCase()}', ...changes];
    return parts.isEmpty ? null : parts.join(', ');
  }

  factory CourseItem.fromJson(Map<String, dynamic> j) => CourseItem(
    name: j['name'] as String,
    quantity: _toInt(j['quantity']),
    variant: j['variant'] as String?,
    addons: [for (final a in j['addons'] as List? ?? const []) a.toString()],
    note: j['note'] as String?,
    changes: [
      for (final c in j['changes'] as List? ?? const [])
        if (c is Map && c['name'] is String)
          '${c['kind'] == 'extra' ? 'więcej' : 'bez'}: ${(c['name'] as String).toLowerCase()}',
    ],
  );
}

/// Kurs dostawcy: zamówienie z dostawą przydzielone mnie.
class Course {
  const Course({
    required this.id,
    required this.number,
    required this.stage,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.cash,
    required this.paid,
    required this.totalGrosze,
    required this.items,
    this.note,
    this.testPayment = false,
    this.promisedAt,
    this.courseId,
    this.company,
    this.staffNote,
    this.prepaid = false,
  });

  final String id;
  final int number;
  final CourseStage stage;

  /// Nazwa lokalu albo firmy klienta (zamówienie przyjęte w panelu).
  final String? company;

  /// Komentarz tylko dla pracowników (gość go nie widzi).
  final String? staffNote;

  /// Opłacone wcześniej (zamówienie przyjęte w panelu): nic nie pobierasz.
  final bool prepaid;

  /// Kilka dostaw połączonych w panelu w jeden kurs ma ten sam numer kursu.
  final String? courseId;
  final String customerName;
  final String customerPhone;
  final String address;
  final String? note;

  /// Gość płaci gotówką przy drzwiach.
  final bool cash;

  /// Opłacone z góry kartą online.
  final bool paid;
  final bool testPayment;
  final int totalGrosze;
  final DateTime? promisedAt;
  final List<CourseItem> items;

  /// Kurs można oddać, dopóki zamówienie jest w lokalu.
  bool get canHandOver => stage != CourseStage.onTheWay;

  /// Adres do nawigacji: Google Maps otwiera trasę samochodem.
  Uri get navigationUri => Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': address,
    'travelmode': 'driving',
  });

  Uri get phoneUri => Uri(scheme: 'tel', path: customerPhone.replaceAll(' ', ''));

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    id: j['id'] as String,
    number: _toInt(j['number']),
    stage: CourseStage.from(j['fulfillment']),
    customerName: j['customer_name'] as String? ?? '',
    customerPhone: j['customer_phone'] as String? ?? '',
    address: j['delivery_address'] as String? ?? '',
    note: j['delivery_note'] as String?,
    cash: j['payment_choice'] == 'cash',
    paid: j['payment_status'] == 'paid',
    testPayment: j['payment_test'] == true,
    totalGrosze: _toInt(j['total_grosze']),
    promisedAt: _date(j['promised_at']),
    courseId: j['course_id'] as String?,
    company: (j['customer_company'] as String?)?.trim().isEmpty ?? true ? null : j['customer_company'] as String,
    staffNote: (j['staff_note'] as String?)?.trim().isEmpty ?? true ? null : j['staff_note'] as String,
    prepaid: j['payment_choice'] == 'prepaid',
    items: [for (final i in j['items'] as List? ?? const []) CourseItem.fromJson(i as Map<String, dynamic>)],
  );
}

/// Dostawca na zmianie w kolejce lokalu.
class QueuedCourier {
  const QueuedCourier({required this.memberId, required this.name, required this.busy});

  final String memberId;
  final String name;
  final bool busy;

  factory QueuedCourier.fromJson(Map<String, dynamic> j) =>
      QueuedCourier(memberId: j['member_id'] as String, name: j['name'] as String, busy: j['busy'] == true);
}

/// Wszystko dla zakładki „Dostawy”.
class DeliveryBoard {
  const DeliveryBoard({
    required this.restaurantName,
    required this.restaurantAddress,
    required this.onShift,
    required this.isCourier,
    required this.queue,
    required this.waiting,
    required this.courses,
    required this.todayCount,
    required this.todayCashGrosze,
  });

  final String restaurantName;
  final String restaurantAddress;
  final bool onShift;
  final bool isCourier;

  /// Dostawcy na zmianie: najpierw wolni, od najdłużej czekającego.
  final List<QueuedCourier> queue;

  /// Zamówienia czekające na wolnego dostawcę.
  final int waiting;
  final List<Course> courses;
  final int todayCount;
  final int todayCashGrosze;

  /// Moje miejsce w kolejce wolnych (1 = dostanę następny kurs). Null: jestem zajęty albo poza kolejką.
  int? positionOf(String memberId) {
    final free = queue.where((q) => !q.busy).toList();
    final i = free.indexWhere((q) => q.memberId == memberId);
    return i < 0 ? null : i + 1;
  }

  factory DeliveryBoard.fromJson(Map<String, dynamic> j) => DeliveryBoard(
    restaurantName: j['restaurant_name'] as String? ?? '',
    restaurantAddress: j['restaurant_address'] as String? ?? '',
    onShift: j['on_shift'] == true,
    isCourier: j['is_courier'] == true,
    queue: [for (final q in j['queue'] as List? ?? const []) QueuedCourier.fromJson(q as Map<String, dynamic>)],
    waiting: _toInt(j['waiting']),
    courses: [for (final c in j['courses'] as List? ?? const []) Course.fromJson(c as Map<String, dynamic>)],
    todayCount: _toInt(j['today_count']),
    todayCashGrosze: _toInt(j['today_cash_grosze']),
  );
}

class DeliveriesRepository {
  DeliveriesRepository(this._db);

  final SupabaseClient _db;
  static int _seq = 0;

  Future<DeliveryBoard> board(String memberId) => _guard(() async {
    final json = await _db.rpc<Map<String, dynamic>>('staff_deliveries', params: {'p_member_id': memberId});
    return DeliveryBoard.fromJson(json);
  });

  Future<void> pickUp(String orderId, String memberId) =>
      _guard(() => _db.rpc<void>('staff_delivery_pickup', params: {'p_order_id': orderId, 'p_member_id': memberId}));

  Future<void> delivered(String orderId, String memberId) =>
      _guard(() => _db.rpc<void>('staff_delivery_done', params: {'p_order_id': orderId, 'p_member_id': memberId}));

  /// Oddaje kurs osobie [toMemberId] albo następnemu wolnemu (null). Zwraca imię nowego dostawcy.
  Future<String> handOver(String orderId, String memberId, {String? toMemberId}) => _guard(
    () => _db.rpc<String>('staff_delivery_handover', params: {
      'p_order_id': orderId,
      'p_member_id': memberId,
      'p_to_member': toMemberId,
    }),
  );

  /// Zmiany zmian w lokalu (ktoś zaczął albo skończył): kolejka się przesuwa.
  void Function() watchShifts(String restaurantId, void Function() onChange) {
    final channel = _db
        .channel('dostawcy-$restaurantId-${_seq++}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'staff_shifts',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'restaurant_id', value: restaurantId),
          callback: (_) => onChange(),
        )
        .subscribe();
    return () => unawaited(_db.removeChannel(channel));
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code == 'P0001' && e.message.isNotEmpty) throw AppFailure(e.message);
      throw const AppFailure('Nie udało się pobrać kursów. Spróbuj ponownie.');
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure('Brak połączenia z serwerem. Sprawdź internet.');
    }
  }
}

final deliveriesRepositoryProvider = Provider<DeliveriesRepository>(
  (ref) => DeliveriesRepository(Supabase.instance.client),
);

/// Zmiany zmian w lokalu na żywo.
class ShiftsLive extends Notifier<int> {
  ShiftsLive(this.restaurantId);

  final String restaurantId;

  @override
  int build() {
    final stop = ref.watch(deliveriesRepositoryProvider).watchShifts(restaurantId, () => state++);
    // Zapas: kolejka odświeża się też co pół minuty, gdyby zdarzenie z bazy nie dotarło.
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => state++);
    ref.onDispose(() {
      stop();
      timer.cancel();
    });
    return 0;
  }
}

final shiftsLiveProvider = NotifierProvider.autoDispose.family<ShiftsLive, int, String>(ShiftsLive.new);

/// Tablica dostawcy: kursy, kolejka, dzisiejsze podsumowanie. Odświeża się przy każdej zmianie zamówień i zmian.
typedef CourierKey = ({String memberId, String restaurantId});

final deliveryBoardProvider = FutureProvider.autoDispose.family<DeliveryBoard, CourierKey>((ref, key) {
  ref
    ..watch(ordersLiveProvider(key.restaurantId))
    ..watch(shiftsLiveProvider(key.restaurantId));
  if (ref.watch(sessionProvider) == null) {
    return Future.error(const AppFailure('Zaloguj się ponownie.'));
  }
  return ref.watch(deliveriesRepositoryProvider).board(key.memberId);
});

/// Kursy po kolei, z dostawami jednego kursu obok siebie, i dla każdej inne dostawy z jej kursu.
List<(Course, List<Course>)> groupCourses(List<Course> courses) {
  final byCourse = <String, List<Course>>{};
  for (final c in courses) {
    if (c.courseId != null) byCourse.putIfAbsent(c.courseId!, () => []).add(c);
  }
  final seen = <String>{};
  final ordered = <Course>[];
  for (final c in courses) {
    if (seen.contains(c.id)) continue;
    final group = c.courseId == null ? [c] : byCourse[c.courseId]!;
    for (final g in group) {
      seen.add(g.id);
      ordered.add(g);
    }
  }
  return [
    for (final c in ordered)
      (c, [for (final m in c.courseId == null ? const <Course>[] : byCourse[c.courseId]!) if (m.id != c.id) m]),
  ];
}
