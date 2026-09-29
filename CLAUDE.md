# Table

Rezerwacje stolików i ranking kuchni. Repozytorium ma trzy aplikacje Flutter i wspólny pakiet:

- `apps/guest`: aplikacja dla gości na telefony (Android i iOS), identyfikator `pl.table.app`.
- `apps/panel`: panel restauracji na komputery (Windows i macOS), identyfikator macOS `pl.table.panel`.
  Na tablety przejdziemy, gdy panel na komputerach będzie ustalony. Nigdy na telefony.
- `apps/staff`: Table for employees, aplikacja dla pracowników lokalu na telefony (Android `pl.table.table_staff`,
  iOS `pl.table.tableStaff`). Logowanie numerem telefonu (SMS), skan wspólnego kodu QR z panelu
  zaczyna zmianę i loguje w panelu. Dolne menu: Zamówienia, Zeskanuj, Grafik, Ustawienia. Grafik to lista dni z okresu lokalu
  (tydzień, 2 tygodnie albo miesiąc, `restaurants.schedule_period`, ustawia „Dane lokalu”) ze zgłaszaniem godzin
  na cały okres naraz i „Moje godziny” na dole. Kelner nabija zamówienia (stoliki, menu, wysyłka na kuchnię, wydanie,
  zamknięcie rachunku), mój grafik (zgłaszanie godzin), mój kod do panelu. Każda aktualizacja na S23 i iPhone'a, tak jak aplikacja dla gości.
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
  Właściciele REVE z prawdziwymi kontami: `wiktorgodlewski977@gmail.com` (użytkownik) i
  `krystian.pryszczepko@gmail.com` (wspólnik). Konta zakłada użytkownik w Supabase (Authentication → Users),
  a do lokalu przypisujemy je wierszem w `restaurant_staff`.
  Hasła zna użytkownik. Nie zapisujemy ich w repozytorium i nie podajemy w rozmowie.

## Wydawanie panelu na Windows

- Wspólnik dostaje panel przez instalator i aktualizuje go automatycznie.
- Wydanie: tag `panel-vX.Y.Z` albo ręcznie workflow „Wydanie panelu na Windows” w GitHub Actions.
  Buduje instalator (Inno Setup, `apps/panel/windows/installer/table_panel.iss`) i wrzuca go z `latest.json`
  do publicznego katalogu `panel-releases/windows` w Supabase.
- Panel zainstalowany w `%LOCALAPPDATA%\Programs\Table Panel` sprawdza `latest.json` przy starcie
  (aktualizuje się od razu) i co 4 godziny (wiersz „Nowa wersja” w menu). Uruchomiony z folderu projektu
  nigdy się nie aktualizuje.
