# Table

Rezerwacje stolików i ranking kuchni. Repozytorium ma trzy aplikacje Flutter i wspólny pakiet:

- `apps/guest`: aplikacja dla gości na telefony (Android i iOS), identyfikator `pl.table.app`.
- `apps/panel`: panel restauracji na komputery (Windows i macOS), identyfikator macOS `pl.table.panel`.
  Na tablety przejdziemy, gdy panel na komputerach będzie ustalony. Nigdy na telefony.
- `apps/staff`: Table for employees, aplikacja dla pracowników lokalu na telefony (Android `pl.table.table_staff`,
  iOS `pl.table.tableStaff`). Logowanie numerem telefonu (SMS), skan wspólnego kodu QR z panelu
  zaczyna zmianę i loguje w panelu. Dolne menu: Zamówienia, Dostawy, Zeskanuj, Grafik, Ustawienia. Grafik to lista dni z okresu lokalu
  (tydzień, 2 tygodnie albo miesiąc, `restaurants.schedule_period`, ustawia „Ustawienia lokalu”) ze zgłaszaniem godzin
  na cały okres naraz i „Moje godziny” na dole (miesiąc kalendarzowy ze strzałkami, do 3 miesięcy wstecz).
  Napisy dolnego menu: 11 px, bez powiększania czcionki z ustawień telefonu (S23 ma 1,15), żeby się nie zawijały. Kelner nabija zamówienia (stoliki, menu, wysyłka na kuchnię, wydanie,
  zamknięcie rachunku; niewysłaną pozycję usuwa się przesunięciem w lewo, minus tylko zmniejsza ilość; w wyborze dań
  „Przejdź dalej” na dole wraca do rachunku stolika; zamknięcie z rabatem, zadatkiem, napiwkiem i podziałem), mój grafik
  (zgłaszanie godzin), mój kod do panelu. Każda aktualizacja na S23 i iPhone'a, tak jak aplikacja dla gości.
- `packages/table_core`: wspólny motyw, czcionka Geist, ikony Phosphor, formatery, widżety i konfiguracja.
- `packages/table_car`: wtyczka Flutter tylko dla Table for employees: kurs dostawcy w Android Auto (Kotlin, Car App
  Library, szablon Pane, kategoria POI) i CarPlay (Swift, CPInformationTemplate, scena `TableCarSceneDelegate`
  w Info.plist) oraz rozpoznanie podłączenia do auta (`TableCar.connection`: aplikacja sama przechodzi na „Dostawy”).
  CarPlay na iPhonie wymaga uprawnienia Apple (`com.apple.developer.carplay-driving-task`, płatne konto), więc
  uprawnienie jest tylko dla symulatora (`CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]` w `ios/Flutter/Debug.xcconfig`).
  Test: Android Auto w emulatorze DHU (telefon przez USB, tryb dewelopera Android Auto, „Nieznane źródła”),
  CarPlay w symulatorze Xcode (I/O → External Displays → CarPlay). Nie edytujemy `.pbxproj`.

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
  Panel: window_manager (minimalny rozmiar okna 1100×720), file_selector (logo, zdjęcia, zapis CSV).
  Gość: flutter_map + latlong2 (mapa dostawcy, kafelki OpenStreetMap; przed wydaniem w sklepach przejść na płatnego dostawcę kafelków).
  Pracownik: geolocator (pozycja dostawcy w drodze).
- Supabase: projekt `slcxxvcxheuxqajliuil` („Aplikacja”, eu-west-1). Migracje w `supabase/migrations`
  (0001–0058, wszystkie wdrożone). Dane testowe: `supabase/seed.sql` (Białystok), `supabase/seed_krakow.sql` (Kraków)
  i `supabase/seed_panel.sql` (strefy i rozstawienie stolików), wszystkie wgrane.
- Nowa kolumna `restaurants` zmieniana wprost z panelu (`updateProfile`) potrzebuje `grant update (kolumna) on public.restaurants to authenticated`: tabela ma zgody tylko na wybrane kolumny (0012, 0041).
- Kody SMS w trybie testowym trafiają do tabeli `private.dev_sms_outbox` (hook `dev_send_sms_hook`).
  Gdy użytkownik napisze „kod”, podaj najnowszy `otp` z tej tabeli (jego numer kończy się na 098).

## Struktura

- `packages/table_core/lib/src`: `theme.dart` (`AppPalette`, `AppColors`, `AppTheme`), `theme_setting.dart`,
  `toasts.dart` (powiadomienia w stylu Table: `showMessage` z `tone`, `showError`, `Toasts`, `ToastHost` w
  `MaterialApp.builder` każdej aplikacji; komputer: prawy dolny róg, telefon: góra ekranu),
  `formatters.dart` (`Fmt`), `units.dart`, `env.dart`, `failure.dart` (`AppFailure`), `widgets.dart`
  (`PressScale`, `LoadingView`, `MessageView`, `ErrorView`, `Tag`, `DropdownPill`...), `app_icons.dart`
  (`Glyph` zamiast `Icon`, stałe `AppIcons`, SVG w `assets/icons`, nowe: `npx better-icons get ph:<nazwa>`;
  każda ikona ma też wersję duotone w `assets/icons/duotone` (`ph:<nazwa>-duotone`, `AppIcons.x.duotone`):
  wybrane zakładki i dolne menu, powiadomienia, puste ekrany, kafle `IconBadge`).
