import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:table_core/table_core.dart';

import 'export_csv.dart';

/// Czcionki PDF: Geist z pakietu table_core (polskie znaki). Wczytane raz na uruchomienie panelu.
({pw.Font regular, pw.Font bold})? _fonts;

Future<({pw.Font regular, pw.Font bold})> _loadFonts() async {
  final cached = _fonts;
  if (cached != null) return cached;
  Future<pw.Font> font(String weight) async =>
      pw.Font.ttf(await rootBundle.load('packages/table_core/assets/fonts/Geist-$weight.ttf'));
  final loaded = (regular: await font('Regular'), bold: await font('SemiBold'));
  _fonts = loaded;
  return loaded;
}

const _ink = PdfColor.fromInt(0xFF161616);
const _muted = PdfColor.fromInt(0xFF6B716D);
const _line = PdfColor.fromInt(0xFFE2E4E3);
const _headerFill = PdfColor.fromInt(0xFFF1F2F1);
const _accent = PdfColor.fromInt(0xFF007A5C);

/// Plik PDF z tabelą eksportu: nagłówek z nazwą lokalu i miesiącem, tabela z sumą na końcu i numery stron.
/// Szerokie tabele (sprzedaż z VAT) na stronie poziomej, mniejszą czcionką.
Future<Uint8List> exportPdf(ExportTable table, {required String restaurant, required String period}) async {
  final fonts = await _loadFonts();
  final wide = table.header.length > 8;
  final size = table.header.length > 14 ? 6.2 : (wide ? 7.0 : 8.5);
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final created = '${now.day}.${two(now.month)}.${now.year}, ${two(now.hour)}:${two(now.minute)}';

  final doc = pw.Document(
    title: '${table.title} – $restaurant – $period',
    author: 'Table',
    creator: 'Panel Table',
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );

  pw.Widget cell(String text, int column, {bool bold = false, bool header = false}) {
    final right = table.numeric.contains(column);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
      child: pw.Text(
        text,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: header ? size - 0.4 : size,
          font: bold || header ? fonts.bold : fonts.regular,
          color: header ? _muted : _ink,
        ),
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
      header: (context) => context.pageNumber == 1
          ? pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 14),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          table.title,
                          style: pw.TextStyle(font: fonts.bold, fontSize: 16, color: _ink),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text('$restaurant · $period', style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
                      ],
                    ),
                  ),
                  pw.Text(
                    'Table',
                    style: pw.TextStyle(font: fonts.bold, fontSize: 12, color: _accent),
                  ),
                ],
              ),
            )
          : pw.SizedBox(),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          children: [
            pw.Text('Utworzono $created', style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            pw.Spacer(),
            pw.Text(
              'Strona ${context.pageNumber} z ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ],
        ),
      ),
      build: (context) => [
        if (table.rows.isEmpty)
          pw.Text('Brak danych w tym miesiącu.', style: const pw.TextStyle(fontSize: 10, color: _muted))
        else
          pw.Table(
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
            columnWidths: {
              for (var i = 0; i < table.header.length; i++)
                i: table.numeric.contains(i) ? const pw.FlexColumnWidth(1) : const pw.FlexColumnWidth(1.4),
            },
            children: [
              // Nagłówek tabeli powtarza się na każdej stronie.
              pw.TableRow(
                repeat: true,
                decoration: const pw.BoxDecoration(color: _headerFill),
                children: [for (final (i, h) in table.header.indexed) cell(h, i, header: true)],
              ),
              for (final row in table.rows) pw.TableRow(children: [for (final (i, v) in row.indexed) cell(v, i)]),
              if (table.footer case final footer?)
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: _headerFill,
                    border: pw.Border(top: pw.BorderSide(color: _ink, width: 0.8)),
                  ),
                  children: [for (final (i, v) in footer.indexed) cell(v, i, bold: true)],
                ),
            ],
          ),
      ],
    ),
  );
  return doc.save();
}

/// Miesiąc po polsku do nagłówka PDF, np. „październik 2026”.
String exportPeriod(DateTime month) => Fmt.monthYear(month);
