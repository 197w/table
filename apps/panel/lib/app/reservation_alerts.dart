import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Ekran kuchni jest otwarty i ma wyłączone powiadomienia o rezerwacjach (ustawienia kuchni, na tym komputerze).
  bool kitchenSilent = false;

  /// Otwiera zakładkę Dostawy albo Odbiór (według rodzaju zamówienia).
  void Function(OrderKind kind)? onOpenTakeaway;

  /// Otwiera Inwentaryzację (powiadomienie o zamówieniu).
  VoidCallback? onOpenInventory;

  /// Składniki, których stan doszedł do progu „Powiadom o zamówieniu przy” (0086, 11.11.2026, prośba użytkownika):
  /// powiadomienie w panelu z „Pokaż”, a gdy panel jest w tle, także systemowe. Raz na zejście do progu: składnik
  /// powiadamia znowu dopiero wtedy, gdy stan wróci nad próg (dostawa, inwentaryzacja) i spadnie jeszcze raz.
  /// Powiadomione zapisuje na tym komputerze, więc ponowne uruchomienie panelu ich nie powtarza.
  /// Zwraca true, gdy pokazało powiadomienie.
  Future<bool> onReorder(String restaurantId, List<(InventoryItem, double)> low) async {
    final key = 'panel_zamowienie_powiadomione_$restaurantId';
    final prefs = SharedPreferencesAsync();
    Set<String> before;
    try {
      before = (await prefs.getStringList(key) ?? const <String>[]).toSet();
    } catch (_) {
      before = {};
    }
    final now = {for (final (item, _) in low) item.id};
    if (!setEquals(before, now)) {
      try {
        await prefs.setStringList(key, now.toList());
      } catch (_) {
        // Bez zapisu powiadomienie najwyżej powtórzy się po ponownym uruchomieniu.
      }
    }
    final fresh = [
      for (final entry in low)
        if (!before.contains(entry.$1.id)) entry,
    ];
    if (fresh.isEmpty) return false;
    String left((InventoryItem, double) e) => '${e.$1.name}: zostało ${inventoryNumber(e.$2 < 0 ? 0 : e.$2)} '
        '${e.$1.unit.label}';
    final title = fresh.length == 1
        ? 'Czas zamówić: ${fresh.first.$1.name}'
        : 'Czas zamówić: ${fresh.length} ${_ingredients(fresh.length)}';
    final details = fresh.length == 1
        ? 'Zostało ${inventoryNumber(fresh.first.$2 < 0 ? 0 : fresh.first.$2)} ${fresh.first.$1.unit.label}, '
              'powiadomienie przy ${inventoryNumber(fresh.first.$1.reorderAt!)} ${fresh.first.$1.unit.label}.'
        : fresh.take(4).map(left).join(' · ') + (fresh.length > 4 ? ' · i ${fresh.length - 4} więcej' : '');
    Toasts.instance.show(
      details,
      title: title,
      tone: ToastTone.warning,
      icon: AppIcons.package,
      actionLabel: onOpenInventory == null ? null : 'Pokaż',
      onAction: onOpenInventory,
      duration: const Duration(seconds: 20),
    );
    if (!_ready) return true;
    try {
      if (await windowManager.isFocused()) return true;
    } catch (_) {
      // Bez informacji o oknie pokazujemy też powiadomienie systemowe.
    }
    try {
      await LocalNotification(title: title, body: details).show();
    } catch (_) {
      // System odmówił powiadomienia.
    }
    return true;
  }

  static String _ingredients(int n) {
    final last = n % 10;
    final teen = n % 100 >= 12 && n % 100 <= 14;
    return last >= 2 && last <= 4 && !teen ? 'składniki' : 'składników';
  }

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
      order.cash ? 'gotówka' : (order.cardOnDelivery ? 'karta przy odbiorze' : 'karta online'),
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
    if (row['source'] != 'app' || muted || kitchenSilent) return;

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
