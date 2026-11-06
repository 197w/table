import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_transport.dart';

// Terminal płatniczy na tym komputerze („Drukarki” → „Terminal”): panel wysyła kwotę rachunku na terminal,
// terminal przyjmuje kartę, a panel zapisuje płatność kartą dopiero po udanej transakcji. Operatorzy z publiczną
// dokumentacją API: Viva.com (Cloud Terminal API, developer.viva.com) i Adyen (Terminal API przez chmurę,
// docs.adyen.com). Klucze wpisuje lokal ze swojego konta u operatora; zostają tylko na tym komputerze.

enum TerminalProvider {
  viva('Viva.com', 'Terminal Viva albo telefon z aplikacją Viva.com Terminal (Tap to Pay)'),
  adyen('Adyen', 'Terminale Adyen (np. V400m, S1F2) z Terminal API w chmurze');

  const TerminalProvider(this.label, this.devices);
  final String label;
  final String devices;

  static TerminalProvider? from(Object? v) => values.where((p) => p.name == v).firstOrNull;
}

class TerminalSettings {
  const TerminalSettings({
    this.provider,
    this.test = true,
    this.vivaClientId = '',
    this.vivaClientSecret = '',
    this.vivaTerminalId = '',
    this.cashRegisterId = 'TABLE-1',
    this.adyenApiKey = '',
    this.adyenMerchant = '',
    this.adyenPoiid = '',
  });

  final TerminalProvider? provider;

  /// Środowisko testowe operatora (Viva demo, Adyen test): bez prawdziwych pieniędzy.
  final bool test;

  final String vivaClientId;
  final String vivaClientSecret;
  final String vivaTerminalId;

  /// Kasa w systemie operatora (Viva: cashRegisterId; Adyen: SaleID).
  final String cashRegisterId;

  final String adyenApiKey;
  final String adyenMerchant;

  /// Terminal Adyen: model i numer seryjny, np. „V400m-123456789”.
  final String adyenPoiid;

  bool get configured => switch (provider) {
    TerminalProvider.viva => vivaClientId.isNotEmpty && vivaClientSecret.isNotEmpty && vivaTerminalId.isNotEmpty,
    TerminalProvider.adyen => adyenApiKey.isNotEmpty && adyenMerchant.isNotEmpty && adyenPoiid.isNotEmpty,
    null => false,
  };

  String get title => switch (provider) {
    TerminalProvider.viva => 'Viva.com · $vivaTerminalId${test ? ' (demo)' : ''}',
    TerminalProvider.adyen => 'Adyen · $adyenPoiid${test ? ' (test)' : ''}',
    null => 'Brak',
  };

  TerminalSettings copyWith({
    TerminalProvider? provider,
    bool clearProvider = false,
    bool? test,
    String? vivaClientId,
    String? vivaClientSecret,
    String? vivaTerminalId,
    String? cashRegisterId,
    String? adyenApiKey,
    String? adyenMerchant,
    String? adyenPoiid,
  }) => TerminalSettings(
    provider: clearProvider ? null : (provider ?? this.provider),
    test: test ?? this.test,
    vivaClientId: vivaClientId ?? this.vivaClientId,
    vivaClientSecret: vivaClientSecret ?? this.vivaClientSecret,
    vivaTerminalId: vivaTerminalId ?? this.vivaTerminalId,
    cashRegisterId: cashRegisterId ?? this.cashRegisterId,
    adyenApiKey: adyenApiKey ?? this.adyenApiKey,
    adyenMerchant: adyenMerchant ?? this.adyenMerchant,
    adyenPoiid: adyenPoiid ?? this.adyenPoiid,
  );

  Map<String, dynamic> toJson() => {
    'provider': provider?.name,
    'test': test,
    'vivaClientId': vivaClientId,
    'vivaClientSecret': vivaClientSecret,
    'vivaTerminalId': vivaTerminalId,
    'cashRegisterId': cashRegisterId,
    'adyenApiKey': adyenApiKey,
    'adyenMerchant': adyenMerchant,
    'adyenPoiid': adyenPoiid,
  };

  factory TerminalSettings.fromJson(Map<String, dynamic> j) => TerminalSettings(
    provider: TerminalProvider.from(j['provider']),
    test: j['test'] != false,
    vivaClientId: j['vivaClientId'] as String? ?? '',
    vivaClientSecret: j['vivaClientSecret'] as String? ?? '',
    vivaTerminalId: j['vivaTerminalId'] as String? ?? '',
    cashRegisterId: j['cashRegisterId'] as String? ?? 'TABLE-1',
    adyenApiKey: j['adyenApiKey'] as String? ?? '',
    adyenMerchant: j['adyenMerchant'] as String? ?? '',
    adyenPoiid: j['adyenPoiid'] as String? ?? '',
  );
}