- `apps/guest/lib`: `app` (router, dolne menu, preferencje), `core` (mapy, lokalizacja), `data`, `features`
  (m.in. `ordering`: zamawianie z dostawą i na wynos).
- `apps/staff/lib`: `data.dart` (repozytorium i providery), `orders_data.dart`, `login_screen.dart`, `home_screen.dart`,
  `scan_screen.dart`, `schedule_screen.dart`, `settings_screen.dart`, `shell.dart`, `waiter_screens.dart`,
  `deliveries_data.dart`, `deliveries_screen.dart`
  (mobile_scanner). Podpis iOS: `DEVELOPMENT_TEAM` w `ios/Flutter/*.xcconfig`, nie w pbxproj.
- `apps/panel/lib`: `app` (router, `shell.dart` z górnym i bocznym paskiem, `sections.dart` z grupami zakładek,
  motyw na komputer), `data` (modele, `PanelRepository`, providery), `features` (auth, onboarding, kiosk,
  reservations, orders, deliveries, fleet, kitchen, serving, floor, menu, inventory, profile (też „Ustawienia lokalu”),
  customers, reviews, staff (też statystyki zespołu), stats),
  `shared/panel_widgets.dart`.

## Panel restauracji

- Logowanie e-mailem i hasłem. Obowiązkowe 2FA dodajemy przed wydaniem.
- Układ jak w UniFi (`shell.dart`, `sections.dart`, 0.11.0). Górny pasek: lokal po lewej (logo, kropka połączenia
  na żywo, plan; strzałka i lista tylko przy kilku lokalach konta), grupy zakładek (`PanelSection`, `_SectionTab`: same ikony bez ramek, wybrana w kolorze akcentu z nazwą):
  Rezerwacje (Rezerwacje), Zamówienia (Zamówienia, Historia zamówień `/historia`, Kompletowanie `/wydanie`,
  Odbiór `/odbior`), Kuchnia (Kuchnia), Dostawy (Dostawy, Flota),
  Pracownicy (Pracownicy: Zespół i Grafik, Statystyki zespołu `/zespol`), Baza klientów (Klienci `/klienci`, Opinie),
  Management (Podsumowanie dnia `/podsumowanie`, Godziny pracy `/godziny`, Menu, Inwentaryzacja, Statystyki,
  Kody rabatowe `/rabaty`, Eksport `/eksport`);
  „Table” na środku; po prawej nowa wersja, odliczanie do wylogowania, motyw i kółko pracownika (inicjały; menu:
  kod pracownika, „Zakończ zmianę”, „Wyloguj”, „Wejdź na zmianę”, e-mail i wersja, wylogowanie konta restauracji).
  Wąski pasek boczny: zakładki wybranej grupy (same ikony bez ramek, 30 px, nazwy w podpowiedziach po prawej, `tooltipOnRight`), na dole Ustawienia lokalu
  (`/ustawienia`), Dane lokalu i Edycja sali. Grupa i zakładki według uprawnień zalogowanego pracownika;
  ostatnia grupa zostaje wybrana na stronach lokalu (`panelSectionProvider`). Bez hamburgera i bez paska nad zakładką.
- Ustawienia lokalu: rezerwacje w aplikacji (co ile minut, największa grupa), zadatek przy rezerwacji, grafik pracowników,
  okres inwentaryzacji, dostawa i odbiór.
- Management (0048–0050): Podsumowanie dnia (`panel_day_summary`, uprawnienie `day_close`): sprzedaż według płatności
  (gotówka, karta z terminala, karta online z aplikacji i zadatki, inne), rabaty, raport dobowy z kasy fiskalnej
  (napiwków tu nie pokazujemy, są w statystykach zespołu; „Obrót w panelu”, „Karty w panelu” i „Powinno być” to duże kafle),
  terminale (kilka, nazwa i kwota), policzona gotówka i notatka (`day_reports`, `panel_save_day_report`), petty cash
  (wydatki i wpłaty z kasy, `petty_cash`, `panel_add_petty`, `panel_delete_petty`); zgodność kwot zielona albo żółta różnica.
  Godziny pracy (uprawnienie `timesheet`; wcześniej „Czas pracy” w Pracownikach): miesiąc z sumą godzin każdego pracownika
  (rozwijane zmiany) albo tydzień dzień po dniu; poprawka zmiany co do minuty (`panel_save_shift` z `p_editor_id`)
  zapamiętuje godziny sprzed niej (`staff_shifts.original_*`, `edited_at`), poprawione są żółte z różnicą („+0:15”).
  Okno poprawki ma osobny dzień początku i końca (zmiana może trwać przez północ albo dłużej niż dobę; koniec innego
  dnia na liście jako „18:09 (2.10)”). Zmiany i grafik odświeżają się na żywo (`TableLive`: kanał zakłada się od nowa
  po zerwaniu połączenia, a dane i tak co minutę), czas trwającej zmiany rośnie co 30 s (`clockProvider`).
  Kody rabatowe (uprawnienie `discounts`, `discount_codes`): procent albo kwota, ważność od–do, limit użyć, włączanie;
  gość wpisuje kod przy rezerwacji w aplikacji (`guest_check_discount`, `book_table(p_discount_code)`), rabat odejmuje się
  od rachunku stolika (procent od każdej części, kwota raz; odwołanie rezerwacji oddaje użycie). Eksport (uprawnienie
  `export`, `panel_export_month`): CSV dla Excela (średnik, przecinek, UTF-8 z BOM) za miesiąc: rachunki z VAT (rabat
  rozłożony proporcjonalnie na stawki), zestawienie dzienne, czas pracy z wynagrodzeniem brutto i netto, petty cash
  (`features/management/export_csv.dart`). Historia zamówień pokazuje obrót tylko z uprawnieniem `revenue`.
  Nowe uprawnienia `revenue`, `day_close`, `discounts`, `export` dostały w 0048 stanowiska z `staff` albo `stats`.
