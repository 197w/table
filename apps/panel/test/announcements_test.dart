import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/app/app.dart';
import 'package:table_panel/app/sections.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/management/unclosed_screen.dart';
import 'package:table_panel/features/staff/announcements_screen.dart';

void main() {
  test('informacje dla pracowników: zakładka dla każdego, pisanie z uprawnieniem', () {
    expect(canOpenRoute(PanelRoutes.announcements, const {}), isTrue);
    expect(canOpenRoute(PanelRoutes.announcements, const {'orders'}), isTrue);
    expect(PanelSection.forRoute(PanelRoutes.announcements), PanelSection.staff);
    expect(StaffPermission.fromKey('announcements'), StaffPermission.announcements);
    // Niezamknięte zamówienia: Management z podsumowaniem dnia.
    expect(canOpenRoute(PanelRoutes.unclosed, const {'orders'}), isFalse);
    expect(canOpenRoute(PanelRoutes.unclosed, const {'day_close'}), isTrue);
    expect(PanelSection.forRoute(PanelRoutes.unclosed), PanelSection.management);
  });

  test('informacja z bazy: odbiorcy, zaplanowana i przeczytana', () {
    final a = Announcement.fromJson({
      'id': 'a1',
      'title': 'Sobota',
      'body': 'Otwieramy o 10.',
      'audience': 'positions',
      'position_ids': ['p1', 'p2'],
      'member_ids': [],
      'publish_at': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String(),
      'author_name': 'Wiktor',
      'read': false,
      'for_me': true,
      'recipients': 5,
      'reads': 0,
    });
    expect(a.audience, AnnouncementAudience.positions);
    expect(a.isPublished(), isFalse);
    expect(a.forMe, isTrue);
    expect(recipientsLabel(a, const {'p1': 'Kelner', 'p2': 'Kucharz'}, const {}), 'Kelner, Kucharz');

    final members = Announcement.fromJson({
      'id': 'a2',
      'title': 'Szkolenie',
      'audience': 'members',
      'member_ids': ['m1', 'm2', 'm3', 'm4', 'm5'],
      'publish_at': '2026-10-01T08:00:00Z',
    });
    expect(members.isPublished(), isTrue);
    expect(
      recipientsLabel(members, const {}, const {'m1': 'Ala', 'm2': 'Ola', 'm3': 'Jan', 'm4': 'Ewa'}),
      'Ala, Ola, Jan i 2 innych',
    );
  });

  test('niezamknięte zamówienia: etap na wynos, kto otworzył, z poprzedniego dnia', () {
    final now = DateTime(2026, 10, 10, 12);
    final old = UnclosedOrder.fromJson({
      'id': 'o1',
      'kind': 'delivery',
      'number': 3,
      'fulfillment': 'ready',
      'status': 'open',
      'opened_at': DateTime(2026, 10, 4, 18, 30).toUtc().toIso8601String(),
      'delivery_fee_grosze': 900,
      'opener': {'name': 'Kasia'},
      'order_items': [
        {
          'id': 'i1',
          'order_id': 'o1',
          'name': 'Pierogi',
          'quantity': 2,
          'unit_price_grosze': 2500,
          'status': 'ready',
          'created_at': '2026-10-04T16:30:00Z',
        },
      ],
    });
    expect(old.stage, TakeawayStage.ready);
    expect(old.openedBy, 'Kasia');
    expect(old.fromEarlierDay(now), isTrue);
    expect(old.order.billGrosze, 5900);
    expect(itemsSummary(old.order), '2 pozycje · do wydania: 2');

    final table = UnclosedOrder.fromJson({
      'id': 'o2',
      'kind': 'dine_in',
      'status': 'open',
      'opened_at': DateTime(2026, 10, 10, 11, 15).toUtc().toIso8601String(),
    });
    expect(table.stage, isNull);
    expect(table.fromEarlierDay(now), isFalse);
    expect(itemsSummary(table.order), 'bez pozycji');
    expect(openFor(const Duration(minutes: 45)), '45 min');
    expect(openFor(const Duration(hours: 3, minutes: 10)), '3 h 10 min');
    expect(openFor(const Duration(days: 6, hours: 2)), '6 dni');
  });
}
