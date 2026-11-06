import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';

// Wygląd etykiety na pudełka i torby zamówień na wynos (0077, `label_templates`): rozmiar w milimetrach i elementy
// (tekst z polami w klamrach, linia, ramka, kod QR, logo lokalu). Wspólny dla wszystkich komputerów lokalu.

/// Rodzaj elementu etykiety.
enum LabelElementType {
  text('Tekst', AppIcons.textT),
  line('Linia', AppIcons.lineSegment),
  box('Ramka', AppIcons.rectangle),
  qr('Kod QR', AppIcons.qrCode),
  logo('Logo lokalu', AppIcons.image);

  const LabelElementType(this.label, this.icon);
  final String label;
  final AppIconData icon;

  static LabelElementType from(Object? value) =>
      values.firstWhere((t) => t.name == value, orElse: () => LabelElementType.text);
}

enum LabelAlign {
  left(TextAlign.left, 'Do lewej', AppIcons.textAlignLeft),
  center(TextAlign.center, 'Do środka', AppIcons.textAlignCenter),
  right(TextAlign.right, 'Do prawej', AppIcons.textAlignRight);

  const LabelAlign(this.textAlign, this.label, this.icon);
  final TextAlign textAlign;
  final String label;
  final AppIconData icon;

  static LabelAlign from(Object? value) => values.firstWhere((a) => a.name == value, orElse: () => LabelAlign.left);
}

/// Jedna etykieta na każdą sztukę dania (pudełko pizzy) albo na całe zamówienie (torba).
enum LabelPer {
  item('Każde danie'),
  order('Całe zamówienie');

  const LabelPer(this.label);
  final String label;

  static LabelPer from(Object? value) => value == 'order' ? LabelPer.order : LabelPer.item;
}

double _num(Object? v, double fallback) => v is num ? v.toDouble() : fallback;

/// Milimetry zaokrąglone do 0,1 mm, żeby zapis był krótki i porównanie szkicu działało.
double roundMm(double v) => (v * 10).roundToDouble() / 10;

@immutable
class LabelElement {
  const LabelElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.text = '',
    this.size = 12,
    this.bold = false,
    this.align = LabelAlign.left,
    this.invert = false,
    this.fit = true,
    this.stroke = 0.4,
    this.fill = false,
  });

  final String id;
  final LabelElementType type;

  /// Położenie i rozmiar w milimetrach od lewego górnego rogu etykiety.
  final double x;
  final double y;
  final double w;
  final double h;

  /// Tekst z polami w klamrach, np. „#{numer}” (tekst i kod QR).
  final String text;

  /// Wielkość czcionki w punktach (1 pt = 0,353 mm).
  final double size;
  final bool bold;
  final LabelAlign align;

  /// Biały napis na czarnym tle.
  final bool invert;

  /// Mniejsza czcionka, gdy tekst nie mieści się w polu (długie nazwy dań i adresy).
  final bool fit;

  /// Grubość obrysu ramki w milimetrach.
  final double stroke;

  /// Ramka wypełniona na czarno.
  final bool fill;

  Rect get rect => Rect.fromLTWH(x, y, w, h);

  LabelElement copyWith({
    String? id,
    double? x,
    double? y,
    double? w,
    double? h,
    String? text,
    double? size,
    bool? bold,
    LabelAlign? align,
    bool? invert,
    bool? fit,
    double? stroke,
    bool? fill,
  }) => LabelElement(
    id: id ?? this.id,
    type: type,
    x: roundMm(x ?? this.x),
    y: roundMm(y ?? this.y),
    w: roundMm(w ?? this.w),
    h: roundMm(h ?? this.h),
    text: text ?? this.text,
    size: size ?? this.size,
    bold: bold ?? this.bold,
    align: align ?? this.align,
    invert: invert ?? this.invert,
    fit: fit ?? this.fit,
    stroke: stroke ?? this.stroke,
    fill: fill ?? this.fill,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
    if (type == LabelElementType.text || type == LabelElementType.qr) 'text': text,
    if (type == LabelElementType.text) ...{
      'size': size,
      'bold': bold,
      'align': align.name,
      'invert': invert,
      'fit': fit,
    },
    if (type == LabelElementType.box) ...{'stroke': stroke, 'fill': fill},
  };

  factory LabelElement.fromJson(Map<String, dynamic> json) => LabelElement(
    id: json['id'] as String? ?? newLabelElementId(),
    type: LabelElementType.from(json['type']),
    x: _num(json['x'], 0),
    y: _num(json['y'], 0),
    w: _num(json['w'], 20),
    h: _num(json['h'], 8),
    text: json['text'] as String? ?? '',
    size: _num(json['size'], 12),
    bold: json['bold'] == true,
    align: LabelAlign.from(json['align']),
    invert: json['invert'] == true,
    fit: json['fit'] != false,
    stroke: _num(json['stroke'], 0.4),
    fill: json['fill'] == true,
  );
}