- Dane lokalu: logo, dane, poziom cen, dane właściciela, godziny, dni wyjątkowe.
- Flota (`/flota`, uprawnienie `fleet`, 0045): `vehicles` (auto, skuter, rower, inny; nazwa, rejestracja unikalna
  w lokalu, VIN 17 znaków bez I/O/Q unikalny w lokalu (0046), dostawca, w użyciu), `panel_save_vehicle`,
  `panel_delete_vehicle`. Notatki o pojeździe (0047): `vehicle_notes` (autor z zalogowanego pracownika albo
  „Konto restauracji”, `private.note_author`), `panel_add_vehicle_note`, `panel_delete_vehicle_note`; w oknie pojazdu
  po prawej, karta pokazuje ostatnią. Stare „Uwagi” (`vehicles.note`) przeszły do notatek z autorem „Uwagi”.
- Stawki i zarobki (0046, 0047): w oknie pracownika rodzaj umowy („Umowa”: zlecenie, zlecenie – student do 26 lat,
  umowa o pracę; `staff_rates.contract`) oraz stawka brutto i netto za godzinę: wpisanie jednej liczy drugą
  (`Payroll` w `models.dart`, 2026 w przybliżeniu: składki 13,71%, zdrowotna 9%, PIT 12%; zlecenie koszty 20%;
  umowa o pracę koszty 250 zł i kwota zmniejszająca 300 zł miesięcznie, stawka liczona dla 168 h; student netto = brutto).
  W bazie tylko brutto: tabela `staff_rates` (czyta tylko uprawnienie `staff`, bo `staff_members` widzą wszyscy
  pracownicy), zapis `panel_set_staff_rate(member, grosze, contract)`. Netto zarobku liczy panel z umowy (szczegóły
  pracownika, kolumna „Zarobek” i kafel „Wynagrodzenia brutto” w statystykach zespołu).
  Statystyki pracownika (szczegóły w Zespole) i zespołu liczone za miesiąc kalendarzowy od 1. do ostatniego dnia
  w strefie czasowej lokalu (`private.month_range`, `p_month`; zmiana przez północ dzieli się między miesiące),
  przełącznik `MonthSwitcher`; zarobek = godziny × obecna stawka, w zespole tylko z uprawnieniem `staff`.
  Okresy przełącza jedna pigułka `StepSwitcher` („‹ 5–11 paź ›”, `weekLabel`; stuknięcie w napis wraca do bieżącego):
  tydzień w Grafiku i Czasie pracy, miesiąc (`MonthSwitcher`), dzień w Historii zamówień (z kalendarzem w pigułce).
- Godziny wybiera się kółkami jak w iOS (`showTimeWheel` w `table_core`, w panelu `pickTime`): zapętlone kółka,
  przeciąganie myszą, na telefonie od dołu. Zamknięcie lokalu, koniec zmiany i „do” w grafiku mogą być 24:00
  (`allowEndOfDay`, `TimeOfDay(hour: 24)`, w bazie `time '24:00'`, kolumny i sprawdzenia `closes > opens` to przyjmują).
- Klienci (`/klienci`, uprawnienie `customers`, 0045): `panel_customers` łączy rezerwacje (bez blokad) i dostarczone
  zamówienia na wynos po koncie w aplikacji, telefonie (ostatnie 9 cyfr) albo imieniu: wizyty, nieobecności,
  zamówienia, wydatki, ostatnia wizyta, najbliższa rezerwacja. Układ: lista z wyszukiwaniem po lewej, po prawej
  wybrany klient (liczby, historia `panel_customer_history`, notatki) albo podsumowanie wszystkich. Klucz klienta
  liczy `private.customer_key` (0047). Notatki o kliencie: `customer_notes` (RLS: tylko obsługa lokalu,
  `has_staff_role`; goście ich nie widzą), `panel_add_customer_note`, `panel_delete_customer_note`, wspólny widżet
  `NotesView` (`shared/notes_view.dart`, Enter dodaje). Statystyki zespołu (`/zespol`, uprawnienie `stats`):
  `panel_team_stats` (godziny, zmiany, rachunki, pozycje, kursy, goście i pominięcia liczby gości, napiwki gotówką
  i kartą z `order_payments.member_id`, zarobek ze stawką widoczną od razu, sprzedaż na osobę) i `panel_team_summary`
  (obrót lokalu, goście, pominięcia, napiwki; kafel „Wypłaty z obrotu” = wynagrodzenia brutto / obrót); okres
  Dzisiaj / 7 dni / 14 dni / W tym miesiącu (`TeamPeriod`, `p_from` albo `p_days` albo `p_month`).