- Sekrety repozytorium: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` i `SUPABASE_SERVICE_ROLE_KEY` (ten ostatni wpisuje użytkownik).
- Link do pierwszej instalacji: `<SUPABASE_URL>/storage/v1/object/public/panel-releases/windows/TablePanelSetup.exe`.

## Uruchamianie

`env.json` leży w katalogu głównym repozytorium i nie trafia do Gita.

```bash
cd apps/guest && flutter run -d <telefon albo symulator> --dart-define-from-file=../../env.json
cd apps/panel && flutter run -d windows --dart-define-from-file=../../env.json
cd apps/panel && flutter run -d macos --dart-define-from-file=../../env.json
cd apps/staff && flutter run -d <telefon> --dart-define-from-file=../../env.json
```

Windows wymaga Visual Studio Build Tools z modułem C++ i włączonego trybu dewelopera. macOS wymaga Xcode.
`flutter pub get` w dowolnym miejscu rozwiązuje zależności całego workspace (jeden `pubspec.lock` w katalogu głównym).

## Stos

- Flutter 3.47.4 / Dart 3.13, pub workspace. Importuj `package:material_ui/material_ui.dart`, nie `flutter/material`.
- go_router 18, flutter_riverpod 3 (Notifier), supabase_flutter 2 (`publishableKey`), shared_preferences
  (SharedPreferencesAsync), flutter_svg. Gość: geolocator, url_launcher, add_2_calendar, package_info_plus.
  Panel: window_manager (minimalny rozmiar okna 1100×720).
- Supabase: projekt `slcxxvcxheuxqajliuil` („Aplikacja”, eu-west-1). Migracje w `supabase/migrations`
  (0001–0035, wszystkie wdrożone). Dane testowe: `supabase/seed.sql` (Białystok), `supabase/seed_krakow.sql` (Kraków)
  i `supabase/seed_panel.sql` (strefy i rozstawienie stolików), wszystkie wgrane.
- Kody SMS w trybie testowym trafiają do tabeli `private.dev_sms_outbox` (hook `dev_send_sms_hook`).
  Gdy użytkownik napisze „kod”, podaj najnowszy `otp` z tej tabeli (jego numer kończy się na 098).

## Struktura

- `packages/table_core/lib/src`: `theme.dart` (`AppPalette`, `AppColors`, `AppTheme`), `theme_setting.dart`,
  `formatters.dart` (`Fmt`), `units.dart`, `env.dart`, `failure.dart` (`AppFailure`), `widgets.dart`
  (`PressScale`, `LoadingView`, `MessageView`, `ErrorView`, `Tag`, `DropdownPill`...), `app_icons.dart`
  (`Glyph` zamiast `Icon`, stałe `AppIcons`, SVG w `assets/icons`, nowe: `npx better-icons get ph:<nazwa>`).
- `apps/guest/lib`: `app` (router, dolne menu, preferencje), `core` (mapy, lokalizacja), `data`, `features`.
- `apps/staff/lib`: `data.dart` (repozytorium i providery), `orders_data.dart`, `login_screen.dart`, `home_screen.dart`,
  `scan_screen.dart`, `schedule_screen.dart`, `settings_screen.dart`, `shell.dart`, `waiter_screens.dart`
  (mobile_scanner). Podpis iOS: `DEVELOPMENT_TEAM` w `ios/Flutter/*.xcconfig`, nie w pbxproj.
- `apps/panel/lib`: `app` (router, boczne menu, motyw na komputer), `data` (modele, `PanelRepository`, providery),
  `features` (auth, onboarding, kiosk, reservations, orders, kitchen, floor, menu, profile, reviews, staff, stats),
  `shared/panel_widgets.dart`.

## Panel restauracji

- Logowanie e-mailem i hasłem. Obowiązkowe 2FA dodajemy przed wydaniem.
- Restauracja zakłada konto w panelu mailem firmowym („Nowa restauracja? Załóż konto”), potwierdza mail
  i tworzy lokal (`panel_create_restaurant`: nazwa, NIP, miasto, adres, telefon, kuchnia; plan Free).
  Nowy lokal ma `restaurants.listed = false`: działa w panelu, ale goście go nie widzą, dopóki Table go
  nie zweryfikuje (weryfikacja: `update restaurants set listed = true`, poprawić też położenie `location`).
  Ja nadal nie zakładam kont ani nie wymyślam haseł: konto zakłada sama restauracja albo użytkownik.
- Pracownicy nie mają kont w panelu. Dodaje ich osoba z uprawnieniem `staff` w „Pracownicy” → „Zespół”
  (kafelki albo lista, przełącznik po prawej w wierszu zakładek; szczegóły ze statystykami `panel_member_stats`).
  Zakładki Zespół, Grafik i Czas pracy to same ikony (`IconTabs` w `panel_widgets.dart`): wybrana rozsuwa się z nazwą. Każdy pracownik ma czterocyfrowy kod, unikalny w lokalu
  (nadaje go baza przy dodaniu, trigger `staff_members_code`; zmiana: `panel_set_staff_code`, wpisany albo losowy).
  Kod widać stale w szczegółach (uprawnienie `staff_logins`, „Kody pracowników”, `panel_staff_codes`) i w aplikacji
  pracownika (`staff_my_codes`). Kod leży zaszyfrowany w Supabase Vault (`staff_codes.code_secret`), logowanie szuka
  po skrócie sha256 z lokalem. Po 10 błędnych kodach w 5 minut lokal wstrzymuje logowanie kodem
  (`station_login_failures`). Kod nie jest kontem Supabase Auth. Głównego stanowiska nie ma (usunięte w 0032):
  pracownicy logują się na każdym komputerze z panelem lokalu.
- Stanowisko systemowe „ALL” (`system_key = 'all'`): zawsze wszystkie uprawnienia, także przyszłe
  (`private.all_permissions()`, `private.position_permissions`). Nowe uprawnienie dopisujemy w `private.all_permissions()`
  i w `StaffPermission`. „ALL” ma Wiktor Godlewski (REVE); nadaje je tylko osoba z uprawnieniem `positions`.
- Logowanie pracownika w panelu jest jedno dla wszystkich zakładek (`panelMemberProvider`): kod QR z aplikacji
  Table for employees (`staff_scan`) albo czterocyfrowy kod na klawiaturze (`panel_member_login`). Bez zalogowanego
  pracownika każda zakładka pokazuje logowanie (`TabLoginGate`); wejść może tylko osoba z uprawnieniem do zakładki.
  Menu boczne pokazuje zakładki zalogowanego pracownika. Pasek nad zakładką (`TabSessionBar`): „Wyloguj”
  i „Zakończ zmianę”. Właściciel otwiera panel hasłem konta restauracji (`ActingMember.account()`).
  „Wejdź na zmianę” (menu boczne, `ShiftScreen`) zaczyna zmianę i loguje pracownika.
- Uprawnienia (`StaffPermission`, grupy Sala, Zamówienia, Kuchnia, Zespół, Lokal, Wyniki): m.in. `orders_close`
  (zamykanie rachunków), `orders_cancel` (anulowanie pozycji z kuchni), `kitchen_settings`, `staff_logins`,
  `schedule`, `timesheet`, `positions`. Menu boczne pokazuje zakładki według uprawnień konta,
  w zakładce przyciski według uprawnień zalogowanego pracownika (`memberPermissionsProvider`).
  Konto telefonu pracownika dostaje rolę obsługi (`restaurant_staff`, trigger `staff_members_account`), więc
  zamówienia w aplikacji używają funkcji `panel_*` z `p_member_id` (wymagana trwająca zmiana). Zamówienia zapisują
  pracownika (`opened_by_member`, `created_by_member`), kuchnia pokazuje jego imię na bileciku.
- Grafik („Pracownicy” → „Grafik”, uprawnienie `schedule`): pracownik zgłasza w aplikacji, od której do której może
  pracować (`staff_submit_hours`, `staff_delete_hours`, `staff_my_schedule`), przełożony przyjmuje (także ze
  zmienionymi godzinami), odrzuca albo sam wpisuje godziny (`panel_decide_hours`, `panel_add_hours`,
  `panel_delete_hours`) albo daje wolne (`panel_set_day_off`, stan `off` bez godzin, niebieski, ikona słońca).
  Po decyzji pracownik nie może zmienić tego dnia. Okres, na który pracownicy zgłaszają
  godziny, ustawia lokal w „Dane lokalu” → „Grafik pracowników” (`schedule_period`: week, two_weeks, month;
  pary tygodni liczone od poniedziałku 5.01.2026, `staff_my_jobs` zwraca okres). Czas pracy: „Pracownicy” → „Czas pracy”.
- Statystyki mają zakładki: Sprzedaż (`panel_sales_stats`), Rezerwacje i goście, Historia zamówień.
- Role w `restaurant_staff`: owner, manager, staff. Kierownik i właściciel zmieniają salę, menu, dane lokalu
  i odpowiadają na opinie. Obsługa prowadzi rezerwacje. Uprawnień pilnuje baza (RLS i funkcje `panel_*`).
- Rezerwacje i plan sali tylko w planie Pro. Plan Free widzi opinie, menu, lokal i statystyki wyświetleń.
- Limit osób w jednej rezerwacji z aplikacji ustawia lokal (`restaurants.max_party_size`, 1–30, domyślnie 12).
- Rezerwacje odświeżają się na żywo (Supabase Realtime na tabeli `reservations`).
- Plan sali: strefy w `floor_zones`, stoliki w `dining_tables` z pozycją środka w cm (`x_cm`, `y_cm`),
  obrotem i kształtem. Stolika z przyszłymi rezerwacjami nie da się usunąć (trigger), trzeba go wyłączyć.
- Kliknięcie stolika na planie w „Rezerwacjach” otwiera menu tylko w obszarze planu, obok stolika i jego krzeseł.
  W menu „Nowa rezerwacja” otwiera okno z tym stolikiem. W „Nowej rezerwacji” stolik: „Dobierz automatycznie”
  albo „Wybierz stolik”. „Edycja sali” pokazuje zajętość stolików tylko teraz (bez innej godziny).
- Stanowiska (`staff_positions`) mają uprawnienia, np. Kelner: rezerwacje, plan, zamówienia, karty. Pracownika łączy się
  z kontem w oknie pracownika („Konto w panelu”, `panel_link_staff_account`). Konto obsługi ma wtedy uprawnienia
  stanowiska (`private.has_permission`, `panel_my_permissions`). Kierownik i właściciel mają wszystkie.
- Zamówienia (`orders`, `order_items`, tylko Pro): zakładka „Zamówienia” widoczna z uprawnieniem `orders`.
  Rachunek otwiera się przy pierwszej pozycji, jeden otwarty na stolik. Cenę, nazwę i VAT liczy baza z menu
  (`panel_add_order_item`), zapis tylko przez funkcje `panel_*`. Stany pozycji: new → sent (kuchnia) → ready
  (kuchnia zbiła, „do wydania”) → served (kelner zaniósł). Pozycje z `menu_items.show_in_kitchen = false`
  (np. napoje) po wysłaniu od razu są „do wydania”.
  Pozycję wysłaną na kuchnię anuluje tylko kierownik. Zamknięcie rachunku kończy rezerwację gości przy stoliku.
  Zamknięcie rachunku (`panel_close_order`) przyjmuje kartę podarunkową z kwotą; gdy karta nie pokrywa
  całości, reszta inną metodą. Historia zamkniętych rachunków: zakładka „Historia zamówień”.
  Paragon fiskalny jeszcze na kasie, integrację z drukarką fiskalną robimy później.
- Ekran kuchni (`/kuchnia`, uprawnienie `kitchen`, np. Kucharz): bileciki z pozycjami wysłanymi na kuchnię,
  pogrupowane po rachunku i chwili wysłania, najstarsze pierwsze. Czas liczony od wysłania z sekundami;
  kolory po progach z `restaurants.kitchen_warn_minutes`/`kitchen_late_minutes` (domyślnie 4 i 6 min).
  Stuknięcie pozycji albo „Gotowe” wywołuje `panel_kitchen_set` (sent ↔ ready, `ready_at`); cofnięta pozycja
  ma `recalled_at` i jest niebieska. Anulowane pozycje widać na czerwono. Sterowanie klawiaturą
  (1–9, strzałki, Spacja, Enter, Backspace, F, M, Esc; strzałki przechodzą między bilecikami, Spacja zbija
  i schodzi niżej, Enter zamyka bilecik i zaznacza następny), dolny pasek ze średnim czasem (`panel_kitchen_stats`),
  ustawienia (progi i pozycje ukryte, `panel_set_kitchen_config`). Pełny ekran chowa menu. Nowy bilecik dzwoni.
- Menu: zdjęcia dań (`menu_items.photo_url`, bucket `menu-photos`, panel zmniejsza zdjęcie do 1200 px JPG,
  goście widzą je w aplikacji Table). Uprawnienia: `menu` (zakładka), `menu_edit` (dania, ceny, sekcje, zdjęcia),
  `menu_availability` („Skończyło się”). Warianty (np. rozmiary, każdy z ceną), płatne dodatki, stawka VAT i „dostępne teraz”. Przy wariantach
  `price_grosze` to najniższa cena wariantu. „Skończyło się” może ustawić też kelner i kuchnia (`panel_set_menu_item_available`).

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
  `apps/panel` i `apps/staff`, przed każdą instalacją.
- Zrzut okna panelu (PrintWindow) bywa biały przy Impellerze albo wygaszonym monitorze. Wtedy wygląd sprawdzamy
  testem z `matchesGoldenFile` i prawdziwą czcionką Geist, poza repozytorium.
