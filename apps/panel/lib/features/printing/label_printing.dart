import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import 'label_render.dart';
import 'label_template.dart';
import 'printer_commands.dart';
import 'printer_transport.dart';

// Drukarka etykiet na tym komputerze (preferencje lokalne, jak „Ten komputer” w ustawieniach), wzór etykiety
// lokalu z bazy, drukowanie zamówień i automatyczny wydruk po przyjęciu zamówienia.

/// Drukarka etykiet tego komputera i automatyczne drukowanie. Każdy komputer ma swoją: drukuje tylko ten,
/// do którego drukarka jest podłączona.
class LabelPrinterSettings {
  const LabelPrinterSettings({
    this.network = false,
    this.printer = '',
    this.host = '',
    this.port = 9100,
    this.language = PrinterLanguage.tspl,
    this.darkness = 8,
    this.rotate = false,
    this.gapMm = 2,
    this.autoPrint = false,
    this.autoSince,
  });

  final bool network;

  /// Nazwa drukarki w systemie (Windows, macOS).
  final String printer;
  final String host;
  final int port;
  final PrinterLanguage language;

  /// Ciemność druku 1–15.
  final int darkness;
  final bool rotate;
  final double gapMm;

  /// Drukuje sam, gdy zamówienie zostanie przyjęte (na tym albo innym komputerze, w aplikacji pracownika).
  final bool autoPrint;

  /// Od kiedy drukuje sam: starsze przyjęte zamówienia nie drukują się po włączeniu.
  final DateTime? autoSince;

  bool get configured => network ? host.trim().isNotEmpty : printer.isNotEmpty;

  PrinterTarget get target => (network: network, name: printer, host: host, port: port);

  /// Nazwa do wyświetlenia, np. „Xprinter XP-410B” albo „192.168.1.50:9100”.
  String get title => network ? '${host.trim()}:$port' : printer;

  LabelPrinterSettings copyWith({
    bool? network,
    String? printer,
    String? host,
    int? port,
    PrinterLanguage? language,
    int? darkness,
    bool? rotate,
    double? gapMm,
    bool? autoPrint,
    DateTime? autoSince,
  }) => LabelPrinterSettings(
    network: network ?? this.network,
    printer: printer ?? this.printer,
    host: host ?? this.host,
    port: port ?? this.port,
    language: language ?? this.language,
    darkness: darkness ?? this.darkness,
    rotate: rotate ?? this.rotate,
    gapMm: gapMm ?? this.gapMm,
    autoPrint: autoPrint ?? this.autoPrint,
    autoSince: autoSince ?? this.autoSince,
  );

  Map<String, dynamic> toJson() => {
    'network': network,
    'printer': printer,
    'host': host,
    'port': port,
    'language': language.name,
    'darkness': darkness,
    'rotate': rotate,
    'gap': gapMm,
    'auto': autoPrint,
    'autoSince': autoSince?.toIso8601String(),
  };

  factory LabelPrinterSettings.fromJson(Map<String, dynamic> json) => LabelPrinterSettings(
    network: json['network'] == true,
    printer: json['printer'] as String? ?? '',
    host: json['host'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 9100,
    language: PrinterLanguage.from(json['language']),
    darkness: (json['darkness'] as num?)?.toInt() ?? 8,
    rotate: json['rotate'] == true,
    gapMm: (json['gap'] as num?)?.toDouble() ?? 2,
    autoPrint: json['auto'] == true,
    autoSince: DateTime.tryParse(json['autoSince'] as String? ?? ''),
  );

  LabelJobOptions jobOptions(LabelTemplate t) =>
      (widthMm: t.widthMm, heightMm: t.heightMm, darkness: darkness, rotate: rotate, gapMm: gapMm);
}

class LabelPrinterNotifier extends Notifier<LabelPrinterSettings> {
  static const _key = 'panel_drukarka_etykiet';

  @override
  LabelPrinterSettings build() {
    unawaited(_load());
    return const LabelPrinterSettings();
  }

  Future<void> _load() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_key);
      if (raw != null) state = LabelPrinterSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Bez zapisanych ustawień: drukarka do wybrania.
    }
  }

  Future<void> set(LabelPrinterSettings value) async {
    // Włączenie automatu liczy się od teraz.
    if (value.autoPrint && !state.autoPrint) value = value.copyWith(autoSince: DateTime.now());
    state = value;
    try {
      await SharedPreferencesAsync().setString(_key, jsonEncode(value.toJson()));
    } catch (_) {
      // Działa do zamknięcia panelu.
    }
  }
}

final labelPrinterProvider = NotifierProvider<LabelPrinterNotifier, LabelPrinterSettings>(LabelPrinterNotifier.new);

/// Drukarki zainstalowane w systemie (odświeżane przy wejściu do „Drukarki”).
final systemPrintersProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  if (!PrinterTransport.supportsSystem) return const [];
  try {
    return await PrinterTransport.systemPrinters();
  } catch (_) {
    return const [];
  }
});

/// Wzór etykiety lokalu; bez zapisanego wzoru domyślny 100 × 50 mm.
final labelTemplateProvider = FutureProvider.autoDispose.family<LabelTemplate, String>((ref, restaurantId) async {
  ref.cacheFor(const Duration(minutes: 30));
  return LabelTemplate.fromJson(await ref.watch(repositoryProvider).labelTemplateJson(restaurantId));
});