- Zakładki nie mają tytułów ani opisów (`PageHeader`: tylko akcje i rząd zakładek); nazwę widać w menu bocznym.
  Przyciski (`actions`) stoją po prawej w tym samym rzędzie co zakładki i filtry (`below`); osobny rząd nad nimi
  tylko z `actionsInRow: false` (Edycja sali).
  Przejście między zakładkami menu (`_tabPage` w `app.dart`) i zakładkami w ekranie (`TabContent`) ma ten sam ruch:
  wygaszenie i wjazd o kilka pikseli z dołu (`PanelMotion`, 220 ms). W Rezerwacjach wybór dnia, „Gość z ulicy”
  i „Nowa rezerwacja” są nad listą po prawej (z liczbą rezerwacji i gości), a „Na żywo”, odświeżanie i dźwięk
  na końcu rzędu filtrów.
- Restauracja zakłada konto w panelu mailem firmowym („Nowa restauracja? Załóż konto”), potwierdza mail
  i tworzy lokal (`panel_create_restaurant`: nazwa, NIP, miasto, adres, telefon, kuchnia; plan Free).
  Nowy lokal ma `restaurants.listed = false`: działa w panelu, ale goście go nie widzą, dopóki Table go
  nie zweryfikuje (weryfikacja: `update restaurants set listed = true`, poprawić też położenie `location`).
  Ja nadal nie zakładam kont ani nie wymyślam haseł: konto zakłada sama restauracja albo użytkownik.
- Pracownicy nie mają kont w panelu. Dodaje ich osoba z uprawnieniem `staff` w „Pracownicy” → „Zespół”
  (kafelki albo lista, przełącznik po prawej w wierszu zakładek; szczegóły ze statystykami `panel_member_stats`).
  Zakładki Zespół, Grafik i Czas pracy to same ikony (`IconTabs` w `panel_widgets.dart`): wybrana rozsuwa się z nazwą.
  `SegmentedTabs` i `IconTabs` mają wspólne podświetlenie (`_SlidingSegments`), które przesuwa się do wybranej opcji. Każdy pracownik ma czterocyfrowy kod, unikalny w lokalu
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
  pracownika każda zakładka pokazuje logowanie (`TabLoginGate`, bez opisu; „Właściciel: otwórz hasłem konta” pod kodem QR). Zalogować się może każdy pracownik w dowolnej zakładce: bez uprawnienia do niej `_RouteGuard` od razu przenosi go do pierwszej jego zakładki (kolejność `allPanelTabs`, zwykle Rezerwacje), z uprawnieniem zostaje. Nie loguje się tylko ktoś bez żadnej zakładki.
  Pasek boczny pokazuje zakładki zalogowanego pracownika, a menu pod jego kółkiem w górnym pasku „Wyloguj”
  i „Zakończ zmianę”. Właściciel otwiera panel hasłem konta restauracji (`ActingMember.account()`).
  „Wejdź na zmianę” (menu boczne, `ShiftScreen`) zaczyna zmianę i loguje pracownika. „Zakończ zmianę” jest w menu
  pracownika w górnym pasku (`EndShiftDialog`): pracownik potwierdza swoim kodem (`panel_member_end_shift` z `p_member_id`,
  kod innej osoby nie działa) albo kodem QR, który może zeskanować tylko on (`panel_login_tokens.purpose = 'end_shift'`,
  `for_member`; `staff_scan` kończy wtedy zmianę).
  Po 30 sekundach bez ruchu myszy i klawiatury panel sam wylogowuje pracownika i zamyka otwarte okna
  (`IdleLogout` w `MaterialApp.builder`, `kIdleLogoutSeconds`; ostatnie 10 s odlicza górny pasek).
  Kuchnia i Kompletowanie nie wylogowują pracownika. Pełny dostęp właściciela (`ActingMember.account()`, hasło konta)
  nie wylogowuje się sam: trwa do „Wyloguj” (tak chce użytkownik; bez odliczania w górnym pasku).
  Klawisze tylko liczą ruch, handler zwraca false (nic nie połyka).
  Wylogowanie konta restauracji (menu pracownika, ekran bez uprawnień) wymaga hasła konta (`signOutRestaurantAccount`).
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
  Po decyzji pracownik nie może zmienić tego dnia. Grafik w panelu jest tylko do odczytu, dopóki ktoś nie kliknie
  „Edytuj”: wtedy decyzje zbierają się jako niezapisane zmiany (`scheduleDraftProvider`, kropka w dniu, „Cofnij zmianę”)
  i trafiają do bazy naraz po „Zapisz” (`panel_save_schedule`, 0054, wszystkie albo żadna); pracownicy widzą je dopiero
  wtedy. Szkic przeżywa przejście do innej zakładki i automatyczne wylogowanie, znika, gdy zaloguje się ktoś inny.
  Panel pokazuje cały okres lokalu (tydzień, 2 tygodnie albo cały miesiąc tydzień pod tygodniem, `schedulePeriod`,
  `periodWeeks`), aplikacja Table for employees ten sam okres (okres pobiera od nowa przy otwarciu Grafiku). Okres, na który pracownicy zgłaszają
  godziny, ustawia lokal w „Ustawienia lokalu” → „Grafik pracowników” (`schedule_period`: week, two_weeks, month;
  pary tygodni liczone od poniedziałku 5.01.2026, `staff_my_jobs` zwraca okres). Czas pracy: Management → „Godziny pracy”.
  Od 0056: dzień bez zgłoszenia to „Niedostępny” (pracownik może też sam zgłosić „Nie mogę”, `staff_mark_unavailable`,
  stan `unavailable`); takiej osobie nie da się wpisać zmiany (`panel_add_hours`/`panel_decide_hours` odmawiają), tylko
  wysłać propozycję (`panel_propose_hours`, stan `proposed`, fioletowy), którą pracownik przyjmuje albo odrzuca w aplikacji
  (`staff_answer_proposal`; odrzucenie = niedostępny). Termin zgłaszania: „Ustawienia lokalu” → „Grafik pracowników”
  (`schedule_deadline_dow`, `schedule_deadline_time`: ostatni wybrany dzień tygodnia przed początkiem okresu o godzinie,
  `private.schedule_deadline`); po nim aplikacja nie przyjmuje zgłoszeń (`check_schedule_deadline`). Uwaga pracownika
  na tydzień (`staff_week_notes`, `staff_set_week_note`; w panelu ikona przy nazwisku). Pracownik może mieć kilka
  stanowisk (`staff_member_positions`, `panel_set_member_positions`, okno pracownika „Dodatkowe stanowiska”; uprawnienia
  to suma, `private.member_permissions`, dostawca: `private.is_courier`), w grafiku stanowisko na dzień
  (`staff_schedule.position_id`, wybór w oknie dnia, widać w aplikacji). Pod siatką: przyjętych osób, godziny pracy dnia
  i ile osób na jakim stanowisku; kolumna „Tydzień” z godzinami pracownika.
