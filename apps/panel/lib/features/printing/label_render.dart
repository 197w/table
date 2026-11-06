import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:table_core/table_core.dart';

import 'label_template.dart';

// Rysowanie etykiety: ten sam kod rysuje podgląd w edytorze (piksele ekranu na milimetr) i wydruk
// (8 punktów na milimetr, czyli 203 dpi drukarek termicznych), więc wydruk wygląda jak w edytorze.

/// Rozdzielczość drukarek termicznych etykiet: 203 dpi = 8 punktów na milimetr.
const labelDotsPerMm = 8.0;

const _mmPerPoint = 25.4 / 72;
const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);

/// Wysokość tekstu w punktach dla podanej skali.
double labelFontPx(double points, double scale) => points * _mmPerPoint * scale;

/// Rysuje etykietę na białym tle w skali [scale] pikseli na milimetr.
void paintLabel(
  Canvas canvas,
  LabelTemplate template,
  Map<String, String> values, {
  required double scale,
  ui.Image? logo,
}) {
  final size = Size(template.widthMm * scale, template.heightMm * scale);
  canvas.save();
  canvas.clipRect(Offset.zero & size);
  canvas.drawRect(Offset.zero & size, Paint()..color = _white);
  for (final e in template.elements) {
    paintLabelElement(canvas, e, values, scale: scale, logo: logo);
  }
  canvas.restore();
}

void paintLabelElement(
  Canvas canvas,
  LabelElement e,
  Map<String, String> values, {
  required double scale,
  ui.Image? logo,
}) {
  final rect = Rect.fromLTWH(e.x * scale, e.y * scale, e.w * scale, e.h * scale);
  if (rect.width <= 0 || rect.height <= 0) return;
  final black = Paint()..color = _black;
  canvas.save();
  canvas.clipRect(rect);
  switch (e.type) {
    case LabelElementType.text:
      _paintText(canvas, e, resolveLabelText(e.text, values), rect, scale);
    case LabelElementType.line:
      canvas.drawRect(rect, black);
    case LabelElementType.box:
      if (e.fill) {
        canvas.drawRect(rect, black);
      } else {
        final stroke = math.max(e.stroke * scale, 1.0);
        canvas.drawRect(
          rect.deflate(stroke / 2),
          Paint()
            ..color = _black
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke,
        );
      }
    case LabelElementType.qr:
      _paintQr(canvas, resolveLabelText(e.text, values), rect);
    case LabelElementType.logo:
      if (logo != null) {
        paintImage(canvas: canvas, rect: rect, image: logo, fit: BoxFit.contain, filterQuality: FilterQuality.medium);
      }
  }
  canvas.restore();
}

TextPainter _layout(String text, LabelElement e, double fontPx, double width, Color color) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: fontPx,
        height: 1.12,
        // Zwykły napis w grubości 500: na drukarce termicznej 400 przy małych literach wychodzi za cienki.
        fontWeight: e.bold ? FontWeight.w600 : FontWeight.w500,
        color: color,
      ),
    ),
    textAlign: e.align.textAlign,
    textDirection: TextDirection.ltr,
  )..layout(minWidth: width, maxWidth: width);
}

void _paintText(Canvas canvas, LabelElement e, String text, Rect rect, double scale) {
  if (e.invert) canvas.drawRect(rect, Paint()..color = _black);
  if (text.isEmpty) return;
  final color = e.invert ? _white : _black;
  final box = e.invert ? rect.deflate(math.min(0.8 * scale, rect.shortestSide / 4)) : rect;
  var fontPx = labelFontPx(e.size, scale);
  var painter = _layout(text, e, fontPx, box.width, color);
  if (e.fit) {
    // Zmniejsza czcionkę, aż tekst zmieści się w polu (najwyżej do 35% wielkości).
    final smallest = fontPx * 0.35;
    while (painter.height > box.height + 0.5 && fontPx > smallest) {
      painter.dispose();
      fontPx *= 0.92;
      painter = _layout(text, e, fontPx, box.width, color);
    }
  }
  // Na środku wysokości pola; dłuższy tekst od góry (nadmiar ucina pole).
  final dy = painter.height <= box.height ? (box.height - painter.height) / 2 : 0.0;
  painter.paint(canvas, Offset(box.left, box.top + dy));
  painter.dispose();
}

