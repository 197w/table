import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'cp1250.dart';
import 'fiscal_receipt.dart';
import 'printer_transport.dart';

// Protokół XML drukarek fiskalnych Novitus (publiczny opis „Description of XML communication protocol” 1.0.2,
// novitus.pl/file/get/701; nazwy atrybutów jak w działającej bibliotece litex.novitus_xml): każda komenda to pakiet
// `<packet>…</packet>` w kodowaniu Windows-1250 (najwyżej 5000 bajtów), przez sieć bez sumy kontrolnej.
// Po każdej komendzie `<enq/>` mówi, czy się udała (`lastcommanderror`), a `<error action="get"/>` daje numer błędu.

String _attr(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    // Znaki zabronione w wartościach pakietu: cudzysłów (0x22) i DEL (0x7F).
    .replaceAll('"', "'")
    .replaceAll('\u007F', '')
    .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
    .trim();

String _money(int grosze) {
  final sign = grosze < 0 ? '-' : '';
  final abs = grosze.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

String novitusPacket(String command) => '<packet>$command</packet>';

String novitusPaymentType(FiscalPaymentType t) => switch (t) {
  FiscalPaymentType.cash => 'cash',
  FiscalPaymentType.card => 'card',
  FiscalPaymentType.voucher => 'voucher',
  FiscalPaymentType.transfer => 'transfer',
  FiscalPaymentType.other => 'transfer',
};

/// Stawki PTU drukarki z odpowiedzi `<taxrates action="get">`: litera → procent (null: zwolniona „free”).
/// Stawki nieaktywne (np. 100 i więcej) pomijamy.
Map<String, double?> parseNovitusTaxRates(String reply) {
  final out = <String, double?>{};
  for (final m in RegExp(r'<ptu\s+name\s*=\s*"\s*([A-G])\s*"\s*>([^<]*)</ptu>').allMatches(reply)) {
    final raw = m[2]!.trim().toLowerCase();
    if (raw.startsWith('free') || raw == 'zw' || raw.startsWith('zw')) {
      out[m[1]!] = null;
      continue;
    }
    final v = double.tryParse(raw.replaceAll('%', '').replaceAll(',', '.').trim());
    if (v != null && v >= 0 && v < 100) out[m[1]!] = v;
  }
  return out;
}

/// Litera PTU dla stawki VAT z menu (23, 8, 5, 0; ujemna: zwolniona).
String? novitusLetterFor(int vatRate, Map<String, double?> rates) {
  for (final e in rates.entries) {
    if (vatRate < 0 ? e.value == null : (e.value != null && (e.value! - vatRate).abs() < 0.01)) return e.key;
  }
  return null;
}

/// Komendy paragonu po kolei (każda w osobnym pakiecie): początek, pozycje, rabat do sumy, płatności, zamknięcie.
List<String> novitusReceiptCommands(FiscalReceipt r, Map<String, double?> rates, {String cashier = ''}) {
  final commands = <String>['<receipt action="begin" mode="online" pharmaceutical="no"></receipt>'];
  for (final l in r.lines) {
    final letter = novitusLetterFor(l.vatRate, rates);
    if (letter == null) {
      throw PrinterException(
        'Drukarka fiskalna nie ma stawki VAT ${l.vatRate < 0 ? 'zw.' : '${l.vatRate}%'} (pozycja „${l.name}”). '
        'Stawki ustawia serwis drukarki.',
      );
    }
    var name = _attr(l.name);
    if (name.length > 40) name = name.substring(0, 40).trim();
    if (name.length < 3) name = name.padRight(3, '.');
    commands.add(
      '<item name="$name" quantity="${l.quantity}" quantityunit="szt." ptu="$letter" '
      'price="${_money(l.unitGrosze)}" plu="" action="sale" recipe="" charge="" description=""></item>',
    );
  }
  if (r.discountGrosze > 0) {
    commands.add(
      '<discount value="${_money(r.discountGrosze)}" name="Rabat" type="subtotal" '
      'total="${_money(r.linesGrosze)}" action="discount"></discount>',
    );
  }
  for (final p in r.payments) {
    commands.add(
      '<payment type="${novitusPaymentType(p.type)}" action="add" value="${_money(p.grosze)}" '
      'rate="1" mode="payment" name=""></payment>',
    );
  }
  final safeCashier = _attr(cashier);
  commands.add(
    '<receipt action="close" total="${_money(r.totalGrosze)}" systemno="${_attr(r.systemNo)}" checkout="1" '
    'cashier="${safeCashier.length > 31 ? safeCashier.substring(0, 31) : safeCashier}"'
    '${r.nip == null ? '' : ' nip="${r.nip}"'}></receipt>',
  );
  return commands;
}

/// Wydruk niefiskalny (test połączenia): kilka linii z nagłówkiem „Wydruk niefiskalny”.
String novitusNonFiscal(List<String> lines) => '<nonfiscalprintout systemno="" nonfiscalheader="yes">'
    '${[for (final l in lines) '<line>${_attr(l)}</line>'].join()}</nonfiscalprintout>';

/// Wartość atrybutu z odpowiedzi drukarki, np. `lastcommanderror` z `<enq …/>`.
String? novitusAttr(String reply, String name) =>
    RegExp('$name\\s*=\\s*"([^"]*)"').firstMatch(reply)?[1]?.trim();

/// Połączenie z drukarką Novitus przez sieć (TCP). Jedno połączenie na jeden paragon.
class NovitusConnection {
  NovitusConnection._(this._socket) {
    _socket.listen(_buffer.addAll, onDone: () => _closed = true, onError: (_) => _closed = true);
  }

  final Socket _socket;
  final _buffer = <int>[];
  bool _closed = false;

  static Future<NovitusConnection> open(String host, int port) async {
    try {
      final socket = await Socket.connect(host.trim(), port, timeout: const Duration(seconds: 5));
      return NovitusConnection._(socket);
    } on SocketException {
      throw PrinterException(
        'Drukarka fiskalna $host:$port nie odpowiada. Sprawdź, czy jest włączona, w tej samej sieci i z protokołem XML.',
      );
    }
  }

  Future<void> close() async {
    await _socket.close().catchError((_) => _socket);
    _socket.destroy();
  }

  void _write(String command) {
    if (_closed) throw const PrinterException('Drukarka fiskalna zerwała połączenie.');
    final bytes = encodeCp1250(novitusPacket(command));
    if (bytes.length > 5000) throw const PrinterException('Za długa komenda dla drukarki fiskalnej.');
    _socket.add(bytes);
  }

  /// Komenda z odpowiedzią: czeka na `</packet>` (najwyżej [timeout]).
  Future<String> query(String command, {Duration timeout = const Duration(seconds: 6)}) async {
    _buffer.clear();
    _write(command);
    await _socket.flush();
    final end = encodeCp1250('</packet>');
    final until = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(until)) {
      final at = _indexOf(_buffer, end);
      if (at >= 0) {
        final reply = decodeCp1250(_buffer.sublist(0, at + end.length));
        _buffer.removeRange(0, at + end.length);
        return reply;
      }
      if (_closed) break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    throw const PrinterException('Drukarka fiskalna nie odpowiedziała na czas.');
  }

  /// Komenda bez odpowiedzi, potem sprawdzenie błędu (`<enq/>`, przy błędzie numer z `<error action="get"/>`).
  Future<void> command(String command) async {
    _write(command);
    await _socket.flush();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final enq = await query('<enq/>');
    if (novitusAttr(enq, 'lastcommanderror') == 'yes') {
      final err = await query('<error action="get" value=""></error>');
      throw PrinterException('Drukarka fiskalna zgłosiła błąd ${novitusAttr(err, 'value') ?? '?'}. ${_hint(command)}');
    }
  }

  String _hint(String command) {
    if (command.startsWith('<receipt action="close"')) return 'Sprawdź kwotę i formy płatności.';
    if (command.startsWith('<item')) return 'Sprawdź nazwę, cenę i stawkę VAT pozycji.';
    return 'Numer błędu opisuje instrukcja drukarki.';
  }

  Future<Map<String, String?>> status() async {
    final dle = await query('<dle/>');
    final enq = await query('<enq/>');
    return {
      'online': novitusAttr(dle, 'online'),
      'papererror': novitusAttr(dle, 'papererror'),
      'printererror': novitusAttr(dle, 'printererror'),
      'fiscal': novitusAttr(enq, 'fiscal'),
      'intransaction': novitusAttr(enq, 'intransaction'),
    };
  }

  Future<Map<String, double?>> taxRates() async =>
      parseNovitusTaxRates(await query('<taxrates action="get"></taxrates>'));
}

int _indexOf(List<int> data, Uint8List pattern) {
  outer:
  for (var i = 0; i <= data.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}