class TerminalSettingsNotifier extends Notifier<TerminalSettings> {
  static const _key = 'panel_terminal_platniczy';

  @override
  TerminalSettings build() {
    unawaited(_load());
    return const TerminalSettings();
  }

  Future<void> _load() async {
    try {
      final raw = await SharedPreferencesAsync().getString(_key);
      if (raw != null) state = TerminalSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Bez zapisanych ustawień.
    }
  }

  Future<void> set(TerminalSettings value) async {
    state = value;
    try {
      await SharedPreferencesAsync().setString(_key, jsonEncode(value.toJson()));
    } catch (_) {
      // Działa do zamknięcia panelu.
    }
  }
}

final terminalSettingsProvider = NotifierProvider<TerminalSettingsNotifier, TerminalSettings>(TerminalSettingsNotifier.new);

/// Wynik płatności na terminalu.
typedef TerminalResult = ({bool success, String message, String? transactionId});

/// Przerwanie płatności z okna „Zapłać kartą” (obsługa kliknęła „Przerwij”).
class TerminalCancel {
  bool _requested = false;
  void Function()? _onCancel;

  bool get requested => _requested;

  void cancel() {
    if (_requested) return;
    _requested = true;
    _onCancel?.call();
  }
}

String _uuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0F) | 0x40;
  b[8] = (b[8] & 0x3F) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String _serviceId() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789';
  final r = Random.secure();
  return List.generate(10, (_) => chars[r.nextInt(chars.length)]).join();
}

abstract class TerminalClient {
  /// Płatność [grosze] na terminalu; [onStatus] dostaje napisy do okna płatności.
  Future<TerminalResult> pay(int grosze, {required String reference, required void Function(String) onStatus, required TerminalCancel cancel});

  /// Sprawdzenie połączenia i terminala (napis do pokazania).
  Future<String> check();
}

/// Viva.com Cloud Terminal API: token OAuth (dane „POS APIs” z konta Viva), `transactions:sale`, potem odpytywanie
/// sesji, aż terminal odda wynik. Przerwanie: DELETE sesji (działa, dopóki karta nie została odczytana).
class VivaTerminalClient implements TerminalClient {
  VivaTerminalClient(this.s, {http.Client? client}) : _http = client ?? http.Client();

  final TerminalSettings s;
  final http.Client _http;
  String? _token;
  DateTime _tokenUntil = DateTime(2000);

  String get _accounts => s.test ? 'https://demo-accounts.vivapayments.com' : 'https://accounts.vivapayments.com';
  String get _api => s.test ? 'https://demo-api.vivapayments.com' : 'https://api.vivapayments.com';

