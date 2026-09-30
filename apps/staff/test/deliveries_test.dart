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
}
