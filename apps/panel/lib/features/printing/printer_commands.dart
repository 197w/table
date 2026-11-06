import 'dart:convert';
import 'dart:typed_data';

import 'label_render.dart';

// Polecenia drukarek etykiet. Etykieta idzie jako obraz z punktów (BITMAP w TSPL, ^GFA w ZPL), więc wydruk
// wygląda jak w edytorze, z czcionką Geist i polskimi znakami, bez czcionek drukarki.

/// Język poleceń drukarki etykiet.
enum PrinterLanguage {
  tspl('TSPL', 'Xprinter, TSC, Gprinter'),
  zpl('ZPL', 'Zebra');

  const PrinterLanguage(this.label, this.brands);
  final String label;
  final String brands;

  static PrinterLanguage from(Object? value) => value == 'zpl' ? PrinterLanguage.zpl : PrinterLanguage.tspl;

  /// Zgadywany po nazwie drukarki w systemie: Zebra (ZDesigner) mówi ZPL, reszta TSPL.
  static PrinterLanguage guess(String printerName) {
    final name = printerName.toLowerCase();
    return name.contains('zebra') || name.contains('zdesigner') ? PrinterLanguage.zpl : PrinterLanguage.tspl;
  }
}

/// Ustawienia wydruku wspólne dla obu języków.
typedef LabelJobOptions = ({
  int widthMm,
  int heightMm,
  // Ciemność druku 1–15 (8 to środek).
  int darkness,
  // Obrót o 180° (etykieta wychodzi do góry nogami).
  bool rotate,
  // Przerwa między etykietami w milimetrach (0: papier ciągły).
  double gapMm,
});

String _mm(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// Zadanie TSPL: rozmiar etykiety i przerwa, ciemność, potem każda etykieta jako BITMAP. W TSPL bit 0 to punkt
/// wydrukowany, a 1 biały, więc odwracamy bity (w [LabelRaster] 1 to czarny).
Uint8List tsplJob(List<LabelRaster> labels, LabelJobOptions o) {
  final out = BytesBuilder(copy: false);
  void line(String s) => out.add(ascii.encode('$s\r\n'));
  line('SIZE ${o.widthMm} mm,${o.heightMm} mm');
  line(o.gapMm <= 0 ? 'GAP 0 mm,0 mm' : 'GAP ${_mm(o.gapMm)} mm,0 mm');
  line('DIRECTION ${o.rotate ? 0 : 1},0');
  line('REFERENCE 0,0');
  line('OFFSET 0 mm');
  line('DENSITY ${o.darkness.clamp(0, 15)}');
  line('SPEED 4');
  line('SET TEAR ON');
  for (final label in labels) {
    line('CLS');
    final inverted = Uint8List(label.bits.length);
    for (var i = 0; i < inverted.length; i++) {
      inverted[i] = ~label.bits[i] & 0xFF;
    }
    // Ostatni bajt wiersza ma punkty poza szerokością: zostają białe (1).
    out.add(ascii.encode('BITMAP 0,0,${label.rowBytes},${label.height},0,'));
    out.add(inverted);
    out.add(ascii.encode('\r\n'));
    line('PRINT 1,1');
  }
  return out.toBytes();
}

const _hex = '0123456789ABCDEF';

/// Zadanie ZPL: każda etykieta osobno (^XA ... ^XZ) z obrazem ^GFA (1 to punkt wydrukowany).
Uint8List zplJob(List<LabelRaster> labels, LabelJobOptions o) {
  final out = StringBuffer();
  for (final label in labels) {
    final total = label.bits.length;
    out
      ..write('^XA')
      ..write('^PW${label.width}')
      ..write('^LL${label.height}')
      ..write('^LH0,0')
      ..write(o.rotate ? '^POI' : '^PON')
      ..write(o.gapMm <= 0 ? '^MNN' : '^MNY')
      // Ciemność w ZPL: 0–30.
      ..write('~SD${(o.darkness.clamp(0, 15) * 2).toString().padLeft(2, '0')}')
      ..write('^FO0,0^GFA,$total,$total,${label.rowBytes},');
    for (final b in label.bits) {
      out
        ..write(_hex[b >> 4])
        ..write(_hex[b & 0x0F]);
    }
    out.write('^FS^PQ1^XZ\n');
  }
  return ascii.encode(out.toString());
}

Uint8List labelJob(PrinterLanguage language, List<LabelRaster> labels, LabelJobOptions options) =>
    switch (language) {
      PrinterLanguage.tspl => tsplJob(labels, options),
      PrinterLanguage.zpl => zplJob(labels, options),
    };
