import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/shared/notes_view.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pl_PL'));

  test('brutto → netto według umowy', () {
    // Zlecenie: 13,71% składek, 9% zdrowotnej, PIT 12% po kosztach 20%.
    expect(Payroll.hourlyNet(Contract.zlecenie, 3000), 2107);
    // Student do 26 lat: netto = brutto.
    expect(Payroll.hourlyNet(Contract.student, 3000), 3000);
    // Umowa o pracę liczona dla pełnego etatu: 5040 zł brutto → 3765,60 zł netto.
    expect(Payroll.monthlyNet(Contract.praca, 504000), 376560);
    expect(Payroll.hourlyNet(Contract.praca, 3000), 2241);
    expect(Payroll.monthlyNet(Contract.zlecenie, 0), 0);
    expect(const StaffRate(grossGrosze: 3000, contract: Contract.zlecenie).netGrosze, 2107);
  });

  test('netto → brutto: najmniejsze brutto, które daje wpisane netto', () {
    for (final contract in Contract.values) {
      for (final net in [1500, 2107, 2500, 3333]) {
        final gross = Payroll.hourlyGross(contract, net);
        expect(Payroll.hourlyNet(contract, gross), greaterThanOrEqualTo(net), reason: '$contract $net');
        expect(Payroll.hourlyNet(contract, gross - 1), lessThan(net), reason: '$contract $net');
      }
    }
    expect(Payroll.hourlyGross(Contract.zlecenie, 2107), 3000);
    expect(Payroll.hourlyGross(Contract.student, 2500), 2500);
    expect(Payroll.hourlyGross(Contract.praca, 0), 0);
  });

  test('rodzaj umowy z bazy, nieznany to zlecenie', () {
    expect(Contract.from('praca'), Contract.praca);
    expect(Contract.from('zlecenie_student'), Contract.student);
    expect(Contract.from(null), Contract.zlecenie);
    final team = TeamStat.fromJson({
      'member_id': 'm1', 'name': 'Anna', 'seconds': 0, 'shifts': 0, 'orders_opened': 0, 'orders_closed': 0,
      'revenue': 0, 'items': 0, 'deliveries': 0, 'contract': 'praca',
    });
    expect(team.contract, Contract.praca);
    expect(MemberStats.fromJson({'seconds': 0, 'contract': 'zlecenie_student'}).contract, Contract.student);
  });

  test('notatki klienta i pojazdu oraz historia klienta', () {
    final vehicleNote = Note.fromJson({
      'id': 'n1',
      'vehicle_id': 'v1',
      'body': 'Przegląd w marcu',
      'author_name': 'Anna Nowak',
      'created_at': '2026-10-02T10:00:00Z',
    });
    expect(vehicleNote.parentId, 'v1');
    expect(vehicleNote.author, 'Anna Nowak');
    final customerNote = Note.fromJson({
      'id': 'n2',
      'customer_key': 'p:500600700',
      'body': 'Alergia na orzechy',
      'author_name': null,
      'created_at': '2026-10-02T10:00:00Z',
    });
    expect(customerNote.parentId, 'p:500600700');
    expect(customerNote.author, isNull);

    final visit = CustomerEvent.fromJson({
      'at': '2026-09-30T18:00:00Z',
      'kind': 'reservation',
      'status': 'no_show',
      'party_size': 4,
      'spent_grosze': 0,
    });
    expect(visit.partySize, 4);
    expect(ReservationStatus.fromDb(visit.status), ReservationStatus.noShow);
    final delivery = CustomerEvent.fromJson({'at': '2026-09-29T12:00:00Z', 'kind': 'delivery', 'spent_grosze': 6400});
    expect(delivery.partySize, isNull);
    expect(delivery.spentGrosze, 6400);
  });

  testWidgets('notatka: Enter dodaje i czyści pole, Shift+Enter nie dodaje', (tester) async {
    final added = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 500,
            child: NotesView(
              notes: AsyncData([
                Note(id: 'n1', body: 'Stara notatka', author: 'Anna', createdAt: DateTime(2026, 10, 1, 12)),
              ]),
              onAdd: (body) async => added.add(body),
              onDelete: (_) async {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Stara notatka'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Lubi stolik przy oknie');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(added, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(added, ['Lubi stolik przy oknie']);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
  });
}
