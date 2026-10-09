import 'package:flutter_test/flutter_test.dart';
import 'package:table_staff/deliveries_data.dart';

void main() {
  test('tablica dostawcy: kurs, kolejka i moje miejsce', () {
    final board = DeliveryBoard.fromJson({
      'restaurant_name': 'REVE',
      'restaurant_address': 'Rynek 1, Białystok',
      'on_shift': true,
      'is_courier': true,
      'queue': [
        {'member_id': 'a', 'name': 'Adam', 'busy': false},
        {'member_id': 'b', 'name': 'Bartek', 'busy': false},
        {'member_id': 'c', 'name': 'Cezary', 'busy': true},
      ],
      'waiting': 2,
      'courses': [
        {
          'id': 'o1',
          'number': 12,
          'fulfillment': 'on_the_way',
          'customer_name': 'Anna',
          'customer_phone': '600 100 200',
          'delivery_address': 'Lipowa 1/2, Białystok',
          'payment_choice': 'cash',
          'payment_status': 'unpaid',
          'total_grosze': 5200,
          'items': [
            {'name': 'Pizza', 'quantity': 2, 'variant': 'Duża', 'addons': ['Ser']},
          ],
        },
      ],
      'today_count': 3,
      'today_cash_grosze': 12000,
    });
    expect(board.positionOf('a'), 1);
    expect(board.positionOf('b'), 2);
    expect(board.positionOf('c'), isNull);
    final course = board.courses.single;
    expect(course.stage, CourseStage.onTheWay);
    expect(course.cash, isTrue);
    expect(course.canHandOver, isFalse);
    expect(course.items.single.details, 'Duża, + ser');
    expect(course.navigationUri.queryParameters['destination'], 'Lipowa 1/2, Białystok');
    expect(course.phoneUri.toString(), 'tel:600100200');
  });

  test('dostawy jednego kursu są obok siebie', () {
    Course course(String id, int number, String? courseId) => Course.fromJson({
      'id': id,
      'number': number,
      'course_id': courseId,
      'fulfillment': 'ready',
      'delivery_address': 'Lipowa $number',
      'total_grosze': 1000,
    });
    final grouped = groupCourses([course('a', 11, 'k1'), course('b', 12, null), course('c', 13, 'k1')]);
    expect([for (final (c, _) in grouped) c.number], [11, 13, 12]);
    expect([for (final m in grouped.first.$2) m.number], [13]);
    expect(grouped.last.$2, isEmpty);
  });

  test('kurs z panelu: firma, komentarz dla pracowników, opłacone i zmiany składników', () {
    final c = Course.fromJson({
      'id': 'o9',
      'number': 9,
      'fulfillment': 'ready',
      'customer_name': 'Jan Kowalski',
      'customer_company': 'Biuro ABC',
      'customer_phone': '600100200',
      'delivery_address': 'Lipowa 14/3, Białystok',
      'staff_note': 'Stały klient',
      'payment_choice': 'prepaid',
      'payment_status': 'paid',
      'total_grosze': 4400,
      'items': [
        {
          'name': 'Pizza',
          'quantity': 1,
          'addons': [],
          'changes': [
            {'name': 'Cebula', 'kind': 'without'},
            {'name': 'Ser', 'kind': 'extra'},
          ],
        },
      ],
    });
    expect(c.company, 'Biuro ABC');
    expect(c.staffNote, 'Stały klient');
    expect(c.prepaid, isTrue);
    expect(c.cash, isFalse);
    expect(c.items.single.details, 'bez: cebula, więcej: ser');
  });

  test('lokal wymaga lokalizacji: dostawca bez niej nie jest w kolejce wolnych', () {
    final board = DeliveryBoard.fromJson({
      'tracking': true,
      'located': false,
      'is_courier': true,
      'queue': [
        {'member_id': 'a', 'name': 'Adam', 'busy': false, 'located': true},
        {'member_id': 'b', 'name': 'Bartek', 'busy': false, 'located': false},
        {'member_id': 'c', 'name': 'Cezary', 'busy': false, 'located': true},
      ],
    });
    expect(board.tracking, isTrue);
    expect(board.located, isFalse);
    expect(board.positionOf('a'), 1);
    expect(board.positionOf('b'), isNull);
    expect(board.positionOf('c'), 2);
    // Starszy serwer bez pola „located”: wszyscy widoczni.
    expect(QueuedCourier.fromJson({'member_id': 'x', 'name': 'X'}).located, isTrue);
  });
}
