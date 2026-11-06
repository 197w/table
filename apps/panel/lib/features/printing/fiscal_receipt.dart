import '../../data/models.dart';

// Paragon fiskalny niezależny od drukarki: pozycje z rachunku (to, co nabito w zamówieniu), rabat do sumy,
// formy płatności i NIP nabywcy. Sterownik drukarki (np. Novitus XML) zamienia go na swoje polecenia.

/// Forma płatności na paragonie.
enum FiscalPaymentType { cash, card, voucher, transfer, other }

typedef FiscalLine = ({String name, int quantity, int unitGrosze, int vatRate});
typedef FiscalPayment = ({FiscalPaymentType type, int grosze});

class FiscalReceipt {
  const FiscalReceipt({
    required this.lines,
    required this.systemNo,
    this.discountGrosze = 0,
    this.payments = const [],
    this.nip,
  });

  final List<FiscalLine> lines;

  /// Rabat do sumy paragonu (kod rabatowy rachunku).
  final int discountGrosze;

  /// Formy płatności, gdy ich suma zgadza się z kwotą paragonu (inaczej drukarka przyjmie całość gotówką).
  final List<FiscalPayment> payments;

  /// NIP nabywcy (firma z zamówienia).
  final String? nip;

  /// Numer systemowy na paragonie (rachunek w Table), bez „#” i „@” na początku (to kod kreskowy i QR).
  final String systemNo;

  int get linesGrosze => lines.fold(0, (s, l) => s + l.quantity * l.unitGrosze);

  int get totalGrosze => linesGrosze - discountGrosze;
}

FiscalPaymentType _type(PaymentMethod m) => switch (m) {
  PaymentMethod.cash => FiscalPaymentType.cash,
  PaymentMethod.card => FiscalPaymentType.card,
  PaymentMethod.giftCard => FiscalPaymentType.voucher,
  PaymentMethod.other => FiscalPaymentType.transfer,
};

/// Paragon za opłacony rachunek: aktywne pozycje (nazwa z wariantem, ilość, cena z dodatkami, stawka VAT
/// z menu), opłata za dostawę ([deliveryVat]), rabat, płatności i zadatek jako przelew.
FiscalReceipt fiscalReceiptFor(PanelOrder o, {String? nip, int deliveryVat = 8}) {
  final lines = <FiscalLine>[
    for (final i in o.active)
      if (i.quantity > 0 && i.unitPriceGrosze > 0)
        (name: [i.name, ?i.variant].join(' '), quantity: i.quantity, unitGrosze: i.unitPriceGrosze, vatRate: i.vatRate),
    if (o.deliveryFeeGrosze > 0) (name: 'Dostawa', quantity: 1, unitGrosze: o.deliveryFeeGrosze, vatRate: deliveryVat),
  ];
  final gross = lines.fold(0, (s, l) => s + l.quantity * l.unitGrosze);
  final discount = o.discountGrosze.clamp(0, gross);
  final total = gross - discount;
  final payments = <FiscalPayment>[
    for (final p in o.payments)
      if (p.amountGrosze > 0) (type: _type(p.method), grosze: p.amountGrosze),
    if (o.depositGrosze > 0) (type: FiscalPaymentType.transfer, grosze: o.depositGrosze),
  ];
  final paid = payments.fold(0, (s, p) => s + p.grosze);
  final digits = nip?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
  return FiscalReceipt(
    lines: lines,
    discountGrosze: discount,
    payments: paid == total ? payments : const [],
    nip: digits.length == 10 ? digits : null,
    systemNo: o.number != null && o.kind != OrderKind.dineIn
        ? '${o.kind == OrderKind.delivery ? 'D' : 'O'}${o.number}'
        : 'R${o.id.substring(0, 8).toUpperCase()}',
  );
}