int _idCounter = 0;

/// Krótki identyfikator elementu (wystarczy unikalny w jednej etykiecie).
String newLabelElementId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idCounter++).toRadixString(36)}';

@immutable
class LabelTemplate {
  const LabelTemplate({
    required this.widthMm,
    required this.heightMm,
    required this.elements,
    this.per = LabelPer.item,
    this.kinds = const {OrderKind.delivery, OrderKind.pickup},
    this.sections = const [],
    this.saved = true,
  });

  final int widthMm;
  final int heightMm;
  final List<LabelElement> elements;
  final LabelPer per;

  /// Rodzaje zamówień z etykietą: dostawa i odbiór osobisty.
  final Set<OrderKind> kinds;

  /// Działy menu z etykietą. Puste: wszystkie dania, które robi kuchnia.
  final List<String> sections;

  /// Wzór zapisany w bazie (false: lokal jeszcze go nie zapisał, to domyślny wzór).
  final bool saved;

  static const minWidth = 20;
  static const maxWidth = 110;
  static const minHeight = 15;
  static const maxHeight = 200;

  LabelTemplate copyWith({
    int? widthMm,
    int? heightMm,
    List<LabelElement>? elements,
    LabelPer? per,
    Set<OrderKind>? kinds,
    List<String>? sections,
  }) => LabelTemplate(
    widthMm: widthMm ?? this.widthMm,
    heightMm: heightMm ?? this.heightMm,
    elements: elements ?? this.elements,
    per: per ?? this.per,
    kinds: kinds ?? this.kinds,
    sections: sections ?? this.sections,
    saved: saved,
  );

  /// Ten sam wygląd i zasady (do sprawdzania niezapisanych zmian).
  String get signature => jsonEncode({
    'w': widthMm,
    'h': heightMm,
    'per': per.name,
    'kinds': [for (final k in OrderKind.values) if (kinds.contains(k)) k.db],
    'sections': [...sections]..sort(),
    'elements': [for (final e in elements) e.toJson()],
  });

  factory LabelTemplate.fromJson(Map<String, dynamic>? json) {
    if (json == null) return LabelTemplate.standard();
    return LabelTemplate(
      widthMm: (json['width_mm'] as num?)?.toInt() ?? 100,
      heightMm: (json['height_mm'] as num?)?.toInt() ?? 50,
      per: LabelPer.from(json['per']),
      kinds: {for (final k in json['kinds'] as List? ?? const ['delivery', 'pickup']) OrderKind.from(k)}
        ..remove(OrderKind.dineIn),
      sections: [for (final s in json['sections'] as List? ?? const []) s as String],
      elements: [
        for (final e in json['elements'] as List? ?? const [])
          if (e is Map<String, dynamic>) LabelElement.fromJson(e),
      ],
    );
  }

  /// Parametry `panel_save_label_template`.
  Map<String, dynamic> toRpc(String restaurantId) => {
    'p_restaurant_id': restaurantId,
    'p_width_mm': widthMm,
    'p_height_mm': heightMm,
    'p_per': per.name,
    'p_kinds': [for (final k in kinds) k.db],
    'p_sections': sections,
    'p_elements': [for (final e in elements) e.toJson()],
  };

