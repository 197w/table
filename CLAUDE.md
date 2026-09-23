# Table

Rezerwacje stolików i ranking kuchni. Repozytorium ma dwie aplikacje Flutter i wspólny pakiet:

- `apps/guest`: aplikacja dla gości na telefony (Android i iOS), identyfikator `pl.table.app`.
- `apps/panel`: panel restauracji na komputery (Windows i macOS), identyfikator macOS `pl.table.panel`.
  Na tablety przejdziemy, gdy panel na komputerach będzie ustalony. Nigdy na telefony.
- `packages/table_core`: wspólny motyw, czcionka Geist, ikony Phosphor, formatery, widżety i konfiguracja.

Z użytkownikiem rozmawiamy po polsku. Teksty w aplikacjach i komentarze w kodzie też są po polsku.

## Stan na 17.09.2026

- Aplikacja zmieniła nazwę z „Rarytka” na „Table”. Repozytorium: github.com/197w/table (prywatne).
- Logo w `design/logo`: `table-1024px` (zielone) to ikona aplikacji dla gości, `table-b-1024px` (niebieskie) to ikona panelu.
  Ikony gościa: `python tool/generate_icons.py`, potem w `apps/guest`: `dart run flutter_launcher_icons`.
  Ikony panelu: w `apps/panel`: `dart run flutter_launcher_icons`.
- **Aplikacja dla gości: każda aktualizacja na oba systemy:**
  - Android: Galaxy S23 podłączony do Windowsa.
  - iOS: iPhone 14 użytkownika przez MacBooka Air M2 (od 19.09.2026 na jego prośbę). Darmowe konto Apple,
    więc wersja na telefonie działa 7 dni od podpisu.
  - Projekt Xcode gościa ma `DEVELOPMENT_TEAM = KHS3GJSPNL` (Personal Team użytkownika). Nie usuwać tej linii.
- **Panel restauracji: każda aktualizacja na oba systemy:** Windows na tym komputerze, macOS na MacBooku.
- Sesja Claude na Macu robi `git pull` i uruchamia aplikacje. Flutter na obu komputerach w wersji 3.47.4.
- Konto testowe panelu: `panel@table.test`, właściciel Pierogarni Na Mostku (Pro) i Gruzińskiej Chaty (Free).
  Drugie konto: `reve@table.test`, właściciel REVE Restaurant (Pro, Białystok, dane adresowe do uzupełnienia).
  Hasła zna użytkownik, nie zapisujemy ich w repozytorium.

## Uruchamianie

`env.json` leży w katalogu głównym repozytorium i nie trafia do Gita.

```bash
cd apps/guest && flutter run -d <telefon albo symulator> --dart-define-from-file=../../env.json
cd apps/panel && flutter run -d windows --dart-define-from-file=../../env.json
cd apps/panel && flutter run -d macos --dart-define-from-file=../../env.json
```

Windows wymaga Visual Studio Build Tools z modułem C++ i włączonego trybu dewelopera. macOS wymaga Xcode.
`flutter pub get` w dowolnym miejscu rozwiązuje zależności całego workspace (jeden `pubspec.lock` w katalogu głównym).

## Stos

- Flutter 3.47.4 / Dart 3.13, pub workspace. Importuj `package:material_ui/material_ui.dart`, nie `flutter/material`.
- go_router 18, flutter_riverpod 3 (Notifier), supabase_flutter 2 (`publishableKey`), shared_preferences
  (SharedPreferencesAsync), flutter_svg. Gość: geolocator, url_launcher, add_2_calendar, package_info_plus.
  Panel: window_manager (minimalny rozmiar okna 1100×720).
- Supabase: projekt `slcxxvcxheuxqajliuil` („Aplikacja”, eu-west-1). Migracje w `supabase/migrations`
  (0001–0018, wszystkie wdrożone). Dane testowe: `supabase/seed.sql` (Białystok), `supabase/seed_krakow.sql` (Kraków)
  i `supabase/seed_panel.sql` (strefy i rozstawienie stolików), wszystkie wgrane.
- Kody SMS w trybie testowym trafiają do tabeli `private.dev_sms_outbox` (hook `dev_send_sms_hook`).
  Gdy użytkownik napisze „kod”, podaj najnowszy `otp` z tej tabeli (jego numer kończy się na 098).

