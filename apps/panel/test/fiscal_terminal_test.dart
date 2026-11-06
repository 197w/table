import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/printing/cp1250.dart';
import 'package:table_panel/features/printing/fiscal_receipt.dart';
import 'package:table_panel/features/printing/novitus_xml.dart';
import 'package:table_panel/features/printing/payment_terminal.dart';
import 'package:table_panel/features/printing/printer_transport.dart';

OrderItem _item(String name, int qty, int price, int vat, {String? variant, OrderItemStatus status = OrderItemStatus.served}) =>
    OrderItem(
      id: name,
      orderId: 'o1',
      name: name,
      variant: variant,
      unitPriceGrosze: price,
      vatRate: vat,
      quantity: qty,
      course: 1,
      status: status,
      createdAt: DateTime(2026, 11, 6, 18),
    );

PanelOrder _order({List<PaymentPart>? payments, int discount = 0, int fee = 0}) => PanelOrder(
  id: 'abcdef12-3456-7890-abcd-ef1234567890',
  openedAt: DateTime(2026, 11, 6, 18),
  status: 'paid',
  kind: OrderKind.delivery,
  number: 12,
  items: [
    _item('Margherita', 2, 3200, 8, variant: '32 cm'),
    _item('Cola "Zero"', 1, 900, 23),
    _item('Lasagne', 1, 4100, 8, status: OrderItemStatus.cancelled),
  ],
  discountGrosze: discount,
  deliveryFeeGrosze: fee,
  payments: payments ?? const [PaymentPart(PaymentMethod.card, 7800)],
);

const _rates = <String, double?>{'A': 23, 'B': 8, 'C': 5, 'D': 0, 'E': null};

