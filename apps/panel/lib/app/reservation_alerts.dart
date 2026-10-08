import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:table_core/table_core.dart';
import 'package:window_manager/window_manager.dart';

import '../data/models.dart';

/// Dźwięk i powiadomienie, gdy gość zarezerwuje stolik w aplikacji: w panelu powiadomienie w stylu Table
/// z przyciskiem „Pokaż”, a gdy panel jest w tle, także powiadomienie systemowe.
/// Rezerwacje wpisane przez obsługę (telefon, gość z ulicy) nie dzwonią,
/// bo obsługa i tak wie, że je dodała.
class ReservationAlerts {
  ReservationAlerts._();

  static final instance = ReservationAlerts._();

  final _player = AudioPlayer();
  bool _ready = false;

  /// Otwiera zakładkę Rezerwacje. Ustawia ją aplikacja panelu (router).
  VoidCallback? onOpen;

  /// Otwiera zakładkę Dostawy albo Odbiór (według rodzaju zamówienia).
  void Function(OrderKind kind)? onOpenTakeaway;

  /// Nowe zamówienie z dostawą albo odbiorem osobistym z aplikacji Table.
  Future<void> onTakeaway(TakeawayOrder order, {required bool muted}) async {
    if (muted) return;
    try {
      await _player.play(AssetSource('sounds/nowa_rezerwacja.wav'));
    } catch (_) {
      // Bez dźwięku zostaje powiadomienie.
    }
    final details = [
      order.customerName,
      ?order.address,
      Fmt.price(order.totalGrosze),
      order.cash ? 'gotówka' : 'karta online',
    ].join(' · ');
    Toasts.instance.show(
      details,
      title: 'Nowe zamówienie: ${order.label}',
      tone: ToastTone.success,
      icon: order.kind == OrderKind.pickup ? AppIcons.shoppingBag : AppIcons.moped,
      actionLabel: onOpenTakeaway == null ? null : 'Pokaż',
      onAction: onOpenTakeaway == null ? null : () => onOpenTakeaway?.call(order.kind),
      duration: const Duration(seconds: 15),
    );
    if (!_ready) return;
    try {
      if (await windowManager.isFocused()) return;
    } catch (_) {
      // Bez informacji o oknie pokazujemy też powiadomienie systemowe.
    }
    try {
      await LocalNotification(title: 'Nowe zamówienie: ${order.label}', body: details).show();
    } catch (_) {
      // System odmówił powiadomienia.
    }
  }

  /// Przygotowuje powiadomienia systemowe. Wywołaj raz przy starcie panelu.
  static Future<void> setup() async {
    try {
      await localNotifier.setup(
        appName: 'Table',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      instance._ready = true;
    } catch (_) {
      // Bez powiadomień systemowych zostaje sam dźwięk.
    }
  }

  /// Nowy wiersz z tabeli rezerwacji, tak jak przysłała go baza.
  Future<void> onInserted(Map<String, dynamic> row, {required bool muted}) async {
    if (row['source'] != 'app' || muted) return;

    try {
      await _player.play(AssetSource('sounds/nowa_rezerwacja.wav'));
    } catch (_) {
      // Brak głośników albo sterownika dźwięku: zostaje powiadomienie.
    }

    final startsAt = DateTime.tryParse(row['starts_at'] as String? ?? '')?.toLocal();
    final party = (row['party_size'] as num?)?.toInt();
    final details = [
      if (party != null) Fmt.people(party),
      if (startsAt != null) '${Fmt.dayShort(startsAt)}, ${Fmt.time(startsAt)}',
    ].join(' · ');

    Toasts.instance.show(
      details.isEmpty ? 'Zajrzyj do rezerwacji.' : details,
      title: 'Nowa rezerwacja z aplikacji',
      tone: ToastTone.success,
      icon: AppIcons.calendarPlus,
      actionLabel: onOpen == null ? null : 'Pokaż',
      onAction: onOpen,
      duration: const Duration(seconds: 12),
    );

    // Systemowe powiadomienie tylko wtedy, gdy panel jest w tle albo zminimalizowany.
    if (!_ready) return;
    try {
      if (await windowManager.isFocused()) return;
    } catch (_) {
      // Bez informacji o oknie pokazujemy też powiadomienie systemowe.
    }
    try {
      await LocalNotification(
        title: 'Nowa rezerwacja z aplikacji',
        body: details.isEmpty ? 'Zajrzyj do rezerwacji.' : details,
      ).show();
    } catch (_) {
      // System odmówił powiadomienia: dźwięk już był.
    }
  }
}