  /// Domyślny wzór 100 × 50 mm na pudełko pizzy: duży numer, która sztuka, rodzaj i godzina, danie z dodatkami,
  /// klient z telefonem i adres.
  factory LabelTemplate.standard() => const LabelTemplate(
    widthMm: 100,
    heightMm: 50,
    saved: false,
    elements: [
      LabelElement(id: 'numer', type: LabelElementType.text, x: 3, y: 2, w: 34, h: 13, text: '#{numer}', size: 30, bold: true),
      LabelElement(id: 'sztuka', type: LabelElementType.text, x: 37, y: 4, w: 18, h: 9, text: '{sztuka}', size: 14, bold: true),
      LabelElement(
        id: 'rodzaj',
        type: LabelElementType.text,
        x: 61,
        y: 3,
        w: 36,
        h: 6.5,
        text: '{rodzaj}',
        size: 11,
        bold: true,
        align: LabelAlign.center,
        invert: true,
      ),
      LabelElement(
        id: 'godzina',
        type: LabelElementType.text,
        x: 61,
        y: 10,
        w: 36,
        h: 5,
        text: 'na {godzina}',
        size: 11,
        align: LabelAlign.right,
      ),
      LabelElement(id: 'linia1', type: LabelElementType.line, x: 3, y: 16, w: 94, h: 0.4),
      LabelElement(id: 'danie', type: LabelElementType.text, x: 3, y: 17.5, w: 94, h: 8, text: '{danie}', size: 17, bold: true),
      LabelElement(id: 'dodatki', type: LabelElementType.text, x: 3, y: 25.5, w: 94, h: 9.5, text: '{dodatki}', size: 10),
      LabelElement(id: 'linia2', type: LabelElementType.line, x: 3, y: 36, w: 94, h: 0.4),
      LabelElement(id: 'klient', type: LabelElementType.text, x: 3, y: 37.5, w: 66, h: 4.8, text: '{klient} · {telefon}', size: 9, bold: true),
      LabelElement(id: 'adres', type: LabelElementType.text, x: 3, y: 42.5, w: 66, h: 5, text: '{adres}', size: 9),
      LabelElement(
        id: 'lokal',
        type: LabelElementType.text,
        x: 70,
        y: 42.5,
        w: 27,
        h: 5,
        text: '{lokal}',
        size: 8,
        align: LabelAlign.right,
      ),
    ],
  );
}

/// Pole do wstawienia w tekst etykiety: klucz w klamrach, nazwa w edytorze i przykład.
typedef LabelField = ({String key, String label});

const labelFields = <LabelField>[
  (key: 'numer', label: 'Numer zamówienia'),
  (key: 'sztuka', label: 'Która sztuka (1/3)'),
  (key: 'danie', label: 'Danie z wariantem'),
  (key: 'dodatki', label: 'Dodatki i zmiany'),
  (key: 'pozycje', label: 'Wszystkie dania'),
  (key: 'rodzaj', label: 'Dostawa / odbiór'),
  (key: 'godzina', label: 'Na którą godzinę'),
  (key: 'data', label: 'Data'),
  (key: 'klient', label: 'Klient'),
  (key: 'telefon', label: 'Telefon'),
  (key: 'adres', label: 'Adres dostawy'),
  (key: 'uwagi', label: 'Uwagi do zamówienia'),
  (key: 'platnosc', label: 'Płatność'),
  (key: 'kwota', label: 'Kwota'),
  (key: 'lokal', label: 'Nazwa lokalu'),
];

final _fieldPattern = RegExp(r'\{([a-z_]+)\}');

/// Tekst elementu z wartościami pól. Element, którego wszystkie pola są puste (np. adres przy odbiorze),
/// znika w całości, razem ze stałym tekstem obok („na {godzina}” bez godziny).
String resolveLabelText(String text, Map<String, String> values) {
  var fields = 0;
  var filled = 0;
  final out = text.replaceAllMapped(_fieldPattern, (m) {
    final value = values[m[1]];
    if (value == null) return m[0]!;
    fields++;
    if (value.isNotEmpty) filled++;
    return value;
  });
  if (fields > 0 && filled == 0) return '';
  return out.trim();
}

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';
String _date(DateTime t) => '${t.toLocal().day}.${_two(t.toLocal().month)}.${t.toLocal().year}';

/// Dane dań menu potrzebne etykiecie: dział i czy robi je kuchnia.
typedef LabelMenuInfo = ({String sectionId, bool kitchen});

Map<String, LabelMenuInfo> labelMenuInfo(List<MenuSection> menu) => {
  for (final s in menu)
    for (final i in s.items) i.id: (sectionId: s.id, kitchen: i.showInKitchen),
};