/// Logo lokalu jako obraz do etykiety. Null: lokal nie ma logo albo nie udało się go pobrać.
final labelLogoProvider = FutureProvider.family<ui.Image?, String>((ref, url) async {
  try {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final codec = await ui.instantiateImageCodec(response.bodyBytes, targetWidth: 600);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
});

/// Zamówienia, którym ten komputer wydrukował już etykiety (żeby automat nie drukował drugi raz, także po
/// ponownym uruchomieniu panelu). Pamięta 3 dni.
abstract final class _PrintedOrders {
  static const _key = 'panel_etykiety_wydrukowane';
  static Map<String, String>? _cache;

  static Future<Map<String, String>> _all() async {
    if (_cache != null) return _cache!;
    try {
      final raw = await SharedPreferencesAsync().getString(_key);
      _cache = raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  static Future<bool> contains(String orderId) async => (await _all()).containsKey(orderId);

  static Future<void> add(String orderId) async {
    final all = await _all();
    final limit = DateTime.now().subtract(const Duration(days: 3));
    all.removeWhere((_, at) => (DateTime.tryParse(at) ?? limit).isBefore(limit));
    all[orderId] = DateTime.now().toIso8601String();
    try {
      await SharedPreferencesAsync().setString(_key, jsonEncode(all));
    } catch (_) {
      // Pamięta do zamknięcia panelu.
    }
  }
}

/// „1 etykieta”, „3 etykiety”, „5 etykiet”.
String labelCount(int n) {
  final tens = n % 100;
  final ones = n % 10;
  if (n == 1) return '1 etykieta';
  if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) return '$n etykiety';
  return '$n etykiet';
}

/// Drukowanie etykiet na drukarce tego komputera.
class LabelPrinting {
  LabelPrinting(this._ref);

  final Ref _ref;

  LabelPrinterSettings get _settings => _ref.read(labelPrinterProvider);

  Future<ui.Image?> _logo(LabelTemplate t, String? logoUrl) async {
    if (logoUrl == null || !t.elements.any((e) => e.type == LabelElementType.logo)) return null;
    return _ref.read(labelLogoProvider(logoUrl).future);
  }

  Future<void> _send(LabelTemplate t, List<Map<String, String>> labels, ui.Image? logo, String job) async {
    final settings = _settings;
    if (!settings.configured) {
      throw const PrinterException('Wybierz drukarkę etykiet w „Drukarki” (pasek boczny, pod ustawieniami).');
    }
    final rasters = [for (final values in labels) await rasterizeLabel(t, values, logo: logo)];
    final data = labelJob(settings.language, rasters, settings.jobOptions(t));
    await PrinterTransport.send(settings.target, data, job: job);
  }

  /// Wydruk próbny wzoru (także niezapisanego) z przykładowym zamówieniem.
  Future<void> printTest(LabelTemplate t, Map<String, String> values, {String? logoUrl}) async {
    await _send(t, [values], await _logo(t, logoUrl), 'Table: etykieta testowa');
  }

  /// Etykiety zamówienia według wzoru lokalu. Zwraca liczbę wydrukowanych etykiet (0: nic do druku).
  Future<int> printOrder(String restaurantId, TakeawayOrder order) async {
    final restaurant = _ref.read(currentRestaurantProvider);
    final template = await _ref.read(labelTemplateProvider(restaurantId).future);
    final menu = await _ref.read(menuProvider(restaurantId).future);
    final labels = labelValuesForOrder(
      order,
      template,
      restaurantName: restaurant?.name ?? '',
      menu: labelMenuInfo(menu),
    );
    if (labels.isEmpty) return 0;
    await _send(template, labels, await _logo(template, restaurant?.logoUrl), 'Table: ${order.label}');
    await _PrintedOrders.add(order.id);
    return labels.length;
  }
}

final labelPrintingProvider = Provider<LabelPrinting>(LabelPrinting.new);

/// Automatyczny wydruk etykiet po przyjęciu zamówienia na wynos (dostawa, odbiór), tylko na komputerze
/// z włączonym automatem. Trzyma go `shell.dart` na każdej zakładce.
final labelAutoPrintProvider = Provider.autoDispose.family<void, String>((ref, restaurantId) {
  final settings = ref.watch(labelPrinterProvider);
  if (!settings.autoPrint || !settings.configured) return;
  final since = settings.autoSince ?? DateTime.now();
  final queued = <String>{};
  ref.listen(takeawayOrdersProvider(restaurantId), (_, next) {
    final orders = next.value;
    if (orders == null) return;
    final now = DateTime.now();
    for (final o in orders) {
      final accepted = o.acceptedAt;
      if (accepted == null || accepted.isBefore(since)) continue;
      if (now.difference(accepted) > const Duration(hours: 2)) continue;
      if (o.stage == TakeawayStage.rejected || o.stage == TakeawayStage.cancelled) continue;
      if (!queued.add(o.id)) continue;
      unawaited(() async {
        if (await _PrintedOrders.contains(o.id)) return;
        try {
          final n = await ref.read(labelPrintingProvider).printOrder(restaurantId, o);
          if (n > 0) {
            Toasts.instance.show('${o.label}: ${labelCount(n)} na drukarce.', tone: ToastTone.success, icon: AppIcons.printer);
          }
        } catch (e) {
          // Bez ponawiania w kółko: etykiety można wydrukować ręcznie z karty zamówienia.
          Toasts.instance.show(
            'Etykiety ${o.label} się nie wydrukowały: ${errorText(e)}',
            tone: ToastTone.error,
            icon: AppIcons.printer,
          );
        }
      }());
    }
  }, fireImmediately: true);
});
