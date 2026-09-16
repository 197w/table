import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Otwiera domyślną aplikację map z celem podróży ustawionym na lokal.
/// Android: link geo, który obsługuje wybrana przez gościa aplikacja map.
/// iOS: Apple Maps z trasą do lokalu.
/// Gdy żadna aplikacja nie odpowie, otwiera trasę w Google Maps w przeglądarce.
Future<bool> openNavigation({
  required double lat,
  required double lng,
  required String label,
  required TargetPlatform platform,
}) async {
  final name = Uri.encodeComponent(label);
  final candidates = <Uri>[
    if (platform == TargetPlatform.iOS)
      Uri.parse('https://maps.apple.com/?daddr=$lat,$lng&q=$name')
    else
      Uri.parse('geo:$lat,$lng?q=$lat,$lng($name)'),
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
  ];

  for (final uri in candidates) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Następny sposób.
    }
  }
  return false;
}
