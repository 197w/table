import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:table_panel/shared/menu_photo.dart';

// Jeden stały rozmiar obrazów z panelu (27.11.2026, prośba użytkownika): banner 1920 × 1080, danie 1200 × 1200,
// przycięcie od środka do proporcji i opis w powiadomieniu.

void main() {
  img.Image picture(int w, int h) {
    final image = img.Image(width: w, height: h);
    // Lewa połowa czerwona, prawa niebieska: po przycięciu od środka obie zostają.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        image.setPixelRgb(x, y, x < w / 2 ? 220 : 20, 30, x < w / 2 ? 20 : 220);
      }
    }
    return image;
  }

  test('banner z kwadratu: przycięty od środka do 16:9 i dokładnie 1920 × 1080', () {
    final picked = prepareImage(img.encodePng(picture(1600, 1600)), 1920, 1080);
    final out = img.decodeJpg(picked.jpeg)!;
    expect((out.width, out.height), (1920, 1080));
    expect(picked.cropped, isTrue);
    expect(picked.smallerThan(ImageSpec.banner), isTrue);
    expect(
      imageNote(picked, ImageSpec.banner),
      'Plik miał 1600 × 1600 px, więc panel przyciął go od środka do 16:9. '
      'Jest też mniejszy niż 1920 × 1080 px, więc w aplikacji może być nieostry.',
    );
  });

  test('banner w dobrych proporcjach i większy: bez uwag', () {
    final picked = prepareImage(img.encodePng(picture(3840, 2160)), 1920, 1080);
    final out = img.decodeJpg(picked.jpeg)!;
    expect((out.width, out.height), (1920, 1080));
    expect(picked.cropped, isFalse);
    expect(imageNote(picked, ImageSpec.banner), isNull);
  });

  test('prawie 16:9 (1366 × 768) to nie przycięcie warte uwagi, ale plik jest mały', () {
    final picked = prepareImage(img.encodePng(picture(1366, 768)), 1920, 1080);
    expect(picked.cropped, isFalse);
    expect(
      imageNote(picked, ImageSpec.banner),
      'Plik ma 1366 × 768 px, czyli mniej niż 1920 × 1080 px, więc w aplikacji może być nieostry.',
    );
  });

  test('zdjęcie dania z poziomego: kwadrat 1200 × 1200, środek zostaje', () {
    final picked = prepareImage(img.encodePng(picture(2400, 1600)), 1200, 1200);
    final out = img.decodeJpg(picked.jpeg)!;
    expect((out.width, out.height), (1200, 1200));
    // Środek zdjęcia (granica kolorów) jest nadal na środku kwadratu.
    expect(out.getPixel(300, 600).r, greaterThan(150));
    expect(out.getPixel(900, 600).b, greaterThan(150));
    expect(ImageSpec.dish.label, '1200 × 1200 px (kwadrat)');
    expect(ImageSpec.banner.label, '1920 × 1080 px (16:9)');
  });

  test('plik, który nie jest obrazem', () {
    final text = Uint8List.fromList('to nie jest obraz, tylko tekst'.codeUnits);
    expect(() => prepareImage(text, 1200, 1200), throwsFormatException);
  });
}
