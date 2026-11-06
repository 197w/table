import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';
import 'fiscal_receipt.dart';
import 'novitus_xml.dart';
import 'printer_transport.dart';

// Drukarka fiskalna albo kasoterminal na tym komputerze („Drukarki” → „Paragony”). Na razie protokół XML
// Novitus przez sieć (publiczna dokumentacja). Komputer z drukarką może drukować sam paragon za każdy opłacony
// rachunek lokalu: zamknięty w panelu, u kelnera w telefonie albo przy wydaniu zamówienia na wynos.

/// Protokół drukarki fiskalnej.
enum FiscalProtocol {
  novitusXml('Novitus XML', 'Novitus: drukarki i kasy z protokołem XML (np. Deon Online, HD Online, Bono Online, Point)');

  const FiscalProtocol(this.label, this.devices);
  final String label;
  final String devices;
}

class FiscalSettings {
  const FiscalSettings({
    this.protocol = FiscalProtocol.novitusXml,
    this.host = '',
    this.port = 6001,
    this.auto = false,
    this.autoSince,
    this.deliveryVat = 8,
  });

  final FiscalProtocol protocol;
  final String host;
  final int port;

  /// Ten komputer drukuje paragony za wszystkie opłacone rachunki lokalu (kasa główna).
  final bool auto;
  final DateTime? autoSince;

  /// Stawka VAT opłaty za dostawę (zależy od lokalu; sprawdza księgowość).
  final int deliveryVat;

  bool get configured => host.trim().isNotEmpty;
  String get title => '${protocol.label} · ${host.trim()}:$port';

  FiscalSettings copyWith({String? host, int? port, bool? auto, DateTime? autoSince, int? deliveryVat}) => FiscalSettings(
    protocol: protocol,
    host: host ?? this.host,
    port: port ?? this.port,
    auto: auto ?? this.auto,
    autoSince: autoSince ?? this.autoSince,
    deliveryVat: deliveryVat ?? this.deliveryVat,
  );

  Map<String, dynamic> toJson() => {
    'protocol': protocol.name,
    'host': host,
    'port': port,
    'auto': auto,
    'autoSince': autoSince?.toIso8601String(),
    'deliveryVat': deliveryVat,
  };

  factory FiscalSettings.fromJson(Map<String, dynamic> json) => FiscalSettings(
    host: json['host'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 6001,
    auto: json['auto'] == true,
    autoSince: DateTime.tryParse(json['autoSince'] as String? ?? ''),
    deliveryVat: (json['deliveryVat'] as num?)?.toInt() ?? 8,
  );
}

class FiscalSettingsNotifier extends Notifier<FiscalSettings> {
  static const _key = 'panel_drukarka_fiskalna';

  @override
  FiscalSettings build() {
    unawaited(_load());
    return const FiscalSettings();
  }

  Future<void> _load() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_key);
      if (raw != null) state = FiscalSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Bez zapisanych ustawień.
    }
  }

  Future<void> set(FiscalSettings value) async {
    // Kolejka paragonów liczy się od włączenia (starsze rachunki nie drukują się same).
    if (value.auto && !state.auto) value = value.copyWith(autoSince: DateTime.now());
    state = value;
    try {
      await SharedPreferencesAsync().setString(_key, jsonEncode(value.toJson()));
    } catch (_) {
      // Działa do zamknięcia panelu.
    }
  }
}

final fiscalSettingsProvider = NotifierProvider<FiscalSettingsNotifier, FiscalSettings>(FiscalSettingsNotifier.new);

/// Stan drukarki do „Sprawdź połączenie”.
typedef FiscalStatus = ({bool online, bool paperOk, bool fiscal, Map<String, double?> rates});

class FiscalPrinting {
  FiscalPrinting(this._ref);

  final Ref _ref;
  Future<void> _queue = Future.value();

  FiscalSettings get _settings => _ref.read(fiscalSettingsProvider);

  /// Jedno zadanie naraz: drukarka fiskalna nie przyjmuje dwóch paragonów jednocześnie.
  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<NovitusConnection> _open() {
    final s = _settings;
    if (!s.configured) throw const PrinterException('Ustaw drukarkę fiskalną w „Drukarki” → „Paragony”.');
    return NovitusConnection.open(s.host, s.port);
  }

  Future<FiscalStatus> check() => _serial(() async {
    final c = await _open();
    try {
      final s = await c.status();
      final rates = await c.taxRates();
      return (online: s['online'] != 'no', paperOk: s['papererror'] != 'yes', fiscal: s['fiscal'] == 'yes', rates: rates);
    } finally {
      await c.close();
    }
  });

  /// Wydruk niefiskalny (nie rejestruje sprzedaży): sprawdzenie, że drukarka drukuje z panelu.
  Future<void> printTest(String restaurantName) => _serial(() async {
    final c = await _open();
    try {
      await c.command(
        novitusNonFiscal([
          'Table: test połączenia',
          restaurantName,
          Fmt.dateTime(DateTime.now()),
          'Ten wydruk nie jest paragonem.',
        ]),
      );
    } finally {
      await c.close();
    }
  });

