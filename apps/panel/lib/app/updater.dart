import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:table_core/table_core.dart';

/// Wersja panelu opublikowana na serwerze.
class PanelRelease {
  const PanelRelease({
    required this.version,
    required this.url,
    required this.sha256,
    required this.notes,
  });

  final String version;
  final String url;
  final String sha256;
  final String notes;

  factory PanelRelease.fromJson(Map<String, dynamic> json) => PanelRelease(
    version: json['version'] as String,
    url: json['url'] as String,
    sha256: (json['sha256'] as String).toLowerCase(),
    notes: json['notes'] as String? ?? '',
  );
}

/// Aktualizacje panelu na Windowsie. GitHub Actions buduje instalator i wrzuca go
/// razem z opisem wersji do publicznego katalogu `panel-releases` w Supabase.
/// Panel sprawdza ten opis przy starcie i co kilka godzin, a instalator podmienia
/// program po cichu i uruchamia go ponownie.
abstract final class PanelUpdater {
  /// Działa tylko w zainstalowanym panelu na Windowsie. Panel uruchomiony z folderu
  /// projektu (w trakcie pracy nad kodem) nigdy się sam nie podmienia.
  static bool get enabled {
    if (!kReleaseMode || !Platform.isWindows) return false;
    final exe = Platform.resolvedExecutable.toLowerCase();
    return exe.contains(r'\programs\table panel\');
  }

  static Uri get _manifest => Uri.parse(
    '${Env.supabaseUrl}/storage/v1/object/public/panel-releases/windows/latest.json',
  );

  /// Nowsza wersja albo null, gdy panel jest aktualny, serwer milczy albo nie ma internetu.
  static Future<PanelRelease?> check({Duration timeout = const Duration(seconds: 6)}) async {
    if (!enabled) return null;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(_manifest).timeout(timeout);
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      final release = PanelRelease.fromJson(jsonDecode(body) as Map<String, dynamic>);
      final current = (await PackageInfo.fromPlatform()).version;
      return isNewer(release.version, current) ? release : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Czy wersja [candidate] (np. 0.3.0) jest nowsza niż [current].
  static bool isNewer(String candidate, String current) {
    List<int> parts(String v) => [
      for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0,
    ];
    final a = parts(candidate);
    final b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Pobiera instalator, sprawdza jego sumę kontrolną, uruchamia go po cichu i zamyka panel.
  /// Instalator na końcu sam uruchamia nową wersję. [onProgress] dostaje 0–1.
  static Future<void> install(
    PanelRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final client = HttpClient();
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}TablePanelSetup-${release.version}.exe',
    );
    try {
      final request = await client.getUrl(Uri.parse(release.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw const AppFailure('Nie udało się pobrać nowej wersji. Spróbuj później.');
      }
      final total = response.contentLength;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } finally {
      client.close(force: true);
    }

    // Instalator musi być dokładnie tym, który opublikował GitHub.
    final digest = sha256.convert(await file.readAsBytes()).toString();
    if (digest != release.sha256) {
      await file.delete().catchError((_) => file);
      throw const AppFailure('Pobrany plik jest uszkodzony. Spróbuj ponownie później.');
    }

    await Process.start(
      file.path,
      const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}

/// Nowsza wersja znaleziona w trakcie pracy panelu. Boczne menu pokazuje ją jako wiersz
/// do kliknięcia, żeby nie przerywać obsługi w środku serwisu.
class AvailableUpdateNotifier extends Notifier<PanelRelease?> {
  Timer? _timer;

  @override
  PanelRelease? build() {
    if (!PanelUpdater.enabled) return null;
    _timer = Timer.periodic(const Duration(hours: 4), (_) => _check());
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  Future<void> _check() async {
    final release = await PanelUpdater.check();
    if (release != null) state = release;
  }
}

final availableUpdateProvider =
    NotifierProvider<AvailableUpdateNotifier, PanelRelease?>(AvailableUpdateNotifier.new);

/// Numer wersji panelu do pokazania w menu.
final panelVersionProvider = FutureProvider<String>(
  (ref) async => (await PackageInfo.fromPlatform()).version,
);