- Statystyki (Management) mają zakładki: Sprzedaż (`panel_sales_stats`) i Rezerwacje i goście; okres 7/30/90 dni
  w rzędzie zakładek. Historia zamówień jest osobną zakładką w grupie Rezerwacje.
- Role w `restaurant_staff`: owner, manager, staff. Kierownik i właściciel zmieniają salę, menu, dane lokalu
  i odpowiadają na opinie. Obsługa prowadzi rezerwacje. Uprawnień pilnuje baza (RLS i funkcje `panel_*`).
- Rezerwacje i plan sali tylko w planie Pro. Plan Free widzi opinie, menu, lokal i statystyki wyświetleń.
- Dane właściciela („Dane lokalu” → „Dane właściciela”, 0043): tabela `restaurant_owner_details` (imię i nazwisko,
  telefon, e-mail, nazwa firmy, NIP, adres firmy), RLS: czyta tylko kierownik i właściciel (`has_staff_role manager`).
  W panelu tylko do odczytu; zmiana tylko w Table Dev (narzędzie zespołu Table, jeszcze go nie ma):
  `panel_set_owner_details` ma tylko rola serwisowa (0044). Nie ma ich w aplikacji Table ani w Table for employees. NIP z rejestracji lokalu
  trafia tutaj (`restaurants.nip` jest puste, bo kolumny `restaurants` są publiczne dla gości).
- Limit osób w jednej rezerwacji z aplikacji ustawia lokal (`restaurants.max_party_size`, 1–30, domyślnie 12).
- Zadatek (0051): lokal ustawia, od ilu osób i ile za osobę (`deposit_min_party`, `deposit_per_person_grosze`,
  `panel_set_deposit`). Gość płaci zaraz po rezerwacji (`guest_pay_deposit_test`, tryb testowy); anulowanie płatności
  odwołuje rezerwację. Zadatek odejmuje się od rachunku (`orders.deposit_grosze`), w podsumowaniu dnia jako karta online.
  Odwołanie zwraca zadatek (`refunded`), nieobecność nie. Panel pokazuje KOD i ZADATEK przy rezerwacji.
- Lista oczekujących (0052, `waitlist_entries`): gość zapisuje się, gdy nie ma wolnych godzin (przedział godzin,
  notatka; najwyżej 3 miejsca naraz), w „Moje” widzi wpis i propozycję lokalu. Panel → Rezerwacje: przycisk z liczbą
  oczekujących, okno z gośćmi, „Zaproponuj godzinę” (`panel_offer_waitlist`) i usuwanie; rezerwacja gościa w tym lokalu
  tego dnia zamyka wpis (trigger).
- Rezerwacje odświeżają się na żywo (Supabase Realtime na tabeli `reservations`).
  Nowa rezerwacja z aplikacji: dźwięk i powiadomienie Table z przyciskiem „Pokaż” (`ReservationAlerts`), systemowe
  powiadomienie Windows tylko, gdy okno panelu jest w tle.
- Plan sali: strefy w `floor_zones`, stoliki w `dining_tables` z pozycją środka w cm (`x_cm`, `y_cm`),
  obrotem i kształtem. Stolika z przyszłymi rezerwacjami nie da się usunąć (trigger), trzeba go wyłączyć.
- Kliknięcie stolika na planie w „Rezerwacjach” otwiera menu tylko w obszarze planu, obok stolika i jego krzeseł.
  W menu „Nowa rezerwacja” otwiera okno z tym stolikiem. W „Nowej rezerwacji” stolik: „Dobierz automatycznie”
  albo „Wybierz stolik”. „Edycja sali” pokazuje zajętość stolików tylko teraz (bez innej godziny).
- Stanowiska (`staff_positions`) mają uprawnienia, np. Kelner: rezerwacje, plan, zamówienia. Pracownika łączy się
  z kontem w oknie pracownika („Konto w panelu”, `panel_link_staff_account`). Konto obsługi ma wtedy uprawnienia
  stanowiska (`private.has_permission`, `panel_my_permissions`). Kierownik i właściciel mają wszystkie.