void _paintQr(Canvas canvas, String data, Rect rect) {
  if (data.isEmpty) return;
  final result = QrValidator.validate(
    data: data,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.M,
  );
  final qr = result.qrCode;
  if (result.status != QrValidationStatus.valid || qr == null) return;
  final side = rect.shortestSide;
  canvas.save();
  canvas.translate(rect.left + (rect.width - side) / 2, rect.top + (rect.height - side) / 2);
  QrPainter.withQr(qr: qr, gapless: true).paint(canvas, Size(side, side));
  canvas.restore();
}

/// Etykieta gotowa do druku: punkty czarne (1) i białe (0), wiersz po wierszu, najstarszy bit to lewy punkt.
@immutable
class LabelRaster {
  const LabelRaster({required this.width, required this.height, required this.bits});

  final int width;
  final int height;
  final Uint8List bits;

  int get rowBytes => (width + 7) >> 3;

  bool isBlack(int x, int y) => bits[y * rowBytes + (x >> 3)] & (0x80 >> (x & 7)) != 0;

  int get blackDots {
    var n = 0;
    for (final b in bits) {
      var v = b;
      while (v != 0) {
        n += v & 1;
        v >>= 1;
      }
    }
    return n;
  }
}

/// Rysuje etykietę w rozdzielczości drukarki i zamienia ją na czarne i białe punkty. Logo (zdjęcie albo kolorowy
/// znak) rastrujemy (Floyd–Steinberg), żeby jasne kolory nie znikły; reszta to próg jasności.
Future<LabelRaster> rasterizeLabel(
  LabelTemplate template,
  Map<String, String> values, {
  ui.Image? logo,
  double dotsPerMm = labelDotsPerMm,
}) async {
  final width = (template.widthMm * dotsPerMm).round();
  final height = (template.heightMm * dotsPerMm).round();
  final recorder = ui.PictureRecorder();
  paintLabel(Canvas(recorder), template, values, scale: dotsPerMm, logo: logo);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  if (data == null) throw StateError('Nie udało się narysować etykiety.');
  final rgba = data.buffer.asUint8List();

  // Jasność każdego punktu (0 czarny, 255 biały).
  final light = Float32List(width * height);
  for (var i = 0; i < width * height; i++) {
    final p = i * 4;
    light[i] = 0.299 * rgba[p] + 0.587 * rgba[p + 1] + 0.114 * rgba[p + 2];
  }

  // Prostokąty logo w punktach drukarki: tam rastrowanie zamiast progu.
  final dithered = <Rect>[
    if (logo != null)
      for (final e in template.elements)
        if (e.type == LabelElementType.logo)
          Rect.fromLTWH(e.x * dotsPerMm, e.y * dotsPerMm, e.w * dotsPerMm, e.h * dotsPerMm),
  ];
  bool inLogo(int x, int y) {
    for (final r in dithered) {
      if (x >= r.left && x < r.right && y >= r.top && y < r.bottom) return true;
    }
    return false;
  }

  final rowBytes = (width + 7) >> 3;
  final bits = Uint8List(rowBytes * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      final old = light[i];
      final black = old < 128;
      if (black) bits[y * rowBytes + (x >> 3)] |= 0x80 >> (x & 7);
      if (dithered.isNotEmpty && inLogo(x, y)) {
        final err = old - (black ? 0 : 255);
        if (x + 1 < width) light[i + 1] += err * 7 / 16;
        if (y + 1 < height) {
          if (x > 0) light[i + width - 1] += err * 3 / 16;
          light[i + width] += err * 5 / 16;
          if (x + 1 < width) light[i + width + 1] += err * 1 / 16;
        }
      }
    }
  }
  return LabelRaster(width: width, height: height, bits: bits);
}

/// Obraz z punktów etykiety (podgląd wydruku w edytorze).
Future<ui.Image> labelRasterImage(LabelRaster raster) {
  final pixels = Uint8List(raster.width * raster.height * 4);
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      final p = (y * raster.width + x) * 4;
      final v = raster.isBlack(x, y) ? 0 : 255;
      pixels[p] = v;
      pixels[p + 1] = v;
      pixels[p + 2] = v;
      pixels[p + 3] = 255;
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(pixels, raster.width, raster.height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}
