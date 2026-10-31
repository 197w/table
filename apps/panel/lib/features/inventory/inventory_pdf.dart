import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/platform.dart';
import '../../data/models.dart';
import '../management/export_csv.dart';
import '../management/export_pdf.dart';
import 'inventory_docs.dart';

String _qty(double? v, InventoryUnit unit) => v == null ? '—' : '${inventoryNumber(v)} ${unit.label}';

String _signed(double? v, InventoryUnit unit) {
  if (v == null) return '—';
  if (v.abs() < 0.0005) return '0 ${unit.label}';
  return '${v > 0 ? '+' : '−'}${inventoryNumber(v.abs())} ${unit.label}';
}

/// Spis: lokalizacja, składnik, policzono (z opakowaniami i pojemnikiem), poprzednio, ruchy, „powinno być”, różnica.
ExportTable inventoryCountTable(InventoryCount count) => ExportTable(
  title: 'Spis',
  header: const [
    'Lokalizacja',
    'Składnik',
    'Policzono',
    'Razem',
    'Poprzednio',
    'Sprzedaż',
    'Dostawy',
    'Usunięte',
    'Powinno być',
    'Różnica',
  ],
  numeric: const {3, 4, 5, 6, 7, 8, 9},
  rows: [
    for (final l in count.lines)
      [
        l.location ?? '',
        l.name,
        [
          if ((l.packages ?? 0) > 0) packCount(l.packages!, l.packName),
          if (l.container != null && l.gross != null)
            '${inventoryGrouped(l.gross!)} g w poj. ${l.container} (−${inventoryGrouped(l.tare ?? 0)} g)'
          else if ((l.loose ?? 0) > 0)
            '${inventoryGrouped(l.loose!)} ${l.unit.portion.label}',
        ].join(' + '),
        _qty(l.total, l.unit),
        _qty(l.previous, l.unit),
        l.used == null ? '—' : _signed(-l.used!, l.unit),
        l.delivered == null ? '—' : _signed(l.delivered, l.unit),
        l.removed == null ? '—' : _signed(-l.removed!, l.unit),
        _qty(l.expected, l.unit),
        _signed(l.difference, l.unit),
      ],
  ],
);

ExportTable _docsTable(List<InventoryDoc> docs, {required bool delivery}) => ExportTable(
  title: delivery ? 'Dostawy w okresie' : 'Usunięcia i przesunięcia w okresie',
  header: delivery
      ? const ['Kiedy', 'Dostawca', 'Dokument', 'Składniki', 'Wpisał(a)']
      : const ['Kiedy', 'Powód', 'Wyjaśnienie', 'Składniki', 'Wpisał(a)'],
  rows: [
    for (final d in docs)
      if (d.delivery == delivery)
        [
          docWhen(d.happenedAt),
          delivery ? d.supplier ?? '' : d.reason?.label ?? '',
          delivery ? d.documentNo ?? '' : d.note ?? '',
          [for (final l in d.lines) '${l.name}: ${l.text}'].join('\n'),
          d.createdBy ?? '',
        ],
  ],
);

/// PDF podsumowania inwentaryzacji: spis z różnicami oraz dostawy i usunięcia z okresu (z powodami).
Future<void> saveInventoryPdf(BuildContext context, InventoryCount count, {required String restaurant}) async {
  if (!panelOnDesktop) {
    showMessage(context, 'PDF zapisuje panel na komputerze.', tone: ToastTone.warning);
    return;
  }
  final finished = count.finishedAt ?? DateTime.now();
  final day =
      '${finished.year}-${finished.month.toString().padLeft(2, '0')}-${finished.day.toString().padLeft(2, '0')}';
  final location = await getSaveLocation(
    suggestedName: 'inwentaryzacja-$day.pdf',
    acceptedTypeGroups: const [
      XTypeGroup(label: 'PDF', extensions: ['pdf']),
    ],
  );
  if (location == null) return;
  try {
    final path = location.path.toLowerCase().endsWith('.pdf') ? location.path : '${location.path}.pdf';
    final bytes = await exportPdfDocument(
      title: 'Inwentaryzacja',
      restaurant: restaurant,
      period: Fmt.capitalize(Fmt.dayLong(finished)),
      notes: [
        [
          if (count.periodFrom != null) 'Okres od ${docWhen(count.periodFrom!)}',
          'spis ${docWhen(count.startedAt)} – ${count.finishedAt == null ? 'trwa' : docWhen(count.finishedAt!)}',
          if (count.finishedBy != null) 'zakończył(a) ${count.finishedBy}',
        ].join(' · '),
        'Powinno być: poprzednia inwentaryzacja minus sprzedaż (receptury dań), plus dostawy, minus usunięcia. '
            'Różnica na minusie to braki.',
      ],
      tables: [
        inventoryCountTable(count),
        _docsTable(count.docs, delivery: true),
        _docsTable(count.docs, delivery: false),
      ],
    );
    await File(path).writeAsBytes(bytes, flush: true);
    if (context.mounted) {
      showMessage(context, 'Zapisano: ${path.split(Platform.pathSeparator).last}.', tone: ToastTone.success);
    }
  } catch (_) {
    if (context.mounted) showError(context, const AppFailure('Nie udało się zapisać pliku. Wybierz inny folder.'));
  }
}