- Zamówienia (`orders`, `order_items`, tylko Pro): zakładka „Zamówienia” widoczna z uprawnieniem `orders`.
  Rachunek otwiera się przy pierwszej pozycji, jeden otwarty na stolik; przed nim pytanie o liczbę gości (0056,
  `orders.guests`, „Pomiń” = `guests_skipped`, liczy się w statystykach; z rezerwacji liczba osób z niej; zmiana w nagłówku
  rachunku, `panel_set_order_guests`; u kelnera `_GuestsSheet`). Przy zamykaniu gotówką „Bez reszty”: reszta idzie do
  napiwku pracownika, który przyjmuje płatność. Nagłówek Zamówień: zegar, „W kuchni: N” (zamówienia z pozycjami
  na kuchni) i „Średnio” (`panel_kitchen_stats`, ostatnia godzina albo dziś). Stolik z rachunkiem jest podświetlony
  na zielono, a gdy ktoś nabija pozycje (panel albo aplikacja kelnera, stan new) na żółto z „Nabijane…”.
  Podział rachunku już przy nabijaniu (0058): pasek „Dla: Wspólne / Osoba 1 / Osoba 2 / +” nad pozycjami, nowe
  pozycje idą do wybranej osoby (`order_items.guest_no`, `p_guest` w `panel_add_order_item`), przeniesienie w menu
  pozycji (`panel_set_items_guest`), kwoty osób w pasku; przy zamykaniu „Po pozycjach” jednym kliknięciem wybiera
  pozycje osoby (`PersonBadge`, `person_badge.dart`). Telefon w „Nowe zamówienie” zaczyna się od „+48 ”.
  Przy stoliku i w nagłówku rachunku czas
  oczekiwania na danie (od najstarszej pozycji wysłanej na kuchnię, a niewydanej; `PanelOrder.waitingSince`, kolory
  według progów kuchni). Lista stolików ma na górze „Nowe zamówienie” (`NewOrderDialog`, `takeaway_form.dart`):
  w lokalu (wybór stolika), na dostawę albo na odbiór. Dostawa i odbiór (0055) wymagają imienia i nazwiska albo nazwy
  lokalu, telefonu, „opłacone” albo „do opłacenia”, a dostawa też ulicy, numeru domu/lokalu i miasta; NIP i komentarze
  (do zamówienia oraz tylko dla pracowników, `staff_note`) są opcjonalne. Po telefonie widać liczbę i kwotę wcześniejszych
  zamówień i „Uzupełnij dane” z ostatniego (`panel_customer_lookup`, ostatnie 9 cyfr `private.phone_key`).
  Zamówienie powstaje jako szkic (`fulfillment = 'draft'`, `panel_takeaway_create`, sekcja „Na wynos · do przyjęcia”
  na liście stolików), dania dokłada się z menu, „Przyjmij” z czasem przygotowania wysyła je na kuchnię i do Dostaw
  (`panel_takeaway_submit`), „Porzuć” je usuwa (`panel_takeaway_discard`), dane zmienia `panel_takeaway_update`.
  Opłacone z panelu to `payment_choice = 'prepaid'` (dostawca nic nie pobiera, w zamknięciu płatność „inne”).
  Zamówienie na godzinę (0057, tylko dostawa i odbiór; w panelu „Na kiedy” w formularzu, w aplikacji gościa „Kiedy”
  w koszyku z dniami i godzinami co 15 min w godzinach otwarcia, `RestaurantDetail.orderSlots`): `orders.scheduled_for`,
  sprawdza `private.check_scheduled` (gość: nie wcześniej niż wyprzedzenie kuchni, min. 15 min, w godzinach otwarcia;
  oba do 7 dni). Przyjęcie (`private.takeaway_plan`) daje `promised_at = scheduled_for`, a pozycjom `sent_at` równe
  godzinie minus wyprzedzenie z ustawień kuchni (`restaurants.kitchen_lead_pickup_min` 20 / `kitchen_lead_delivery_min`
  40); do tego czasu `orders.kitchen_at` jest ustawione, dostawca nie jest przydzielany (`dispatch_deliveries`),
  a pg_cron co minutę (`table_release_scheduled`, `private.release_scheduled`) czyści je po czasie, co przez trigger
  `orders_dispatch` przydziela dostawcę. Godzinę zmienia się (`panel_takeaway_update`, klucz `scheduled_for`),
  dopóki zamówienie nie weszło do kuchni.
  Przy daniu (przycisk ołówka na kafelku albo okno wariantów) zmiana składników: „Bez / Normalnie / Więcej” dla składników
  receptury i dowolny inny składnik (`order_items.changes`, `p_changes` w `panel_add_order_item`); kuchnia pokazuje
  „BEZ …” i „WIĘCEJ …” wyraźnie, magazyn nie zdejmuje składnika „bez”, a „więcej” zdejmuje podwójnie. To samo u kelnera
  w Table for employees. Suwaki list mają odstęp od rogów kart (`scrollbarTheme` w `PanelTheme`). Cenę, nazwę i VAT liczy baza z menu
  (`panel_add_order_item`), zapis tylko przez funkcje `panel_*`. Stany pozycji: new → sent (kuchnia) → ready
  (kuchnia zbiła, „do wydania”) → served (kelner zaniósł). Pozycje z `menu_items.show_in_kitchen = false`
  (np. napoje) po wysłaniu od razu są „do wydania”.
  Pozycję wysłaną na kuchnię anuluje tylko kierownik. Zamknięcie rachunku kończy rezerwację gości przy stoliku.
  Zamknięcie rachunku (0049, `SettleDialog` w panelu, `_SettleSheet` u kelnera): rabat z kodu rezerwacji albo kodu
  wpisanego przy rachunku (0054, `panel_order_set_discount`, zastępuje kod z rezerwacji, użycie liczy się przy zamknięciu;
  podpowiedzi kodów działających dziś: `panel_discount_suggestions`, `DiscountCodeField`, u kelnera `_DiscountSheet`), zadatek,
  napiwek (kwota albo 5/10/15%), całość jedną formą, równy podział na osoby (każda z formą płatności i napiwkiem) albo
  płatność za wybrane pozycje, które przechodzą na osobny opłacony rachunek „Część rachunku” (`panel_pay_items`);
  `panel_settle_order` zapisuje płatności w `order_payments` (method, amount, tip), `panel_order_due` liczy kwotę do zapłaty.
  Stare `panel_close_order` zostało dla starszych wersji: gotówka, karta albo inne. Karty podarunkowe usunięte (0038): nie ma ich
  w panelu ani w aplikacji Table, `purchase_gift_card` zwraca błąd, dane kart i stare płatności kartą zostają w bazie
  (historia zamówień i sprzedaż je pokazują). Historia zamkniętych rachunków: „Rezerwacje” → „Historia zamówień”,
  z podziałem Wszystkie / W restauracji / Dostawy / Odbiór osobisty (`HistoryKind`, z liczbą) i kwotą z dostawą.
  Paragon fiskalny jeszcze na kasie, integrację z drukarką fiskalną robimy później.
