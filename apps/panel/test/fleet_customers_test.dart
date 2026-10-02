import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/data/models.dart';

void main() {
  test('pojazd floty: rodzaj, rejestracja i dostawca', () {
    final v = Vehicle.fromJson({
      'id': 'v1',
      'kind': 'scooter',
      'name': 'Skuter 1',
      'plate': 'BI 1234A',
      'member_id': 'm1',
      'note': null,
      'active': false,
    });
    expect(v.kind, VehicleKind.scooter);
    expect(v.kind.label, 'Skuter');
    expect(v.plate, 'BI 1234A');
    expect(v.memberId, 'm1');
    expect(v.active, isFalse);
    expect(VehicleKind.from('rakieta'), VehicleKind.other);
  });

  test('klient: powracający po drugiej wizycie albo zamówieniu', () {
    Customer c(int visits, int orders) => Customer.fromJson({
      'key': 'k',
      'name': 'Anna',
      'phone': '+48 600 100 200',
      'from_app': true,
      'visits': visits,
      'reservations': visits + 1,
      'no_shows': 1,
      'cancelled': 0,
      'orders': orders,
      'spent_grosze': 12900,
      'first_seen': '2026-09-01T18:00:00Z',
      'last_visit': '2026-09-30T19:00:00Z',
      'next_reservation': null,
    });
    expect(c(1, 0).returning, isFalse);
    expect(c(1, 1).returning, isTrue);
    expect(c(2, 0).spentGrosze, 12900);
    expect(c(2, 0).nextReservation, isNull);
  });

  test('statystyki zespołu: aktywność w okresie', () {
    final idle = TeamStat.fromJson({
      'member_id': 'm1', 'name': 'Anna', 'position_name': 'Kelner', 'active': false,
      'seconds': 0, 'shifts': 0, 'orders_opened': 0, 'orders_closed': 0, 'revenue': 0, 'items': 0, 'deliveries': 0,
    });
    final busy = TeamStat.fromJson({
      'member_id': 'm2', 'name': 'Adam', 'position_name': 'Dostawca', 'active': true,
      'seconds': 7200, 'shifts': 1, 'orders_opened': 0, 'orders_closed': 0, 'revenue': 0, 'items': 0, 'deliveries': 3,
    });
    expect(idle.hasActivity, isFalse);
    expect(busy.hasActivity, isTrue);
    expect(busy.position, 'Dostawca');
    expect(busy.deliveries, 3);
  });
}