  Future<Map<String, String>> _headers() async {
    if (_token == null || DateTime.now().isAfter(_tokenUntil)) {
      final basic = base64Encode(utf8.encode('${s.vivaClientId}:${s.vivaClientSecret}'));
      final r = await _http
          .post(
            Uri.parse('$_accounts/connect/token'),
            headers: {'Authorization': 'Basic $basic', 'Content-Type': 'application/x-www-form-urlencoded'},
            body: 'grant_type=client_credentials',
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw PrinterException('Viva.com nie przyjęła danych logowania (HTTP ${r.statusCode}). Sprawdź Client ID i Secret „POS APIs”.');
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      _token = j['access_token'] as String?;
      _tokenUntil = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?)?.toInt() ?? 3600) - 60));
    }
    return {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'};
  }

  @override
  Future<String> check() async {
    final r = await _http
        .post(Uri.parse('$_api/ecr/v1/devices:search'), headers: await _headers(), body: jsonEncode({'statusId': 1}))
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw PrinterException('Viva.com: lista terminali niedostępna (HTTP ${r.statusCode}).');
    final ids = [for (final d in jsonDecode(r.body) as List) '${(d as Map)['terminalId']}'];
    if (!ids.contains(s.vivaTerminalId)) {
      throw PrinterException(
        'Viva.com nie widzi aktywnego terminala ${s.vivaTerminalId}. Aktywne: ${ids.isEmpty ? 'brak' : ids.join(', ')}.',
      );
    }
    return 'Połączono z Viva.com. Terminal ${s.vivaTerminalId} jest aktywny.';
  }

  @override
  Future<TerminalResult> pay(int grosze, {required String reference, required void Function(String) onStatus, required TerminalCancel cancel}) async {
    final session = _uuid();
    final sale = await _http
        .post(
          Uri.parse('$_api/ecr/v1/transactions:sale'),
          headers: await _headers(),
          body: jsonEncode({
            'sessionId': session,
            'terminalId': s.vivaTerminalId,
            'cashRegisterId': s.cashRegisterId,
            'amount': grosze,
            // PLN według ISO 4217 (kod liczbowy).
            'currencyCode': '985',
            'merchantReference': reference,
            'customerTrns': reference,
            'tipAmount': 0,
            'preauth': false,
            'maxInstalments': 0,
            'showTransactionResult': true,
            'showReceipt': true,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (sale.statusCode != 200) {
      throw PrinterException('Viva.com nie przyjęła płatności (HTTP ${sale.statusCode}). ${_short(sale.body)}');
    }
    onStatus('Przyłóż albo włóż kartę na terminalu.');
    cancel._onCancel = () async {
      onStatus('Przerywam płatność…');
      try {
        await _http.delete(
          Uri.parse('$_api/ecr/v1/sessions/$session?cashRegisterId=${Uri.encodeQueryComponent(s.cashRegisterId)}'),
          headers: await _headers(),
        );
      } catch (_) {
        // Wynik i tak przyjdzie z odpytywania sesji.
      }
    };
    final until = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final r = await _http.get(Uri.parse('$_api/ecr/v1/sessions/$session'), headers: await _headers()).timeout(
        const Duration(seconds: 20),
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final ok = j['success'] == true;
        return (
          success: ok,
          message: (j['message'] as String?)?.trim().isNotEmpty == true
              ? j['message'] as String
              : (ok ? 'Zapłacono kartą.' : (cancel.requested ? 'Płatność przerwana.' : 'Płatność odrzucona.')),
          transactionId: j['transactionId'] as String?,
        );
      }
      // 202: terminal jeszcze pracuje; 404: sesja jeszcze nie dotarła.
      if (r.statusCode != 202 && r.statusCode != 404) {
        throw PrinterException('Viva.com: błąd odczytu płatności (HTTP ${r.statusCode}).');
      }
    }
    throw const PrinterException('Terminal nie odpowiedział w 4 minuty. Sprawdź na terminalu, czy płatność przeszła.');
  }
}

/// Adyen Terminal API przez chmurę (Cloud device API): żądanie nexo `PaymentRequest` na
/// `/v1/merchants/{konto}/devices/{POIID}/sync` z nagłówkiem `x-API-key`; odpowiedź przychodzi w tym samym
/// połączeniu (do 150 s), a po przekroczeniu czasu pytamy o stan transakcji (`TransactionStatusRequest`).
class AdyenTerminalClient implements TerminalClient {
  AdyenTerminalClient(this.s, {http.Client? client}) : _http = client ?? http.Client();

  final TerminalSettings s;
  final http.Client _http;

  String get _host => s.test ? 'https://device-api-test.adyen.com' : 'https://device-api-live.adyen.com';

  Uri _endpoint(String mode) => Uri.parse(
    '$_host/v1/merchants/${Uri.encodeComponent(s.adyenMerchant)}/devices/${Uri.encodeComponent(s.adyenPoiid)}/$mode',
  );

  Map<String, String> get _headers => {'x-API-key': s.adyenApiKey, 'Content-Type': 'application/json'};

  Map<String, dynamic> _header(String category, String serviceId) => {
    'ProtocolVersion': '3.0',
    'MessageClass': 'Service',
    'MessageCategory': category,
    'MessageType': 'Request',
    'SaleID': s.cashRegisterId,
    'ServiceID': serviceId,
    'POIID': s.adyenPoiid,
  };

  Future<Map<String, dynamic>> _post(String mode, Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 30)}) async {
    final r = await _http.post(_endpoint(mode), headers: _headers, body: jsonEncode(body)).timeout(timeout);
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const PrinterException('Adyen nie przyjął klucza API (potrzebna rola „Cloud Device API”).');
    }
    if (r.statusCode != 200) throw PrinterException('Adyen: błąd HTTP ${r.statusCode}. ${_short(r.body)}');
    if (r.body.trim().isEmpty || r.body.trim() == 'ok') return const {};
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Terminal niedostępny: Adyen odsyła powiadomienie zamiast odpowiedzi.
  static String? _event(Map<String, dynamic> json) {
    final event = (json['SaleToPOIRequest'] as Map?)?['EventNotification'] as Map?;
    if (event == null) return null;
    return 'Terminal: ${event['EventToNotify'] ?? 'zdarzenie'}${event['EventDetails'] == null ? '' : ' (${event['EventDetails']})'}.';
  }

  static TerminalResult _paymentResult(Map<String, dynamic>? payment) {
    final response = (payment?['Response'] as Map?) ?? const {};
    final ok = response['Result'] == 'Success';
    final additional = Uri.splitQueryString('${response['AdditionalResponse'] ?? ''}');
    final reason = additional['refusalReason'] ?? additional['message'] ?? response['ErrorCondition'];
    final poi = ((payment?['POIData'] as Map?)?['POITransactionID'] as Map?)?['TransactionID'] as String?;
    return (
      success: ok,
      message: ok ? 'Zapłacono kartą.' : 'Płatność nieudana${reason == null ? '' : ': $reason'}.',
      transactionId: poi,
    );
  }

  @override
  Future<String> check() async {
    final json = await _post('sync', {
      'SaleToPOIRequest': {
        'MessageHeader': _header('Diagnosis', _serviceId()),
        'DiagnosisRequest': {'HostDiagnosisFlag': false},
      },
    });
    final event = _event(json);
    if (event != null) throw PrinterException(event);
    final result = ((json['SaleToPOIResponse'] as Map?)?['DiagnosisResponse'] as Map?)?['Response']?['Result'];
    if (result != 'Success') throw PrinterException('Adyen: terminal ${s.adyenPoiid} nie odpowiada ($result).');
    return 'Połączono z Adyen. Terminal ${s.adyenPoiid} odpowiada.';
  }

  @override
  Future<TerminalResult> pay(int grosze, {required String reference, required void Function(String) onStatus, required TerminalCancel cancel}) async {
    final serviceId = _serviceId();
    cancel._onCancel = () async {
      onStatus('Przerywam płatność…');
      try {
        await _post('async', {
          'SaleToPOIRequest': {
            'MessageHeader': _header('Abort', _serviceId()),
            'AbortRequest': {
              'AbortReason': 'MerchantAbort',
              'MessageReference': {'MessageCategory': 'Payment', 'SaleID': s.cashRegisterId, 'ServiceID': serviceId},
            },
          },
        });
      } catch (_) {
        // Wynik płatności i tak przyjdzie (Failure / Aborted).
      }
    };
    onStatus('Przyłóż albo włóż kartę na terminalu.');
    Map<String, dynamic> json;
    try {
      json = await _post('sync', {
        'SaleToPOIRequest': {
          'MessageHeader': _header('Payment', serviceId),
          'PaymentRequest': {
            'SaleData': {
              'SaleTransactionID': {'TransactionID': reference, 'TimeStamp': DateTime.now().toUtc().toIso8601String()},
            },
            'PaymentTransaction': {
              'AmountsReq': {'Currency': 'PLN', 'RequestedAmount': grosze / 100},
            },
          },
        },
      }, timeout: const Duration(seconds: 170));
    } on TimeoutException {
      onStatus('Sprawdzam wynik płatności…');
      final status = await _post('sync', {
        'SaleToPOIRequest': {
          'MessageHeader': _header('TransactionStatus', _serviceId()),
          'TransactionStatusRequest': {
            'MessageReference': {'MessageCategory': 'Payment', 'SaleID': s.cashRegisterId, 'ServiceID': serviceId},
          },
        },
      });
      final body = (((status['SaleToPOIResponse'] as Map?)?['TransactionStatusResponse'] as Map?)?['RepeatedMessageResponse']
          as Map?)?['RepeatedResponseMessageBody'] as Map?;
      if (body == null) {
        throw const PrinterException('Terminal nie oddał wyniku. Sprawdź na terminalu, czy płatność przeszła.');
      }
      return _paymentResult(body['PaymentResponse'] as Map<String, dynamic>?);
    }
    final event = _event(json);
    if (event != null) throw PrinterException(event);
    return _paymentResult((json['SaleToPOIResponse'] as Map?)?['PaymentResponse'] as Map<String, dynamic>?);
  }
}

String _short(String body) => body.length > 160 ? '${body.substring(0, 160)}…' : body;

/// Klient terminala z ustawień tego komputera. Null: terminal nie jest ustawiony.
TerminalClient? terminalClientFor(TerminalSettings s) {
  if (!s.configured) return null;
  return switch (s.provider!) {
    TerminalProvider.viva => VivaTerminalClient(s),
    TerminalProvider.adyen => AdyenTerminalClient(s),
  };
}

/// Klient trzymany między płatnościami (token Viva ważny godzinę).
final terminalClientProvider = Provider<TerminalClient?>((ref) => terminalClientFor(ref.watch(terminalSettingsProvider)));