- Dostawy i odbiór osobisty (0039, 0040, tylko Pro): lokal włącza je w „Ustawienia lokalu” → „Dostawa i odbiór”
  (`delivery_enabled`, `pickup_enabled`, `takeaway_cash` = gotówka, opłata, minimalne zamówienie, obszar). Gość zamawia
  w aplikacji Table (przycisk „Zamów” w lokalu, koszyk, `guest_place_order`; ceny liczy baza z menu), płaci kartą online
  albo gotówką. Operatora płatności jeszcze nie ma: `private.app_settings.payments_mode = 'test'`, karta opłaca się
  w trybie testowym (`guest_pay_order_test`, `payment_test`). Zamówienie: `orders.kind` delivery/pickup,
  `fulfillment`: awaiting_payment → placed → accepted → ready → on_the_way → delivered (albo rejected/cancelled),
  numer dnia `number`. Panel „Dostawy” (`/dostawy`, uprawnienie `orders`, dźwięk i powiadomienie przy nowym):
  przyjęcie z czasem (`panel_takeaway_accept`, pozycje idą na kuchnię), gotowe, wydanie odbioru, odrzucenie, ręczna
  zmiana dostawcy (`panel_takeaway_assign`, `panel_couriers`). Gość śledzi zamówienie na żywo („Moje” → „Zamówienia”).
  Od paczki 3 „Dostawy” pokazują tylko dostawy, a odbiór osobisty ma zakładkę „Odbiór” w grupie Zamówienia (ten sam
  `DeliveriesScreen(kind: OrderKind.pickup)`: telefon, imię, godzina złożenia albo na którą, dania, kwota, opłacone;
  „Pokaż” w powiadomieniu otwiera właściwą zakładkę).
  Dostawcy (stanowisko z `deliveries` wpisanym wprost, bez „ALL”): kolejka `private.courier_queue`: kto pierwszy zaczął
  zmianę albo najdawniej skończył kurs, dostaje pierwszy kurs (`private.dispatch_deliveries`, triggery na zamówieniach
  i zmianach; koniec zmiany oddaje nieodebrane kursy kolejce). W Table for employees zakładka „Dostawy”
  (`staff_deliveries`, `staff_delivery_pickup`, `staff_delivery_done`, `staff_delivery_handover`: oddanie kursu wybranej
  osobie albo następnemu w kolejce, dopóki zamówienie jest w lokalu). Łączenie dostaw (0054, `orders.course_id`):
  w panelu „Połącz z inną dostawą” łączy przyjęte dostawy (jeszcze w lokalu) w jeden kurs jednego dostawcy
  (`panel_takeaway_merge`, wybór dostawcy albo bez zmiany), „Wyjmij” oddaje dostawę kolejce (`panel_takeaway_split`);
  kolejka, zmiana dostawcy, oddanie kursu i „Odebrałem” działają na cały kurs, „Dostarczone” na każdy adres osobno.
  Dostawca na mapie (0053): gdy kurs jest w drodze,
  Table for employees wysyła pozycję (`courier_location.dart`, co ~25 m, najwyżej co 15 s, w tle z powiadomieniem
  „Kurs w drodze”, `staff_courier_position`), gość widzi mapę w szczegółach zamówienia (`courier_map.dart`,
  `guest_courier_position` co 10 s); pozycja znika po zakończeniu kursu.
