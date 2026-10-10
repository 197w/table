import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:table_panel/features/management/export_csv.dart';
import 'package:table_panel/features/management/export_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('eksport PDF: plik PDF z polskimi znakami, także wiele stron i pusta tabela', () async {
    final table = ExportTable(
      title: 'Czas pracy i wynagrodzenia',
      header: const ['Pracownik', 'Stanowisko', 'Godziny', 'Zarobek brutto'],
      rows: [
        for (var i = 0; i < 120; i++) ['Łukasz Żółć $i', 'Kelner', '12,50', '375,00'],
      ],
      footer: const ['Razem', '', '1500,00', '45000,00'],
      numeric: const {2, 3},
    );
    final bytes = await exportPdf(table, restaurant: 'Pierogarnia Na Mostku', period: 'październik 2026');
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(2000));

    final empty = await exportPdf(
      const ExportTable(title: 'Petty cash', header: ['Data', 'Kwota'], rows: []),
      restaurant: 'REVE',
      period: 'wrzesień 2026',
    );
    expect(ascii.decode(empty.sublist(0, 5)), '%PDF-');
  });
}
