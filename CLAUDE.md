# Table

Aplikacja do rezerwacji stolików i rankingu kuchni. Ten projekt to wersja dla gości na telefony (Flutter).
Panel restauracji będzie osobną aplikacją na tablety i komputery, nigdy na telefony.
Z użytkownikiem rozmawiamy po polsku. Teksty w aplikacji i komentarze w kodzie też są po polsku.

## Stan na 17.09.2026

- 17.09.2026 aplikacja zmieniła nazwę z „Rarytka” na „Table”. Repozytorium: github.com/197w/table (prywatne).
  Identyfikator aplikacji na Androidzie i iOS: `pl.table.app` (wcześniej `pl.rarytka.rarytka`).
- Logo w `design/logo`: `table-1024px` (zielone) to ikona aplikacji dla gości, `table-b-1024px` (niebieskie) czeka na decyzję.
  Ikony platform: `python tool/generate_icons.py`, potem `dart run flutter_launcher_icons`.
- **Każda aktualizacja trafia na oba telefony:**
  - Android: Galaxy S23 podłączony do Windowsa.
  - iOS: symulator iOS na MacBooku Air M2 (od 17.09.2026 zamiast prywatnego iPhone'a użytkownika).
    Sesja Claude na Macu robi `git pull` i `flutter run -d <symulator> --dart-define-from-file=env.json`.
  - Projekt Xcode ma `DEVELOPMENT_TEAM = KHS3GJSPNL` (Personal Team użytkownika). Nie usuwać tej linii.
  - Flutter na obu komputerach w wersji 3.47.4. iOS deployment target 15.0, Swift Package Manager (bez Podfile).

## Stos

- Flutter 3.47.4 / Dart 3.13. Importuj `package:material_ui/material_ui.dart`, nie `flutter/material`.
- go_router 18, flutter_riverpod 3 (Notifier), supabase_flutter 2 (`publishableKey`), shared_preferences
  (SharedPreferencesAsync), geolocator, url_launcher, add_2_calendar, package_info_plus, flutter_svg.
- Konfiguracja Supabase w `env.json` (poza repozytorium), przekazywana przez `--dart-define-from-file=env.json`.
- Supabase: projekt `slcxxvcxheuxqajliuil` („Aplikacja”, eu-west-1). Migracje w `supabase/migrations`
  (0001–0011, wszystkie wdrożone). Dane testowe: `supabase/seed.sql` (Białystok) i `supabase/seed_krakow.sql` (Kraków), oba wgrane. Kody SMS w trybie testowym trafiają do tabeli `private.dev_sms_outbox`
  (hook `dev_send_sms_hook`). Gdy użytkownik napisze „kod”, podaj najnowszy `otp` z tej tabeli (jego numer kończy się na 098).

## Struktura

- `lib/app`: router i trasy (`AppRoutes`), dolne menu, ustawienia motywu, języka i jednostek.
- `lib/core`: motyw (`AppPalette`, `AppColors`, `AppTheme`), formatery (`Fmt`), jednostki, mapy, lokalizacja.
- `lib/data`: modele, `Repository` (jedyne miejsce rozmawiające z Supabase), providery.
- `lib/features`: auth, discover, restaurant, booking, reservations, reviews, settings.
- `lib/shared/app_icons.dart`: ikony Phosphor jako SVG w `assets/icons` (pobierane `npx better-icons get ph:<nazwa>`),
  widżet `Glyph` zamiast `Icon`, stałe w `AppIcons`.

## Zasady projektu

- Czcionka Geist (400/500/600, bez 700). Skala tekstu w `AppTheme`.
- Kolory: tło #161616 (ciemny), akcent #00F8B9. W jasnym motywie tekst akcentu #007A5C, wypełnienia #00F8B9.
- Pierścienie zamiast twardych obramowań, zgodne promienie (karta 22 = element 8 + odstęp 14), `PressScale` 0.96.
- Liczby tabelaryczne w cenach, godzinach i telefonach.
- Wszystkie powiadomienia przez push, SMS tylko do logowania. Push jeszcze niepodłączony (wymaga Firebase i konta Apple Developer).
- Opinie bez weryfikacji (rezerwacja albo paragon) nie liczą się do rankingu ani poziomu cen.
- Poziom cen $–$$$$ liczy trigger z mediany `price_per_person` w zweryfikowanych opiniach (≤30, ≤50, ≤80, >80 zł).
- Po usunięciu konta opinie zostają jako anonimowe („Były gość”).
- Profil ma `first_name` (widoczne przy opiniach) i `full_name` (tylko dla restauracji).
- Plan Free: przycisk „Zadzwoń”. Plan Pro: rezerwacja w aplikacji, plan sali 2D, automatyczny dobór stolika.

## Sprawdzanie

- `flutter analyze` bez uwag i `flutter test` przed każdą instalacją na telefonie.
