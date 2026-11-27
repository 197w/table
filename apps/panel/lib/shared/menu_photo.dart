import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Jeden stały rozmiar każdego obrazu wgrywanego z panelu (27.11.2026, prośba użytkownika: „w opisach dokładne
/// rozmiary, jeden rozmiar, najlepiej dla urządzenia, gdzie obraz jest największy; na mniejszych skalowany”).
/// Panel przycina obraz od środka do proporcji i zmienia rozmiar dokładnie na [width] × [height], więc w aplikacji
/// Table każdy obraz ma te same proporcje co miejsce, w którym go widać, i jest tylko pomniejszany.
class ImageSpec {
  const ImageSpec._(this.width, this.height, this.ratioLabel);

  /// Banner lokalu: strona lokalu na tablecie ma 820 punktów szerokości (2 px na punkt, czyli ok. 1640 px), na
  /// telefonie do 440 punktów (3 px na punkt, 1320 px). 1920 × 1080 (16:9) pokrywa oba, a lista lokali i strona
  /// lokalu pokazują go zawsze w 16:9.
  static const banner = ImageSpec._(1920, 1080, '16:9');

  /// Zdjęcie dania: największe w powiększeniu w menu (najwyżej 600 punktów, czyli 1200 px), miniatury
  /// w menu, koszyku i na stronie lokalu są kwadratowe.
  static const dish = ImageSpec._(1200, 1200, 'kwadrat');

  final int width;
  final int height;
  final String ratioLabel;

  /// „1920 × 1080 px (16:9)”.
  String get label => '$width × $height px ($ratioLabel)';
}

/// Obraz gotowy do wysłania: JPG w rozmiarze [ImageSpec] i wymiary pliku, który wybrała osoba.
class PickedImage {
  const PickedImage({required this.jpeg, required this.sourceWidth, required this.sourceHeight, required this.cropped});

  final Uint8List jpeg;
  final int sourceWidth;
  final int sourceHeight;

  /// Plik miał inne proporcje i został przycięty od środka.
  final bool cropped;

  /// Plik mniejszy niż rozmiar docelowy: w aplikacji może być nieostry.
  bool smallerThan(ImageSpec spec) => sourceWidth < spec.width || sourceHeight < spec.height;
}

/// Wybór obrazu z dysku i przygotowanie go do [spec]. Null: nic nie wybrano.
/// Wyjątek [FormatException]: plik nie jest obrazem.
Future<PickedImage?> pickImage(ImageSpec spec) async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'Zdjęcia',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
        uniformTypeIdentifiers: ['public.jpeg', 'public.png', 'org.webmproject.webp'],
      ),
    ],
  );
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  return compute(_prepare, (bytes, spec.width, spec.height));
}

/// Przycina od środka do proporcji [width]:[height] i zmienia rozmiar dokładnie na [width] × [height] (JPG 82).
@visibleForTesting
PickedImage prepareImage(Uint8List bytes, int width, int height) => _prepare((bytes, width, height));

PickedImage _prepare((Uint8List, int, int) input) {
  final (bytes, width, height) = input;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('To nie jest zdjęcie.');
  final source = img.bakeOrientation(decoded);
  final target = width / height;
  final ratio = source.width / source.height;
  var cropW = source.width;
  var cropH = source.height;
  if (ratio > target) {
    cropW = (source.height * target).round();
  } else if (ratio < target) {
    cropH = (source.width / target).round();
  }
  final cropped = cropW != source.width || cropH != source.height;
  final framed = cropped
      ? img.copyCrop(
          source,
          x: (source.width - cropW) ~/ 2,
          y: (source.height - cropH) ~/ 2,
          width: cropW,
          height: cropH,
        )
      : source;
  final resized = framed.width == width && framed.height == height
      ? framed
      : img.copyResize(
          framed,
          width: width,
          height: height,
          interpolation: framed.width > width ? img.Interpolation.average : img.Interpolation.cubic,
        );
  return PickedImage(
    jpeg: img.encodeJpg(resized, quality: 82),
    sourceWidth: source.width,
    sourceHeight: source.height,
    // Różnica proporcji poniżej 1% (np. 1366 × 768) to nie przycięcie, które warto zgłaszać.
    cropped: cropped && (ratio - target).abs() / target > 0.01,
  );
}

/// Opis pliku po przygotowaniu (do powiadomienia po zapisie): przycięcie i za mały plik. Null: plik pasował.
String? imageNote(PickedImage picked, ImageSpec spec) {
  final size = '${picked.sourceWidth} × ${picked.sourceHeight} px';
  return [
    if (picked.cropped) 'Plik miał $size, więc panel przyciął go od środka do ${spec.ratioLabel}.',
    if (picked.smallerThan(spec))
      '${picked.cropped ? 'Jest też mniejszy' : 'Plik ma $size, czyli mniej'} niż ${spec.width} × ${spec.height} px, '
          'więc w aplikacji może być nieostry.',
  ].join(' ').ifEmptyNull;
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
