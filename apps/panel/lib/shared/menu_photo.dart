import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Wybór zdjęcia dania z dysku. Zdjęcie jest zmniejszane do 1200 px i zapisywane jako JPG,
/// żeby w aplikacji gości ładowało się szybko także przez sieć komórkową.
/// Null: nic nie wybrano. Wyjątek [FormatException]: plik nie jest obrazem.
Future<Uint8List?> pickMenuPhoto() async {
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
  return compute(_shrink, bytes);
}

Uint8List _shrink(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('To nie jest zdjęcie.');
  final oriented = img.bakeOrientation(decoded);
  const max = 1200;
  final resized = oriented.width > max || oriented.height > max
      ? img.copyResize(
          oriented,
          width: oriented.width >= oriented.height ? max : null,
          height: oriented.height > oriented.width ? max : null,
          interpolation: img.Interpolation.average,
        )
      : oriented;
  return img.encodeJpg(resized, quality: 82);
}
