import 'package:audioplayers/audioplayers.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:table_core/table_core.dart';

/// Dźwięk i powiadomienie systemowe, gdy gość zarezerwuje stolik w aplikacji.
/// Rezerwacje wpisane przez obsługę (telefon, gość z ulicy) nie dzwonią,
/// bo obsługa i tak wie, że je dodała.
class ReservationAlerts {
  ReservationAlerts._();

  static final instance = ReservationAlerts._();

  final _player = AudioPlayer();
  bool _ready = false;

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

    if (!_ready) return;
    final startsAt = DateTime.tryParse(row['starts_at'] as String? ?? '')?.toLocal();
    final party = (row['party_size'] as num?)?.toInt();
    final details = [
      if (party != null) Fmt.people(party),
      if (startsAt != null) '${Fmt.dayShort(startsAt)}, ${Fmt.time(startsAt)}',
    ].join(' · ');
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
