// Zdarzenia lokalu do Logów (panel i Table for employees, `panel_activity`, migracja 0072).

import 'formatters.dart';

/// Grupa zdarzenia: kolor i pas na osi czasu.
enum ActivityGroup { staff, bills, kitchen, takeaway, reservations, stock }

/// Zdarzenie z dnia lokalu (`panel_activity`), złożone z chwil zapisanych przy zamówieniach, pozycjach, płatnościach,
/// rezerwacjach, zmianach i inwentaryzacji.
class ActivityEvent {
  const ActivityEvent({
    required this.at,
    required this.kind,
    this.label,
    this.member,
    this.count,
    this.amount,
    this.tip,
    this.method,
    this.names,
    this.orderId,
  });

  final DateTime at;
  final String kind;

  /// „Stolik 5”, „#12 dostawa”.
  final String? label;
  final String? member;
  final int? count;
  final int? amount;
  final int? tip;

  /// Płatność: cash, card, card_online… Rezerwacja: godzina „19:00”.
  final String? method;

  /// Pozycje („2× Pierogi, 1× Zupa”), gość rezerwacji, dostawca towaru albo klient zamówienia.
  final String? names;
  final String? orderId;

  ActivityGroup get group => switch (kind) {
    'shift_start' || 'shift_end' => ActivityGroup.staff,
    'order_open' || 'order_close' || 'payment' => ActivityGroup.bills,
    'items_added' || 'items_sent' || 'items_ready' || 'items_served' || 'items_cancelled' => ActivityGroup.kitchen,
    'reservation_new' || 'reservation_app' || 'reservation_seated' => ActivityGroup.reservations,
    'stock_delivery' || 'stock_removal' || 'stock_count' => ActivityGroup.stock,
    _ => ActivityGroup.takeaway,
  };

  String get title {
    final l = label ?? '';
    return switch (kind) {
      'shift_start' => '${member ?? 'Pracownik'} zaczyna zmianę',
      'shift_end' => '${member ?? 'Pracownik'} kończy zmianę',
      'order_open' => 'Otwarty rachunek · $l',
      'order_close' => 'Zamknięty rachunek · $l',
      'payment' => 'Płatność · $l',
      'items_added' => 'Nabite · $l',
      'items_sent' => 'Na kuchnię · $l',
      'items_ready' => 'Gotowe z kuchni · $l',
      'items_served' => 'Wydane gościom · $l',
      'items_cancelled' => 'Anulowane · $l',
      'takeaway_new' => 'Nowe zamówienie $l',
      'takeaway_app' => 'Zamówienie z aplikacji $l',
      'takeaway_accepted' => 'Przyjęte $l',
      'takeaway_ready' => 'Spakowane $l',
      'takeaway_picked' => 'Dostawca odebrał $l',
      'takeaway_done' => l.contains('odbiór') ? 'Wydane gościowi $l' : 'Dostarczone $l',
      'reservation_new' => 'Nowa rezerwacja',
      'reservation_app' => 'Nowa rezerwacja z aplikacji',
      'reservation_seated' => 'Goście usiedli',
      'stock_delivery' => 'Dostawa towaru',
      'stock_removal' => 'Usunięcie składników',
      'stock_count' => 'Inwentaryzacja zakończona',
      _ => kind,
    };
  }

  /// Szczegóły pod tytułem.
  String? get detail {
    final money = amount == null ? null : Fmt.price(amount!);
    final parts = switch (kind) {
      'order_open' => [if ((count ?? 0) > 0) '${count!} ${count == 1 ? 'gość' : 'gości'}', if (member != null) 'otworzył(a) $member'],
      'order_close' => [?money, if (member != null) 'zamknął(a) $member'],
      'payment' => [
        '${money ?? ''} ${paymentLabel(method)}'.trim(),
        if ((tip ?? 0) > 0) 'napiwek ${Fmt.price(tip!)}',
        if (member != null) 'przyjął(a) $member',
      ],
      'items_added' => [?names, ?money, if (member != null) 'nabił(a) $member'],
      'items_sent' || 'items_ready' || 'items_served' => [?names],
      'items_cancelled' => [?names, ?money],
      'takeaway_new' || 'takeaway_app' => [?names, ?money],
      'takeaway_picked' || 'takeaway_done' => [?member],
      'reservation_new' || 'reservation_app' => [?names, if (count != null) '$count os.', if (method != null) 'na $method'],
      'reservation_seated' => [?names, if (count != null) '$count os.'],
      'stock_delivery' || 'stock_removal' => [
        ?names,
        if (count != null) '$count ${count == 1 ? 'składnik' : 'składników'}',
        if (member != null) 'wpisał(a) $member',
      ],
      'stock_count' => [if (count != null) '$count składników', if (member != null) 'zakończył(a) $member'],
      _ => const <String>[],
    };
    return parts.isEmpty ? null : parts.join(' · ');
  }

  factory ActivityEvent.fromJson(Map<String, dynamic> json) => ActivityEvent(
    at: DateTime.parse(json['at'] as String).toLocal(),
    kind: '${json['kind']}',
    label: json['label'] as String?,
    member: json['member'] as String?,
    count: (json['count'] as num?)?.toInt(),
    amount: (json['amount'] as num?)?.toInt(),
    tip: (json['tip'] as num?)?.toInt(),
    method: json['method'] as String?,
    names: json['names'] as String?,
    orderId: json['order_id'] as String?,
  );
}

/// Forma płatności po polsku.
String paymentLabel(String? method) => switch (method) {
  'cash' => 'gotówką',
  'card' => 'kartą',
  'card_online' => 'kartą online',
  'other' => 'inną formą',
  _ => '',
};
