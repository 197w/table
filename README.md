# Table

Rezerwacje stolików i ranking kuchni w okolicy.

| Część | Folder | Platformy |
|---|---|---|
| Aplikacja dla gości | `apps/guest` | Android, iOS |
| Panel restauracji | `apps/panel` | Windows, macOS |
| Wspólny kod | `packages/table_core` | motyw, czcionka Geist, ikony, formatery, widżety |
| Baza danych | `supabase` | migracje i dane testowe Supabase |

## Pierwsze uruchomienie

1. Zainstaluj Flutter 3.47.4.
   - Windows: Visual Studio Build Tools z modułem „Desktop development with C++” i włączony tryb dewelopera.
   - macOS: Xcode.
   - Android: Android SDK.
2. Skopiuj `env.example.json` do `env.json` w katalogu głównym i wpisz adres projektu Supabase oraz klucz publikowalny.
3. Pobierz zależności całego repozytorium:

   ```bash
   flutter pub get
   ```

4. Uruchom wybraną aplikację:

   ```bash
   cd apps/guest && flutter run --dart-define-from-file=../../env.json
   ```

   ```bash
   cd apps/panel && flutter run -d windows --dart-define-from-file=../../env.json
   ```

## Baza danych

Migracje z `supabase/migrations` wgrywaj po kolei. Dane testowe: `seed.sql`, `seed_krakow.sql`, `seed_panel.sql`.
Hook `dev_send_sms_hook` zapisuje kody SMS w tabeli `private.dev_sms_outbox` zamiast je wysyłać.
Przed wydaniem trzeba go wyłączyć i podłączyć prawdziwą bramkę SMS.