## Struktura

- `packages/table_core/lib/src`: `theme.dart` (`AppPalette`, `AppColors`, `AppTheme`), `theme_setting.dart`,
  `formatters.dart` (`Fmt`), `units.dart`, `env.dart`, `failure.dart` (`AppFailure`), `widgets.dart`
  (`PressScale`, `LoadingView`, `MessageView`, `ErrorView`, `Tag`, `DropdownPill`...), `app_icons.dart`
  (`Glyph` zamiast `Icon`, stałe `AppIcons`, SVG w `assets/icons`, nowe: `npx better-icons get ph:<nazwa>`).
- `apps/guest/lib`: `app` (router, dolne menu, preferencje), `core` (mapy, lokalizacja), `data`, `features`.
- `apps/panel/lib`: `app` (router, boczne menu, motyw na komputer), `data` (modele, `PanelRepository`, providery),
  `features` (auth, reservations, floor, menu, profile, reviews, stats), `shared/panel_widgets.dart`.

## Panel restauracji

- Logowanie e-mailem i hasłem. Obowiązkowe 2FA dodajemy przed wydaniem.
- Konto restauracji zakłada się wyłącznie na stronie internetowej, którą robimy na samym końcu.
  W panelu nie ma rejestracji. Do tego czasu konta testowe zakładamy ręcznie w bazie.
- Role w `restaurant_staff`: owner, manager, staff. Kierownik i właściciel zmieniają salę, menu, dane lokalu
  i odpowiadają na opinie. Obsługa prowadzi rezerwacje. Uprawnień pilnuje baza (RLS i funkcje `panel_*`).
- Rezerwacje i plan sali tylko w planie Pro. Plan Free widzi opinie, menu, lokal i statystyki wyświetleń.
- Limit osób w jednej rezerwacji z aplikacji ustawia lokal (`restaurants.max_party_size`, 1–30, domyślnie 12).
- Rezerwacje odświeżają się na żywo (Supabase Realtime na tabeli `reservations`).
- Plan sali: strefy w `floor_zones`, stoliki w `dining_tables` z pozycją środka w cm (`x_cm`, `y_cm`),
  obrotem i kształtem. Stolika z przyszłymi rezerwacjami nie da się usunąć (trigger), trzeba go wyłączyć.

## Zasady projektu

- Czcionka Geist (400/500/600, bez 700). Skala tekstu w `AppTheme`.
- Kolory: tło #161616 (ciemny), akcent #00F8B9. W jasnym motywie tekst akcentu #007A5C, wypełnienia #00F8B9.
- Panel w ciemnym motywie ma własną, chłodniejszą paletę `PanelPalette.dark` (`apps/panel/lib/app/panel_theme.dart`):
  tło #09090B, karty #111113, elementy na kartach #19191C, obrysy zamiast cieni. Aplikacja dla gości zostaje przy `AppPalette.dark`.
- Pierścienie zamiast twardych obramowań, zgodne promienie (karta 22 = element 8 + odstęp 14), `PressScale` 0.96.
- Liczby tabelaryczne w cenach, godzinach i telefonach.
- Wszystkie powiadomienia przez push, SMS tylko do logowania. Push jeszcze niepodłączony (wymaga Firebase i konta Apple Developer).
- Opinie bez weryfikacji (rezerwacja albo paragon) nie liczą się do rankingu ani poziomu cen.
- Poziom cen $–$$$$ liczy trigger z mediany `price_per_person` w zweryfikowanych opiniach (≤30, ≤50, ≤80, >80 zł).
- Po usunięciu konta opinie zostają jako anonimowe („Były gość”).
- Profil gościa ma `first_name` (widoczne przy opiniach) i `full_name` (tylko dla restauracji).
- Plan Free: przycisk „Zadzwoń”. Plan Pro: rezerwacja w aplikacji, plan sali 2D, automatyczny dobór stolika.

## Sprawdzanie

- `flutter analyze` bez uwag w każdej zmienionej aplikacji i pakiecie, `flutter test` w `apps/guest`,
  przed każdą instalacją.
