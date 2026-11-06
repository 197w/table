import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_panel/data/models.dart';
import 'package:table_panel/features/printing/label_printing.dart';
import 'package:table_panel/features/printing/label_render.dart';
import 'package:table_panel/features/printing/label_template.dart';
import 'package:table_panel/features/printing/printer_commands.dart';

OrderItem _item(String id, String menuId, String name, int qty, {String? variant, List<ItemChange> changes = const []}) =>
    OrderItem(
      id: id,
      orderId: 'o1',
      menuItemId: menuId,
      name: name,
      variant: variant,
      changes: changes,
      unitPriceGrosze: 3000,
      vatRate: 8,
      quantity: qty,
      course: 1,
      status: OrderItemStatus.sent,
      createdAt: DateTime(2026, 11, 6, 18),
    );

TakeawayOrder _order({OrderKind kind = OrderKind.delivery}) => TakeawayOrder(
  id: 'o1',
  kind: kind,
  number: 12,
  stage: TakeawayStage.accepted,
  openedAt: DateTime(2026, 11, 6, 18),
  promisedAt: DateTime(2026, 11, 6, 19, 30),
  customerName: 'Anna Kowalska',
  customerPhone: '+48600100200',
  address: 'ul. Lipowa 12/4, Białystok',
  items: [
    _item('i1', 'pizza', 'Margherita', 2, variant: '32 cm', changes: const [ItemChange('Cebula', extra: false)]),
    _item('i2', 'cola', 'Cola', 1),
  ],
  feeGrosze: 0,
  cash: true,
  paid: false,
);

const _menu = <String, LabelMenuInfo>{
  'pizza': (sectionId: 'pizze', kitchen: true),
  'cola': (sectionId: 'napoje', kitchen: false),
};

const _box = LabelTemplate(
  widthMm: 100,
  heightMm: 50,
  elements: [LabelElement(id: 'b', type: LabelElementType.box, x: 0, y: 0, w: 10, h: 10, fill: true)],
);

void main() {
  setUpAll(() => initializeDateFormatting('pl'));

  test('pola etykiety: wartości, puste pole chowa cały napis, nieznane zostaje', () {
    const values = {'numer': '12', 'godzina': '', 'adres': 'ul. Lipowa 1'};
    expect(resolveLabelText('#{numer}', values), '#12');
    expect(resolveLabelText('na {godzina}', values), '');
    expect(resolveLabelText('{adres} {godzina}', values), 'ul. Lipowa 1');
    expect(resolveLabelText('{cos}', values), '{cos}');
    expect(resolveLabelText('Smacznego!', values), 'Smacznego!');
  });

  test('etykieta na każdą sztukę dania z kuchni (bez napojów), 1/2 i 2/2', () {
    final labels = labelValuesForOrder(_order(), LabelTemplate.standard(), restaurantName: 'REVE', menu: _menu);
    expect(labels, hasLength(2));
    expect(labels.map((l) => l['sztuka']), ['1/2', '2/2']);
    expect(labels.first['danie'], 'Margherita · 32 cm');
    expect(labels.first['dodatki'], 'BEZ cebula');
    expect(labels.first['numer'], '12');
    expect(labels.first['rodzaj'], 'DOSTAWA');
    expect(labels.first['godzina'], '19:30');
    expect(labels.first['adres'], 'ul. Lipowa 12/4, Białystok');
    expect(labels.first['platnosc'], startsWith('Gotówka'));
  });

  test('wybrane działy menu, jedna etykieta na zamówienie i rodzaje zamówień', () {
    final drinks = LabelTemplate.standard().copyWith(sections: ['napoje']);
    expect(labelValuesForOrder(_order(), drinks, restaurantName: '', menu: _menu).map((l) => l['danie']), ['Cola']);

    final bag = LabelTemplate.standard().copyWith(per: LabelPer.order);
    final one = labelValuesForOrder(_order(), bag, restaurantName: '', menu: _menu);
    expect(one, hasLength(1));
    expect(one.single['pozycje'], '2× Margherita · 32 cm\n1× Cola');

    final deliveryOnly = LabelTemplate.standard().copyWith(kinds: {OrderKind.delivery});
    expect(labelValuesForOrder(_order(kind: OrderKind.pickup), deliveryOnly, restaurantName: '', menu: _menu), isEmpty);
    // Przy odbiorze adres jest pusty, nawet gdy zamówienie go ma.
    final pickup = labelValuesForOrder(_order(kind: OrderKind.pickup), LabelTemplate.standard(), restaurantName: '', menu: _menu);
    expect(pickup.first['adres'], '');
    expect(pickup.first['rodzaj'], 'ODBIÓR');
  });

  test('wzór etykiety: zapis i odczyt dają ten sam wzór', () {
    final t = LabelTemplate.standard().copyWith(per: LabelPer.order, sections: ['a']);
    final json = jsonDecode(jsonEncode({
      'width_mm': t.widthMm,
      'height_mm': t.heightMm,
      'per': t.per.name,
      'kinds': [for (final k in t.kinds) k.db],
      'sections': t.sections,
      'elements': [for (final e in t.elements) e.toJson()],
    })) as Map<String, dynamic>;
    expect(LabelTemplate.fromJson(json).signature, t.signature);
    expect(LabelTemplate.fromJson(null).elements, isNotEmpty);
    expect(t.toRpc('r1')['p_kinds'], containsAll(['delivery', 'pickup']));
  });

  testWidgets('punkty etykiety i polecenia TSPL oraz ZPL', (tester) async {
    final raster = (await tester.runAsync(() => rasterizeLabel(_box, const {})))!;
    expect(raster.width, 800);
    expect(raster.height, 400);
    expect(raster.rowBytes, 100);
    expect(raster.isBlack(40, 40), isTrue);
    expect(raster.isBlack(200, 200), isFalse);

    const options = (widthMm: 100, heightMm: 50, darkness: 8, rotate: false, gapMm: 2.0);
    final tspl = tsplJob([raster, raster], options);
    final head = latin1.decode(tspl.sublist(0, 60));
    expect(head, startsWith('SIZE 100 mm,50 mm\r\nGAP 2 mm,0 mm\r\n'));
    final marker = ascii.encode('BITMAP 0,0,100,400,0,');
    final at = _indexOf(tspl, marker);
    expect(at, greaterThan(0));
    // W TSPL 0 to punkt wydrukowany: pierwszy bajt (8 czarnych punktów) to 0x00, bajt z białym polem to 0xFF.
    expect(tspl[at + marker.length], 0x00);
    expect(tspl[at + marker.length + 50], 0xFF);
    expect(RegExp('PRINT 1,1').allMatches(latin1.decode(tspl)).length, 2);

    final zpl = ascii.decode(zplJob([raster], options));
    expect(zpl, startsWith('^XA^PW800^LL400'));
    expect(zpl, contains('^GFA,40000,40000,100,FF'));
    expect(zpl.trim(), endsWith('^XZ'));
  });

  test('odmiana liczby etykiet', () {
    expect(labelCount(1), '1 etykieta');
    expect(labelCount(3), '3 etykiety');
    expect(labelCount(5), '5 etykiet');
    expect(labelCount(12), '12 etykiet');
    expect(labelCount(22), '22 etykiety');
  });
}

int _indexOf(List<int> data, List<int> pattern) {
  for (var i = 0; i <= data.length - pattern.length; i++) {
    var ok = true;
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}