  /// Paragon za opłacony rachunek. Rezerwuje go w bazie (drugi komputer go nie wydrukuje), drukuje i zapisuje numer.
  /// False: rachunek ma już paragon. [force]: ponowna próba po przerwanym wydruku (pyta obsługa).
  Future<bool> printOrder(String orderId, {bool force = false}) => _serial(() async {
    final repo = _ref.read(repositoryProvider);
    final orders = await repo.fiscalOrders([orderId]);
    if (orders.isEmpty) throw const PrinterException('Nie znaleziono rachunku.');
    final (order, nip) = orders.single;
    final receipt = fiscalReceiptFor(order, nip: nip, deliveryVat: _settings.deliveryVat);
    if (receipt.lines.isEmpty || receipt.totalGrosze <= 0) {
      throw const PrinterException('Rachunek nie ma nic do paragonu (kwota 0 zł).');
    }
    if (!await repo.fiscalClaim(orderId, force: force)) return false;
    try {
      final number = await _print(receipt);
      await repo.fiscalDone(orderId, number, _settings.title);
      return true;
    } catch (e) {
      await repo.fiscalRelease(orderId).catchError((_) {});
      rethrow;
    }
  });

  Future<String> _print(FiscalReceipt receipt) async {
    final c = await _open();
    try {
      final status = await c.status();
      if (status['online'] == 'no') throw const PrinterException('Drukarka fiskalna jest wyłączona albo w menu.');
      if (status['papererror'] == 'yes') throw const PrinterException('W drukarce fiskalnej skończył się papier.');
      // Paragon otwarty po przerwanym wydruku: anulujemy go, zanim zaczniemy nowy.
      if (status['intransaction'] == 'yes') await c.command('<receipt action="cancel"></receipt>');
      final rates = await c.taxRates();
      final member = _ref.read(panelMemberProvider);
      for (final command in novitusReceiptCommands(receipt, rates, cashier: member?.name ?? '')) {
        try {
          await c.command(command);
        } catch (_) {
          await c.command('<receipt action="cancel"></receipt>').catchError((_) {});
          rethrow;
        }
      }
      final last = await c.query('<info action="lasttransaction"></info>');
      return novitusAttr(last, 'number') ?? '';
    } finally {
      await c.close();
    }
  }
}

final fiscalPrintingProvider = Provider<FiscalPrinting>(FiscalPrinting.new);

/// Paragony z dnia: rachunek → (kiedy wydrukowany, numer). Do Historii zamówień.
final fiscalReceiptsProvider = FutureProvider.autoDispose.family<Map<String, (DateTime?, String?)>, ({String restaurantId, DateTime day})>(
  (ref, q) {
    ref.watch(ordersLiveProvider(q.restaurantId).select((s) => s.version));
    return ref.watch(repositoryProvider).fiscalReceipts(q.restaurantId, q.day.subtract(const Duration(days: 1)));
  },
);

/// Kasa główna: ten komputer drukuje paragon za każdy opłacony rachunek lokalu zamknięty po włączeniu.
/// Trzyma go `shell.dart`. Błąd pokazuje raz i próbuje znowu przy następnej zmianie zamówień (najwcześniej po minucie).
final fiscalAutoPrintProvider = Provider.autoDispose.family<void, String>((ref, restaurantId) {
  final settings = ref.watch(fiscalSettingsProvider);
  if (!settings.auto || !settings.configured) return;
  final since = settings.autoSince ?? DateTime.now();
  var running = false;
  DateTime? pausedUntil;

  Future<void> drain() async {
    if (running) return;
    if (pausedUntil != null && DateTime.now().isBefore(pausedUntil!)) return;
    running = true;
    try {
      final limit = DateTime.now().subtract(const Duration(hours: 24));
      final ids = await ref.read(repositoryProvider).fiscalPendingIds(restaurantId, since.isAfter(limit) ? since : limit);
      for (final id in ids) {
        if (!ref.mounted) return;
        if (await ref.read(fiscalPrintingProvider).printOrder(id)) {
          Toasts.instance.show('Paragon wydrukowany.', tone: ToastTone.success, icon: AppIcons.receipt);
        }
      }
    } catch (e) {
      pausedUntil = DateTime.now().add(const Duration(minutes: 1));
      Toasts.instance.show('Paragon się nie wydrukował: ${errorText(e)}', tone: ToastTone.error, icon: AppIcons.receipt);
    } finally {
      running = false;
    }
  }

  ref.listen(ordersLiveProvider(restaurantId).select((s) => s.version), (_, _) => unawaited(drain()), fireImmediately: true);
  final timer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(drain()));
  ref.onDispose(timer.cancel);
});