/// Czy pozycja dostaje własną etykietę: wybrane działy menu, a bez wyboru wszystko, co robi kuchnia.
bool labelForItem(LabelTemplate t, OrderItem item, Map<String, LabelMenuInfo> menu) {
  final info = item.menuItemId == null ? null : menu[item.menuItemId];
  if (t.sections.isNotEmpty) return info != null && t.sections.contains(info.sectionId);
  return info?.kitchen ?? true;
}

/// Wartości pól wspólne dla całego zamówienia.
Map<String, String> _orderValues(TakeawayOrder o, String restaurantName) {
  final delivery = o.kind == OrderKind.delivery;
  final when = o.scheduledFor ?? o.promisedAt;
  final person = o.personName;
  return {
    'numer': '${o.number}',
    'rodzaj': delivery ? 'DOSTAWA' : 'ODBIÓR',
    'godzina': when == null ? '' : _hm(when),
    'data': _date(o.scheduledFor ?? o.openedAt),
    'klient': o.company == null ? o.customerName : [o.company!, ?person].join(' · '),
    'telefon': Fmt.phone(o.customerPhone),
    'adres': delivery ? (o.address ?? '') : '',
    'uwagi': [?o.note, if (delivery && o.addressNote != null) 'Do adresu: ${o.addressNote}'].join(' · '),
    'platnosc': o.payOnDelivery
        ? '${o.cash ? 'Gotówka' : 'Karta'}: ${Fmt.price(o.totalGrosze)}'
        : 'Opłacone',
    'kwota': Fmt.price(o.totalGrosze),
    'lokal': restaurantName,
    'pozycje': [
      for (final i in o.active) '${i.quantity}× ${[i.name, ?i.variant].join(' · ')}',
    ].join('\n'),
  };
}

String _dish(OrderItem i) => [i.name, ?i.variant].join(' · ');

String _extras(OrderItem i) => [
  for (final a in i.addons) '+ ${a.name.toLowerCase()}',
  for (final c in i.changes) c.extra ? 'WIĘCEJ ${c.name.toLowerCase()}' : 'BEZ ${c.name.toLowerCase()}',
  if (i.note != null && i.note!.trim().isNotEmpty) i.note!.trim(),
].join(', ');

/// Etykiety zamówienia: na każdą sztukę dania z etykietą („1/3”, „2/3”...) albo jedna na całe zamówienie.
/// Pusta lista: zamówienie bez dań z etykietą albo rodzaj zamówienia bez etykiet.
List<Map<String, String>> labelValuesForOrder(
  TakeawayOrder o,
  LabelTemplate t, {
  required String restaurantName,
  required Map<String, LabelMenuInfo> menu,
}) {
  if (!t.kinds.contains(o.kind)) return const [];
  final common = _orderValues(o, restaurantName);
  if (t.per == LabelPer.order) {
    return [
      {...common, 'sztuka': '1/1', 'danie': '', 'dodatki': ''},
    ];
  }
  final units = [
    for (final i in o.active)
      if (labelForItem(t, i, menu))
        for (var n = 0; n < i.quantity; n++) i,
  ];
  return [
    for (var n = 0; n < units.length; n++)
      {...common, 'sztuka': '${n + 1}/${units.length}', 'danie': _dish(units[n]), 'dodatki': _extras(units[n])},
  ];
}

/// Przykładowe zamówienie do edytora i wydruku testowego: dostawa albo odbiór osobisty.
Map<String, String> sampleLabelValues({required bool delivery, required String restaurantName}) => {
  'numer': '12',
  'sztuka': '1/3',
  'danie': 'Margherita · 32 cm',
  'dodatki': '+ jalapeño, BEZ cebula, WIĘCEJ ser',
  'pozycje': '2× Margherita · 32 cm\n1× Lasagne\n1× Cola 0,5 l',
  'rodzaj': delivery ? 'DOSTAWA' : 'ODBIÓR',
  'godzina': '19:30',
  'data': _date(DateTime.now()),
  'klient': 'Anna Kowalska',
  'telefon': Fmt.phone('+48600100200'),
  'adres': delivery ? 'ul. Lipowa 12/4, Białystok' : '',
  'uwagi': delivery ? 'Proszę dzwonić domofonem · Do adresu: klatka B, 2 piętro' : 'Odbierze o 19:30',
  'platnosc': delivery ? 'Gotówka: 86,00 zł' : 'Opłacone',
  'kwota': '86,00 zł',
  'lokal': restaurantName,
};