- Ekran kuchni (`/kuchnia`, uprawnienie `kitchen`, np. Kucharz): bileciki z pozycjami wysłanymi na kuchnię,
  pogrupowane po rachunku i chwili wysłania, najstarsze pierwsze. Czas liczony od wysłania z sekundami;
  kolory po progach z `restaurants.kitchen_warn_minutes`/`kitchen_late_minutes` (domyślnie 4 i 6 min).
  Zamówienie na wynos ma na bilecie adres dostawy z imieniem gościa albo „Odbiór osobisty · imię”.
  Stuknięcie pozycji albo „Gotowe” wywołuje `panel_kitchen_set` (sent ↔ ready, `ready_at`); cofnięta pozycja
  ma `recalled_at` i jest niebieska. Anulowane pozycje widać na czerwono. Sterowanie klawiaturą
  (1–9, strzałki, Spacja, Enter, Backspace, F, M, Esc; strzałki przechodzą między bilecikami, Spacja zbija
  i schodzi niżej, Enter zamyka bilecik i zaznacza następny), dolny pasek ze średnim czasem (`panel_kitchen_stats`),
  ustawienia (progi, wyprzedzenie zamówień na godzinę „Na wynos” i „Na dostawę”, pozycje ukryte,
  `panel_set_kitchen_config`). Pełny ekran chowa menu. Nowy bilecik dzwoni. Zamówienia na godzinę czekają w pasku
  „Zaplanowane” po prawej (tylko gdy są; godzina wejścia do kuchni, bez odliczania), o swojej porze przechodzą
  do bilecików (dzwonią) z paskiem „NA GODZINĘ · odbiór/u klienta HH:MM”. Kompletowanie pokazuje je dopiero wtedy.
- Kompletowanie (dawniej Wydanie; `/wydanie`, `features/serving`, uprawnienie `serving`, grupa Zamówienia; w 0042 dostały je stanowiska
  z `orders`): karty stolików z daniami gotowymi z kuchni (najdłużej czekające pierwsze, żółte po 2 min, czerwone
  po 4 min), stuknięcie pozycji albo „Wydane” wywołuje `panel_serve_items` (ready → served, `p_undo` cofa),
  pod kartą „Jeszcze na kuchni”. Zamówienia na wynos w przygotowaniu: „Spakowane” (`panel_takeaway_ready`),
  gdy kuchnia zrobi wszystko. Nowe gotowe danie dzwoni (wyciszenie `servingMutedProvider`).
- Menu: zdjęcia dań (`menu_items.photo_url`, bucket `menu-photos`, panel zmniejsza zdjęcie do 1200 px JPG,
  goście widzą je w aplikacji Table: miniatura po prawej przy daniu, stuknięcie powiększa; menu gościa pobiera dane
  od nowa przy otwarciu i przeciągnięciem w dół, bo strona lokalu pod spodem trzyma stare). Uprawnienia: `menu` (zakładka), `menu_edit` (dania, ceny, sekcje, zdjęcia),
  `menu_availability` („Skończyło się”). Warianty (np. rozmiary, każdy z ceną), płatne dodatki, stawka VAT i „dostępne teraz”. Przy wariantach
  `price_grosze` to najniższa cena wariantu. „od” przed ceną tylko, gdy warianty mają różne ceny (`priceVaries`
  w modelach gościa, pracownika i panelu); jeden wariant (np. Tonic 200 ml) pokazuje samą cenę. „Skończyło się” może ustawić też kelner i kuchnia (`panel_set_menu_item_available`).
- Inwentaryzacja (`/inwentaryzacja`, `features/inventory`): zakładki Spis, Składniki, Historia (`IconTabs`).
  Składniki (`inventory_items`: nazwa, jednostka ml/l/g/kg/szt, pojemność opakowania; usunięcie ustawia `deleted_at`,
  w historii zostają). Spis (`inventory_counts`, jeden otwarty na lokal, `inventory_count_lines` z ilością w opakowaniach
  oraz jednostką i pojemnością z chwili spisu): `panel_inventory_start`, `panel_inventory_set` (każda ilość zapisuje się
  od razu), `panel_inventory_finish`, `panel_inventory_discard`, lista `panel_inventory_counts`. Okres
  `restaurants.inventory_period` (day, week, two_weeks, month; `panel_set_inventory_period`), ustawia się w „Ustawienia lokalu”,
  następna inwentaryzacja liczona od ostatniej zakończonej. Uprawnienia: `inventory_edit` („Edytowanie składników”: składniki i okres)
  i `inventory_count` („Wpisywanie ilości składników”), grupa „Inwentaryzacja”. W spisie pełne opakowania i obok reszta
  w g/ml/szt (`inventory_count_lines.packages`, `loose`; `quantity` = opakowania z resztą, 6 miejsc po przecinku),
  „Razem” w mniejszej jednostce (np. mąka 50 kg: 1 op. + 2500 g = 52 500 g).
- Receptury (0037): w oknie dania w Menu sekcja „Składniki” (tylko w panelu): składnik z inwentaryzacji, ilość na
  porcję i jednostka (ml/l, g/kg, szt; `private.inventory_factor`), „Nowy składnik” dodaje go do Inwentaryzacji
  (insert z `menu_edit` albo `inventory_edit`). Tabela `menu_item_ingredients` (RLS: tylko obsługa lokalu, goście jej
  nie czytają), zapis `panel_set_menu_item_ingredients`. Trigger `order_items_inventory`: wysłanie pozycji (sent, ready,
  served) zapisuje zużycie w `inventory_movements` (ujemne, `kind = 'sale'`), anulowanie je usuwa. Stan teraz
  (`panel_inventory_stock`) = ostatnia inwentaryzacja składnika + ruchy od chwili, gdy go policzono. Historia pokazuje
  sprzedaż, stan „wg sprzedaży” i różnicę. Dostaw jeszcze nie ma (różnica na plusie). Warianty dania mają tę samą recepturę.

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
