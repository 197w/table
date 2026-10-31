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

  test('PDF z kilkoma tabelami (inwentaryzacja: spis, dostawy, usunięcia)', () async {
    final bytes = await exportPdfDocument(
      title: 'Inwentaryzacja',
      restaurant: 'REVE',
      period: 'Piątek, 30 października 2026',
      notes: const ['Okres od 23.10'],
      tables: const [
        ExportTable(
          title: 'Spis',
          header: ['Składnik', 'Razem'],
          rows: [
            ['Mąka', '75 kg'],
          ],
          numeric: {1},
        ),
        ExportTable(
          title: 'Dostawy w okresie',
          header: ['Kiedy', 'Składniki'],
          rows: [
            ['Dziś, 07:00', 'Mąka: 2 worki = 50 kg'],
          ],
        ),
        ExportTable(title: 'Usunięcia i przesunięcia w okresie', header: ['Kiedy', 'Powód'], rows: []),
      ],
    );
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
  });
}