void main() {
  test('Windows-1250: polskie znaki tam i z powrotem', () {
    final bytes = encodeCp1250('Zażółć gęślą jaźń ŁÓDŹ');
    expect(bytes, contains(0xB3)); // ł
    expect(bytes, contains(0x9F)); // ź
    expect(decodeCp1250(bytes), 'Zażółć gęślą jaźń ŁÓDŹ');
    expect(decodeCp1250(encodeCp1250('☕')), '?');
  });

  test('paragon z rachunku: aktywne pozycje, dostawa, rabat, płatności i NIP', () {
    final r = fiscalReceiptFor(_order(fee: 700, discount: 700, payments: const [PaymentPart(PaymentMethod.card, 7300)]), nip: '123-456-78-90');
    expect(r.lines.map((l) => l.name), ['Margherita 32 cm', 'Cola "Zero"', 'Dostawa']);
    expect(r.lines.last.vatRate, 8);
    expect(r.totalGrosze, 2 * 3200 + 900 + 700 - 700);
    expect(r.payments.single.type, FiscalPaymentType.card);
    expect(r.nip, '1234567890');
    expect(r.systemNo, 'D12');

    // Płatności niezgodne z kwotą: bez form płatności (drukarka przyjmie całość gotówką).
    final mismatch = fiscalReceiptFor(_order(payments: const [PaymentPart(PaymentMethod.cash, 100)]));
    expect(mismatch.payments, isEmpty);
  });

  test('komendy Novitus XML: litery PTU, nazwy bez cudzysłowu, rabat, płatność, zamknięcie z NIP', () {
    final r = fiscalReceiptFor(_order(discount: 500, payments: const [PaymentPart(PaymentMethod.card, 6800)]), nip: '1234567890');
    final commands = novitusReceiptCommands(r, _rates, cashier: 'Anna');
    expect(commands.first, startsWith('<receipt action="begin"'));
    expect(commands[1], contains('name="Margherita 32 cm" quantity="2" quantityunit="szt." ptu="B" price="32.00"'));
    expect(commands[2], contains('name="Cola \'Zero\'"'));
    expect(commands[2], contains('ptu="A" price="9.00"'));
    expect(commands[3], contains('<discount value="5.00" name="Rabat" type="subtotal" total="73.00"'));
    expect(commands[4], contains('<payment type="card" action="add" value="68.00"'));
    expect(commands.last, contains('action="close" total="68.00" systemno="D12"'));
    expect(commands.last, contains('cashier="Anna" nip="1234567890"'));

    expect(
      () => novitusReceiptCommands(r, const {'A': 23}),
      throwsA(isA<PrinterException>().having((e) => e.message, 'message', contains('8%'))),
    );
  });

  test('stawki PTU z odpowiedzi drukarki', () {
    const reply = '<packet><taxrates action="get"><ptu name="A">23%</ptu><ptu name="B">8.00</ptu>'
        '<ptu name="C">5,00</ptu><ptu name="E">free</ptu><ptu name="G">101</ptu></taxrates></packet>';
    final rates = parseNovitusTaxRates(reply);
    expect(rates, {'A': 23.0, 'B': 8.0, 'C': 5.0, 'E': null});
    expect(novitusLetterFor(8, rates), 'B');
    expect(novitusLetterFor(-1, rates), 'E');
    expect(novitusLetterFor(0, rates), isNull);
  });

  test('rozmowa z drukarką Novitus przez TCP: komendy po kolei, błąd z numerem', () async {
    final received = <String>[];
    var failItems = false;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((client) {
      var buffer = '';
      var lastFailed = false;
      client.listen((data) {
        buffer += decodeCp1250(data);
        while (buffer.contains('</packet>')) {
          final end = buffer.indexOf('</packet>') + '</packet>'.length;
          final packet = buffer.substring(0, end);
          buffer = buffer.substring(end);
          received.add(packet);
          String? reply;
          if (packet.contains('<enq/>')) {
            reply = '<packet><enq fiscal="no" lastcommanderror="${lastFailed ? 'yes' : 'no'}" intransaction="no"/></packet>';
          } else if (packet.contains('<dle/>')) {
            reply = '<packet><dle online="yes" papererror="no" printererror="no"/></packet>';
          } else if (packet.contains('<error action="get"')) {
            reply = '<packet><error action="get" value="1234"></error></packet>';
          } else if (packet.contains('taxrates')) {
            reply = '<packet><taxrates action="get"><ptu name="A">23%</ptu><ptu name="B">8%</ptu></taxrates></packet>';
          } else if (packet.contains('lasttransaction')) {
            reply = '<packet><info action="lasttransaction" state="close" number="57"/></packet>';
          } else {
            lastFailed = failItems && packet.contains('<item');
          }
          if (reply != null) client.add(encodeCp1250(reply));
        }
      });
    });
    addTearDown(server.close);

    final r = fiscalReceiptFor(_order(payments: const [PaymentPart(PaymentMethod.card, 7300)]));
    final c = await NovitusConnection.open('127.0.0.1', server.port);
    expect((await c.status())['online'], 'yes');
    final rates = await c.taxRates();
    for (final command in novitusReceiptCommands(r, rates)) {
      await c.command(command);
    }
    final last = await c.query('<info action="lasttransaction"></info>');
    expect(novitusAttr(last, 'number'), '57');
    await c.close();
    final commands = [for (final p in received) if (!p.contains('<enq/>')) p];
    expect(commands.where((p) => p.contains('<item ')).length, 2);
    expect(commands.indexWhere((p) => p.contains('action="begin"')), lessThan(commands.indexWhere((p) => p.contains('action="close"'))));

    failItems = true;
    final c2 = await NovitusConnection.open('127.0.0.1', server.port);
    await c2.command(novitusReceiptCommands(r, rates).first);
    await expectLater(
      c2.command(novitusReceiptCommands(r, rates)[1]),
      throwsA(isA<PrinterException>().having((e) => e.message, 'message', contains('1234'))),
    );
    await c2.close();
  });

  test('Viva.com: token, sprzedaż, odpytywanie sesji aż do wyniku', () async {
    final calls = <String>[];
    var polls = 0;
    final mock = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}');
      if (req.url.path == '/connect/token') {
        expect(req.headers['Authorization'], startsWith('Basic '));
        expect(req.body, 'grant_type=client_credentials');
        return http.Response(jsonEncode({'access_token': 'tok', 'expires_in': 3600}), 200);
      }
      expect(req.headers['Authorization'], 'Bearer tok');
      if (req.url.path == '/ecr/v1/transactions:sale') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['amount'], 7800);
        expect(body['currencyCode'], '985');
        expect(body['terminalId'], '16000010');
        expect(body['sessionId'], matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
        return http.Response('', 200);
      }
      if (req.url.path.startsWith('/ecr/v1/sessions/')) {
        polls++;
        if (polls < 2) return http.Response('', 202);
        return http.Response(jsonEncode({'success': true, 'message': 'Transaction successful', 'transactionId': 't1'}), 200);
      }
      return http.Response('', 404);
    });
    const s = TerminalSettings(
      provider: TerminalProvider.viva,
      vivaClientId: 'id',
      vivaClientSecret: 'secret',
      vivaTerminalId: '16000010',
    );
    final client = VivaTerminalClient(s, client: mock);
    final statuses = <String>[];
    final result = await client.pay(7800, reference: 'Stolik 4', onStatus: statuses.add, cancel: TerminalCancel());
    expect(result.success, isTrue);
    expect(result.transactionId, 't1');
    expect(calls.first, 'POST /connect/token');
    expect(statuses, contains('Przyłóż albo włóż kartę na terminalu.'));
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('Adyen: żądanie nexo i wynik płatności', () async {
    Map<String, dynamic>? sent;
    final mock = MockClient((req) async {
      expect(req.url.toString(), 'https://device-api-test.adyen.com/v1/merchants/ReveRestaurant/devices/V400m-123456789/sync');
      expect(req.headers['x-API-key'], 'key');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'SaleToPOIResponse': {
            'PaymentResponse': {
              'Response': {'Result': 'Failure', 'ErrorCondition': 'Refusal', 'AdditionalResponse': 'refusalReason=Insufficient%20funds'},
            },
          },
        }),
        200,
      );
    });
    const s = TerminalSettings(
      provider: TerminalProvider.adyen,
      adyenApiKey: 'key',
      adyenMerchant: 'ReveRestaurant',
      adyenPoiid: 'V400m-123456789',
    );
    final result = await AdyenTerminalClient(s, client: mock)
        .pay(4123, reference: 'Stolik 4', onStatus: (_) {}, cancel: TerminalCancel());
    final header = sent!['SaleToPOIRequest']['MessageHeader'] as Map<String, dynamic>;
    expect(header['MessageCategory'], 'Payment');
    expect(header['POIID'], 'V400m-123456789');
    expect((header['ServiceID'] as String).length, 10);
    expect(sent!['SaleToPOIRequest']['PaymentRequest']['PaymentTransaction']['AmountsReq'], {'Currency': 'PLN', 'RequestedAmount': 41.23});
    expect(result.success, isFalse);
    expect(result.message, contains('Insufficient funds'));
  });
}
