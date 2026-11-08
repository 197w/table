# Table

Rezerwacje stolików i ranking kuchni. Repozytorium ma trzy aplikacje Flutter i wspólny pakiet:

- `apps/guest`: aplikacja dla gości na telefony (Android i iOS), identyfikator `pl.table.app`.
- `apps/panel`: panel restauracji na komputery (Windows i macOS), identyfikator macOS `pl.table.panel`.
  Na tabletach pełny panel uruchamia Table for employees (`lib/tablet.dart`, `runPanelOnTablet`, od 10.2026):
  poziomo, dźwięki z pakietu (`AudioCache` z prefiksem `packages/table_panel/assets/`), pełny ekran przez
  `SystemChrome` (`setPanelFullscreen` w `app/platform.dart`), bez okna, powiadomień Windows i aktualizatora;
  zapis plików (eksport, PDF) tylko na komputerze (`panelOnDesktop`). Nigdy na telefony.
- `apps/staff`: Table for employees, aplikacja dla pracowników lokalu na telefony (Android `pl.table.table_staff`,
  iOS `pl.table.tableStaff`). Na tablecie (krótszy bok co najmniej 600 punktów, `isTabletScreen`) aplikacja zamiast
  siebie uruchamia pełny panel restauracji jak na komputerze (zależność `table_panel`, zadanie z Todoist: „na tabletach
  identycznie jak na komputerach”): konto lokalu, pracownicy kodem albo QR. Logowanie e-mailem jak w Table (0069; numer konta = numer u pracownika w panelu), skan wspólnego kodu QR z panelu
  zaczyna zmianę i loguje w panelu. Dolne menu: Zamówienia, Dostawy, Zeskanuj, Kalendarz (dawniej Grafik, 8.11.2026), Konto (dawniej Ustawienia).
  Kalendarz (`schedule_screen.dart`, `ScheduleScreen`) to miesiąc jak w Apple Calendar z grafikiem i wydarzeniami lokali:
  zielone pola to dni okna zgłaszania (0081: jedyny okres lokalu, na który pracownik zgłasza teraz dyspozycyjność;
  tydzień, 2 tygodnie albo miesiąc, `restaurants.schedule_period`, ustawia „Ustawienia lokalu”), zgłaszanie godzin na
  ten okres naraz. „Moje godziny” usunięte 9.11.2026 na prośbę.
  Napisy dolnego menu: 11 px, bez powiększania czcionki z ustawień telefonu (S23 ma 1,15), żeby się nie zawijały. Kelner nabija zamówienia (stoliki, menu, wysyłka na kuchnię, wydanie,
  zamknięcie rachunku; niewysłaną pozycję usuwa się przesunięciem w lewo, minus tylko zmniejsza ilość; w wyborze dań
  „Przejdź dalej” na dole wraca do rachunku stolika; zamknięcie z rabatem, zadatkiem, napiwkiem i podziałem), mój grafik
  (zgłaszanie godzin), mój kod do panelu. Każda aktualizacja na S23 i iPhone'a, tak jak aplikacja dla gości.
  Wygląd (10.2026) jak w aplikacji dla gości, z tymi samymi zasadami dostępności (skill ui-ux-pro-max); wspólne
  elementy w `apps/staff/lib/ui.dart`: `StaffColors` (niebieski, fioletowy i pomarańczowy stanów z kontrastem
  co najmniej 4,5:1 w obu motywach, zamiast stałych kolorów), `IconTile`, `StatTile`, `SectionHeader`,
  `CardsSkeleton`, `BottomActionBar`, `ContentWidth` (720 px na tablecie), `hm`, `hoursText`, `hoursSpoken`.
  „Zeskanuj”: powitanie ze stanem, karta lokalu (stan „W pracy” z ikoną, kafle „Ta zmiana” i „Ten tydzień”, kod do
  panelu), „Zeskanuj kod” na stałe na dole. Zamówienia: podsumowanie sali (otwarte rachunki, do wydania, do wysłania),
  kafle stolików z liczbami i ikonami (dzwonek = do wydania, samolocik = do wysłania), rachunek z grupami „Do wydania /
  Do wysłania / Na kuchni / Wydane” i podpowiedzią o przesuwaniu w lewo, niedostępne dania z chipem zamiast
  przezroczystości. Dostawy: etap kursu i „na 19:30” jako chipy, „Nawiguj” z obrysem (pełny kolor ma tylko
  „Odebrałem” albo „Dostarczone”), kolejka z „Wolny / W kursie”, kafle „Kursy” i „Gotówka”, pulsowanie stoi przy
  „Ogranicz ruch”. Kalendarz (jak Apple Calendar): w pasku „‹ 2026” (czerwone, wraca do całego roku `_YearView`:
  12 małych miesięcy, dziś w czerwonym kółku, dni okna na zielono, stuknięcie otwiera miesiąc, przesunięcie zmienia
  rok), „Dziś” i „+” (nowe wydarzenie), wszystkie na Liquid Glass (`GlassTextButton`, `GlassIconButton(native: true)`).
  Miesiąc ze strzałkami i przesuwaniem palcem, siatka 6 tygodni (`_DayCell`: dziś na czerwono, wybrany w kółku,
  zielone pole = dzień okna zgłaszania bez zgłoszenia, kreska w kolorze stanu z `_dayStatus`, kropki wydarzeń),
  legenda z liczbami w miesiącu, wiersz okna („Zgłoś dyspozycyjność na tydzień 16–22 lis do …”, stuknięcie pokazuje te
  dni) i „Zgłoś godziny na …”, a pod kreską wybrany dzień: karta godzin (`_DayRow`, zielona do wpisania, przed oknem
  „Niedostępny”, po nim „Zgłaszanie później”; drugie stuknięcie w dzień też ją otwiera), wydarzenia
  (`CalendarEventTile`), uwaga na tydzień. Bez przygaszania przezroczystością.
  Ustawienia jak u gościa. Podgląd ekranów: test golden poza repozytorium, jak przy panelu.
  „Zakończ zmianę” (31.10.2026, wzór od użytkownika: okno wyboru sposobu zamówienia z aplikacji McDonald's) otwiera
  okno od dołu (`showOptionSheet` w `table_core/src/option_sheet.dart`: karta na całą szerokość telefonu aż do
  dołu ekranu, zaokrąglona u góry, treść nad paskiem systemu (od 1.11.2026, prośba użytkownika; wcześniej karta
  odsunięta od krawędzi), okrągłe „Zamknij” w lewym górnym rogu, duży tytuł, opcje jako wiersze z ikoną i strzałką): „Zakończ w aplikacji”
  albo „Zeskanuj kod z panelu”; potem „Zmiana zakończona” z godzinami w tym samym oknie (`showMessageSheet`, też
  po zeskanowaniu kodu startu albo końca zmiany).
  Wszystkie okna w Table i Table for employees mają ten styl (od 31.10.2026, prośba użytkownika): wspólna ramka
  `TableSheet` w `option_sheet.dart`. Pytania przed działaniem to `showConfirmSheet` (np. „Odwołać rezerwację?”,
  „Wylogować się?”, „Dostarczone #12?”: jedna opcja z ikoną, zamknięcie = nie), wybór `showOptionSheet`, komunikat
  `showMessageSheet`, wpisanie tekstu `showTextSheet` (uwaga na tydzień), a większe okna z własną treścią (filtry,
  warianty dania, płatność kartą, zadatek, lista oczekujących, godziny w grafiku, zamknięcie rachunku, rabat, goście,
  oddanie kursu, zdjęcie dania, kółka godzin na telefonie) `showTableSheet`. Nie używać `showDialog`, `AlertDialog`
  ani gołego `showModalBottomSheet` w aplikacjach mobilnych. Panel na komputerze zostaje przy swoich oknach.
  Informacje od kierownika (0062, `announcements_screen.dart`): karta na „Zeskanuj” (nowe wyróżnione, najnowsza),
  lista z ostatnich 60 dni ze wszystkich lokali pracownika (`staff_announcements`, `announcementsProvider` co 2 min)
  i cała informacja; otwarcie oznacza ją jako przeczytaną (`staff_read_announcement`). Dyspozycyjność może trwać przez
  północ: koniec wcześniej niż początek to następny dzień („02:00+1”, „Do 02:00 następnego dnia”), odrzucane są tylko
  równe godziny.
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
  Panel: window_manager (minimalny rozmiar okna 1100×720), file_selector (logo, zdjęcia, zapis plików eksportu), pdf (eksport do PDF).
  Gość i pracownik: adaptive_platform_ui (Liquid Glass na iOS 26). Pracownik: image_picker (zdjęcia auta).
  Map i śledzenia dostawców nie ma od 0068 (usunięte na prośbę użytkownika, także mapa u gościa).
- Supabase: projekt `slcxxvcxheuxqajliuil` („Aplikacja”, eu-west-1). Migracje w `supabase/migrations`
  (0001–0081, wszystkie wdrożone). Funkcje Edge w `supabase/functions` (wdrażane przez MCP Supabase). Dane testowe: `supabase/seed.sql` (Białystok), `supabase/seed_krakow.sql` (Kraków)
  i `supabase/seed_panel.sql` (strefy i rozstawienie stolików), wszystkie wgrane.
- Nowa kolumna `restaurants` zmieniana wprost z panelu (`updateProfile`) potrzebuje `grant update (kolumna) on public.restaurants to authenticated`: tabela ma zgody tylko na wybrane kolumny (0012, 0041).
- Kody SMS w trybie testowym trafiają do tabeli `private.dev_sms_outbox` (hook `dev_send_sms_hook`).
  Gdy użytkownik napisze „kod”, podaj najnowszy `otp` z tej tabeli (jego numer kończy się na 098).
- Logowanie w Table i Table for employees (0069, `package:table_core/email_auth.dart`: `EmailAuthFlow`, `EmailAuth`,
  `AuthPending`, `AddEmailFlow`): rejestracja numer telefonu → e-mail → kod z e-maila → hasło, logowanie e-mail →
  kod z e-maila → (numer, gdy konto go nie ma) → hasło („Nie pamiętasz hasła?” ustawia nowe, bo e-mail jest już
  potwierdzony kodem). Kod to `signInWithOtp(email)` + `verifyOTP(type: email)`; sesja z kodu liczy się dopiero po
  haśle (`AuthPending`, router gościa i `main.dart` pracownika; wyjście z ekranu albo zamknięcie aplikacji przed hasłem
  wylogowuje, `AuthPending.restore` przy starcie). Numer konta w `profiles.phone` (48 i 9 cyfr, trigger
  `profiles_phone_check`, unikalny `profiles_phone_unique`; stare konta przepisane z `auth.users.phone`), czyta go
  `private.account_phone` (pracownik po numerze `private.my_members`, baza klientów `customer_key`, rezerwacje).
  `auth_signup_check` (bez logowania: `phone_taken` / `email_taken`), `account_status`, `account_set_phone`.
  Stare konta bez e-maila: „Konto bez e-maila? Zaloguj się kodem SMS” (bez zakładania nowych kont SMS-em),
  potem „Dodaj e-mail” w ustawieniach (`updateUser(email)` + `verifyOTP(type: emailChange)`). Zmiana numeru
  w Table: hasło i `account_set_phone`, bez SMS-a. E-maile wysyła na razie poczta Supabase (tylko adresy osób
  z zespołu projektu, kilka na godzinę); szablony „Confirm signup”, „Magic Link” i „Change Email Address” muszą
  mieć `{{ .Token }}` (ustawia użytkownik w Supabase → Authentication → Emails).

## Struktura

- `packages/table_core/lib/src`: `theme.dart` (`AppPalette`, `AppColors`, `AppTheme`), `theme_setting.dart`,
  `toasts.dart` (powiadomienia w stylu Table: `showMessage` z `tone`, `showError`, `Toasts`, `ToastHost` w
  `MaterialApp.builder` każdej aplikacji; komputer: prawy dolny róg, telefon: góra ekranu),
  `formatters.dart` (`Fmt`), `units.dart`, `env.dart`, `failure.dart` (`AppFailure`), `widgets.dart`
  (`PressScale`, `LoadingView`, `MessageView`, `ErrorView`, `Tag`, `DropdownPill`, `StatusChip` (stan: ikona i słowo),
  `ButtonPair` (dwa przyciski, przy dużej czcionce jeden pod drugim)...), `app_icons.dart`
  (`Glyph` zamiast `Icon`, stałe `AppIcons`, SVG w `assets/icons`, nowe: `npx better-icons get ph:<nazwa>`;
  każda ikona ma też wersję duotone w `assets/icons/duotone` (`ph:<nazwa>-duotone`, `AppIcons.x.duotone`):
  wybrane zakładki i dolne menu, powiadomienia, puste ekrany, kafle `IconBadge`). Własne ikony w stylu Phosphor
  (obrys 16 na 256, też w duotone): `cursor`, `corners-out`, `dining-table`, `wall` (pasek edytora sali),
  `circle-half-inset` (pierścień z wypełnioną prawą połową w środku jak w UniFi: motyw systemowy,
  `AppThemeSetting.system`, od 2.11.2026; wcześniej przełączniki `toggles` i monitor).
  Duotone `plus`, `minus` i `x` to te same kształty bez kwadratu w tle (4.11.2026: zielony „+” w Rezerwacjach,
  `GlowButton(primary)`, wyglądał jak kafelek; nie pobierać ich od nowa z better-icons). Tak samo duotone
  `clock-counter-clockwise` (Logi w pasku bocznym, 5.11.2026): bez zielonego koła w środku, sama linia.
  Tak samo duotone `arrows-clockwise` (kafel „Powracający” w Klientach, 8.11.2026): sam zielony obrys, bez tła.
  Własne ikony do drukarek i edytora etykiet (6.11.2026, rysowane ręcznie w stylu Phosphor): `printer`, `text-t`,
  `text-b`, `text-align-left/center/right`, `line-segment`, `image`.
- `apps/guest/lib`: `app` (router, dolne menu, preferencje), `core` (mapy, lokalizacja), `data`, `features`
  (m.in. `ordering`: zamawianie z dostawą i na wynos).
  Odkrywaj (`features/discover`, nowy wygląd z 10.2026): powitanie na całą szerokość, wyszukiwarka
  „Szukaj lokali, dań albo kuchni” (`search_restaurants` od 0060 szuka też po kuchni i nazwach dań, `matched_dish`
  = „W menu: …”), kategorie kuchni z własnymi ikonami na spokojnym tle (`cuisineIcon`, ikony Phosphor z better-icons),
  w rzędzie filtrów „W pobliżu” albo miasto, „Filtry” (okno: ceny, ocena, odległość, rezerwacja w aplikacji, dostawa,
  na wynos; licznik „Pokaż N lokali”),
  „Sortuj” (Polecane / Najlepsza kuchnia / Najbliżej) i szybkie filtry, liczba lokali i przełącznik widoku
  (`DiscoverLayout`: karty ze zdjęciem albo zwarte wiersze, zapamiętany). Karta: zdjęcie na całą szerokość
  (`restaurants.cover_url` z „Dane lokalu” w panelu, inaczej pierwsze zdjęcie dania, inaczej karta w kolorze kuchni
  z ikoną, `RestaurantCover`), nazwa i szczegóły pod zdjęciem. Górna karta przy „Polecane” ma „Najlepsze
  dopasowanie” (`bestMatch`: ocena, odległość, kuchnie lokali z rezerwacji i zamówień gościa). Filtry z okna działają
  na gotowej liście (`applyDiscoverFilter`, `discoverResultsProvider`). To samo zdjęcie jest na górze strony lokalu.
  Dostępność (zasady skilla ui-ux-pro-max): pola dotyku co najmniej 48 dp (`DropdownPill.tapHeight`, pigułki 40 px
  w rzędzie 48), karta czytana jako jedno zdanie (`restaurantSemantics`), bez rezerwacji w aplikacji ikona telefonu
  (nie tylko szary kolor), rzędy rosną z czcionką systemu, nazwy kuchni bez ucinania, „Ogranicz ruch” wyłącza
  animacje, szkielety kart przy ładowaniu, zdjęcia dekodowane w rozmiarze karty (`cacheWidth`), tablet: dwie kolumny.
  Strona lokalu (`features/restaurant/restaurant_screen.dart`, w tym samym stylu): zdjęcie na całą szerokość chowa się
  przy przewijaniu w pasek z nazwą (`SliverAppBar`, przyciemnienie u góry pod przycisk „Wróć”), pod nim logo, nazwa,
  ocena, „Otwarte do 22:00” / „Zamknięte · otwiera jutro o 12:00” (`RestaurantDetail.openStatusAt`), adres do mapy,
  szybkie akcje Menu / Zadzwoń / Mapa / Opinie, cechy (rezerwacja, dostawa z opłatą, na wynos, zadatek), opis z „Pokaż
  więcej” tylko gdy się nie mieści, pasek dań (najpierw ze zdjęciem), oceny z dużą liczbą, godziny z „DZIŚ”, trzy
  opinie i „Pokaż wszystkie”. Na dole jedno główne działanie „Zarezerwuj stolik” (Free: „Zadzwoń”), obok „Zamów”;
  przy dużej czcionce jeden pod drugim. Menu: pasek działów podświetla dział widoczny u góry listy.
  Pozostałe zakładki w tym samym stylu (te same zasady dostępności): „Moje” → Rezerwacje ma sekcje Najbliższa
  (duża karta: kafelek z datą `DateTile`, „Jutro, 19:00” z `relativeVisit`, stan z ikoną `StatusChip`
  i `reservationStatus`, okazja, Odwołaj / Zadzwoń), Lista oczekujących, Nadchodzące i Archiwum („Oceń wizytę”);
  `DateTile`, `relativeVisit` i `reservationStatus` w `features/reservations/booking_widgets.dart`, `StatusChip`
  i `ButtonPair` w `table_core`. „Moje” → Zamówienia: „W trakcie” i „Zakończone”,
  wiersz z kafelkiem rodzaju (dostawa / odbiór), numerem, kwotą i etapem z ikoną; szkielety zamiast kółka ładowania.
  Konto → Polubione (0063, `features/likes/likes.dart`, od 10.2026 w Koncie pod kafelkiem konta jako jeden z dwóch kafelków obok siebie, `_AccountTile`, `LikedScreen`): serce na karcie lokalu w Odkrywaj (osobny przycisk nad
  kartą, poza jej opisem dla czytnika) i w pasku strony lokalu (`LikeButton`), w zwartych wierszach tylko znak
  polubienia (`LikedMark`); lista polubionych jako karty, ostatnio polubione pierwsze (`guest_liked_restaurants`,
  `likedRestaurantsProvider`). Polubienie od razu na ekranie (`LikedIdsNotifier`, przy błędzie wraca), w bazie
  `guest_set_like`; bez konta toast z „Zaloguj się”. Tabela `restaurant_likes` (gość czyta tylko swoje, lokal widzi
  same liczby w statystykach).
  Konto → Kody (0066, `features/codes/codes.dart`, `CodesScreen`): kody od lokali za zakończoną rezerwację albo zweryfikowaną opinię
  (zasady lokalu `guest_code_rules`, event `reservation`/`review`; triggery `reservations_guest_code`,
  `reviews_guest_code`, `private.issue_guest_code`). Kod jest osobisty, nie do udostępniania: widać go dopiero po
  „Aktywuj” (`guest_activate_code`), wtedy dostaje nowy tekst `T-XXXXXX` ważny 15 minut do pokazania kelnerowi
  (odliczanie na karcie; ponowna aktywacja w tym czasie daje ten sam kod). Kelner wpisuje go przy rachunku
  (`panel_order_set_discount` sprawdza najpierw `guest_codes`, `orders.guest_code_id`), zamknięcie oznacza go jako
  użyty (`orders_guest_code_used`). Lista: `guest_my_codes`. Panel: Kody rabatowe → „Kody dla gości z aplikacji”
  (`guest_code_rules.dart`, `panel_guest_code_rules`, `panel_save_guest_code_rule`).
  Ustawienia → „Adres dostawy” (0065, `features/settings/address_screen.dart`, `/ustawienia/adres`): ulica, numer
  domu/lokalu, opis budynku i kod do wejścia (opcjonalne), miasto, kod pocztowy (`profiles.address_*`,
  `Repository.updateAddress`). Koszyk dostawy uzupełnia się z niego (opis budynku i kod wejścia trafiają do notatki).
  Lokal widzi go w Bazie klientów nad notatkami („Adres z aplikacji Table”, `panel_customer_app_address`).
  Stan otwarcia na kafelkach lokali (0064, `search_restaurants` i `guest_liked_restaurants` zwracają `hours`):
  `openingStatus` w `models.dart` („Otwarte do 22:00”, „Wkrótce zamknięcie – 22:00” i „Wkrótce otwarcie – 12:00”
  na godzinę przed, „Zamknięte · otwiera …”), `OpenStatusLine` w `restaurant_cards.dart`.
  Tablet (10.2026): przy szerokości od 840 punktów menu z boku (`NavigationRail` w `shell.dart`, poza iOS 26 z natywnym
  paskiem), a ekrany z treścią (lokal, menu, rezerwacja, koszyk, zamówienie, ustawienia, logowanie) mają szerokość
  do 820 punktów na środku (`TabletWidth` w `app/tablet_width.dart`, owija trasy w `app.dart`).
  Dolne menu Table: Odkrywaj, Rezerwacje („Moje”: rezerwacje i zamówienia), Konto (dawniej Ustawienia; pod kafelkiem
  konta dwa kafelki obok siebie: Polubione z liczbą lokali i Kody z liczbą do wykorzystania, 8.11.2026).
  Liquid Glass (wspólny moduł `table_core/src/liquid_glass.dart`, eksportowany z `table_core`), tylko iOS 26 i nowszy
  (iPhone 14 użytkownika ma iOS 27; `PlatformInfo.isIOS26OrHigher` to „co najmniej 26”). Od 9.11.2026 (prośba: „ma
  wyglądać tak jak dolne menu”) natywne są też: przełącznik kart i listy w Odkrywaj (`GlassSegmentedIcons`, natywny
  UISegmentedControl z symbolami SF), „Zamknij” w oknie od dołu (`_SheetClose` w `option_sheet.dart`: natywny dopiero,
  gdy okno wjechało i nic go nie przykrywa) i przyciski w pasku Kalendarza pracownika (`GlassTextButton` z napisem
  UIKit). Gdy nad ekranem leży okno albo inna strona, w ich miejscu jest szkło Fluttera w tym samym kształcie.
  Natywne kontrolki UIKit tylko tam, gdzie stoją w miejscu i nic z Fluttera ich nie przykrywa: dolne menu
  (`NativeGlassTabBar`, natywny UITabBar), „Wstecz” i „Zamknij” w każdym pasku u góry
  (`AppBar(leading: glassLeading(context))`; poza iOS 26 null, czyli zwykły przycisk), „Wróć” i serce w pasku strony
  lokalu. Reszta to szkło rysowane przez Fluttera
  w tym samym stylu (`GlassSurface`: półprzezroczysta warstwa, jasna krawędź, cień; `frosted` gęstsze na zdjęciu,
  `blur` z rozmyciem nad przewijaną treścią; filtry w Odkrywaj, czyli pigułki i `DropdownPill` „Gdzie szukać” /
  „Sortuj”, wróciły 8.11.2026 na prośbę do wyglądu sprzed Liquid Glass i nie są na szkle): serca na kartach
  (`LikeButton(glass: true)`, od 9.11.2026 przejrzyste szkło z prawdziwym rozmyciem i nasyceniem zdjęcia pod spodem,
  `GlassIconButton(blur: true)`), „Zarezerwuj stolik”, „Zadzwoń, żeby zarezerwować” i „Zamów” (z rozmyciem, bez paska
  pod spodem), u kelnera filtry działów menu, „Zamknij” w oknie od dołu (`GlassIconButton` z `icon`; natywny
  przycisk w oknie, które jedzie od dołu i które przykrywa drugie okno, psuł na iPhonie rysowanie treści okna:
  puste kółka godzin, 1.11.2026). Powód (31.10.2026, „aplikacje są zlagowane”): we Flutterze 3.47 na iOS
  każda klatka z natywnym widokiem czeka na wątek główny, a każdy napis Fluttera na natywnym szkle to osobna warstwa
  wielkości ekranu rysowana w każdej klatce; kilkanaście pigułek i serc w przewijanej liście zacinało obie aplikacje.
  Nie dodawać natywnych kontrolek powtarzanych w wierszach i kartach list ani pod treścią Fluttera (pojedynczy
  przełącznik nad listą jest natywny, ale pod oknem albo inną stroną ustępuje szkłu Fluttera). Wybrane: kolor akcentu z treścią
  `AppColors.onAccent`. Natywny przycisk nie zmienia stylu po utworzeniu, więc klucz zawiera stan. Natywny pasek
  chowa się, gdy nad zakładką jest inny ekran. Android zostaje przy Material. Dolne menu nie ma podpowiedzi po przytrzymaniu (`NavigationDestination(tooltip: '')`); podpowiedzi są
  tylko w lewym pasku panelu. Sprawdzić da się tylko na iPhonie z iOS 26 (Xcode 26).
  Szczegóły rezerwacji: kafelek z datą i stan na górze. Konto: przy „Ogólne” i „Motyw” widać bieżący wybór,
  wiersze co najmniej 56 px, nazwy w dwóch liniach zamiast ucinania. Pary przycisków przy dużej czcionce
  (`textScaler.scale(16) > 20`) stają jeden pod drugim. `textDisabled` (kontrast ok. 3:1) tylko na ozdoby,
  tekst i ikony z informacją w `textMuted`.
- `apps/staff/lib`: `data.dart` (repozytorium i providery), `orders_data.dart`, `login_screen.dart`, `home_screen.dart`,
  `scan_screen.dart`, `schedule_screen.dart`, `settings_screen.dart`, `shell.dart`, `waiter_screens.dart`,
  `deliveries_data.dart`, `deliveries_screen.dart`, `ui.dart` (kolory stanów i wspólne elementy wyglądu)
  (mobile_scanner). Podpis iOS: `DEVELOPMENT_TEAM` w `ios/Flutter/*.xcconfig`, nie w pbxproj.
- `apps/panel/lib`: `app` (router, `shell.dart` z górnym i bocznym paskiem, `sections.dart` z grupami zakładek,
  motyw na komputer), `data` (modele, `PanelRepository`, providery), `features` (auth, onboarding, kiosk,
  reservations, orders, deliveries, fleet, kitchen, serving, floor, menu, inventory, profile (też „Ustawienia lokalu”),
  customers, reviews, staff (też statystyki zespołu), stats),
  `shared/panel_widgets.dart`.

## Panel restauracji

- Logowanie e-mailem i hasłem. Obowiązkowe 2FA dodajemy przed wydaniem.
- Układ jak w UniFi (`shell.dart`, `sections.dart`, 0.11.0). Górny pasek: w lewym rogu sam biały stół ze znaku Table,
  bez tła i bez napisu (`TableMark` z ekranu logowania, na środku nad ikonami bocznego paska; od 0.27.0 na prośbę
  użytkownika, wcześniej był tu lokal), grupy zakładek (`PanelSection`, `_SectionTab`: same ikony bez ramek, wybrana w kolorze akcentu z nazwą):
  Rezerwacje (Rezerwacje), Zamówienia (Zamówienia, Historia zamówień `/historia`, Kompletowanie `/wydanie`,
  Odbiór `/odbior`), Kuchnia (Kuchnia), Dostawy (Dostawy, Flota),
  Pracownicy (Pracownicy: Zespół i Stanowiska, Grafik `/grafik`, Statystyki zespołu `/zespol`, Informacje dla
  pracowników `/informacje`),
  Baza klientów (Klienci `/klienci`, Opinie),
  Management (Podsumowanie dnia `/podsumowanie`, Kalendarz `/kalendarz`, Niezamknięte zamówienia `/niezamkniete`, Godziny pracy `/godziny`,
  Menu, Inwentaryzacja, Statystyki,
  Kody rabatowe `/rabaty`, Eksport `/eksport`);
  Kropki nowości (`tabNewsProvider`, `TabNews`, `_NewsDot`): nowa rezerwacja z aplikacji, nowe zamówienie na dostawę
  albo odbiór, nowe danie do wydania; kropka na zakładce i jej grupie znika po wejściu do zakładki.
  „Table” na środku (szary napis, od 1400 px szerokości; zostaje, użytkownik go nie zmieniał). Po prawej nowa
  wersja, odliczanie do wylogowania, motyw (systemowy: pierścień z połową `AppIcons.circleHalfInset` jak w UniFi, od 2.11.2026; wcześniej przełączniki i monitor), obok niego ikona „Wyloguj”
  (gdy ktoś jest zalogowany, od 0.21.0), kółko pracownika (inicjały; menu: kod pracownika, „Zakończ zmianę”,
  „Wejdź na zmianę”, e-mail i wersja, wylogowanie konta restauracji), a w samym prawym rogu lokal
  (`_RestaurantSwitcher`: logo, kropka połączenia na żywo, plan; strzałka i lista tylko przy kilku lokalach konta).
  Kropka na „Informacje dla pracowników”, dopóki zalogowany pracownik ma nieprzeczytane informacje.
  Wąski pasek boczny: zakładki wybranej grupy (same ikony bez ramek, 30 px, nazwy w podpowiedziach po prawej, `tooltipOnRight`), na dole Ustawienia lokalu
  (`/ustawienia`), Drukarki i terminal (`/drukarki`, od 6.11.2026), pod nimi Logi (`/logi`, od 31.10.2026), Dane lokalu i Edycja sali (`placeTabs`). Grupa i zakładki według uprawnień zalogowanego pracownika;
  ostatnia grupa zostaje wybrana na stronach lokalu (`panelSectionProvider`). Bez hamburgera i bez paska nad zakładką.
  Pod nagłówkiem zakładki (`PageHeader`) i pod paskiem Kuchni i Kompletowania nie ma linii (31.10.2026, prośba
  użytkownika): treść zaczyna się zaraz pod zakładkami.
  Ikony bez tła (1.11.2026, prośba użytkownika): przycisk z ikoną (`IconButton`, motyw w `panel_theme.dart`) to sama
  ikona bez tła, obwódki i podświetlenia po kliknięciu, najechana jaśnieje (w przyciskach nie ustawiamy koloru ikony,
  żeby działało); kosz to zawsze `DeleteButton` (czerwony, wyłączony bladoczerwony, od 4.11.2026, bo szary wyłączony kosz przy
  jedynym terminalu w Podsumowaniu dnia wyglądał na nieczerwony; w notatkach na środku wysokości); `GlowButton` w nagłówkach też sama ikona (główna akcja w kolorze akcentu, duotone); `IconBadge`
  w kaflach liczb i nagłówkach kart to kolorowa ikona bez kostki; `IconTabs` bez pigułki: wybrana ikona w kolorze
  akcentu z nazwą obok, jak grupy w górnym pasku. Jedna wysokość kontrolek 40 px (`PanelTheme.controlHeight`):
  przyciski wszystkich rodzajów, przyciski z ikoną, pola w jednej linii (padding 8 + 24 + 8), ikony w polach,
  `PanelPill`; bez powiększania pola dotyku do 48 px (`materialTapTargetSize: shrinkWrap`). Wyjątki: duże przyciski
  dotykowe Kompletowania (48) i małe przyciski tekstowe w wierszach (32).
- Ustawienia lokalu jako lista jak w UniFi (1.11.2026, prośba użytkownika; `SettingsSection` i `SettingsRow`
  w `panel_widgets.dart`): jedna kolumna sekcji (do 860 px, na środku), tytuł sekcji nad kartą, w karcie wiersze
  oddzielone linią: nazwa (i opis) po lewej, przełącznik, pole albo wybór po prawej, „Zapisz” pod ostatnim wierszem.
  Kolejno: rezerwacje w aplikacji (co ile minut, największa grupa), zadatek przy rezerwacji, dostawa i odbiór,
  platformy dostaw (0067; każda platforma to wiersz z koszem, na końcu „Dodaj platformę” z podpowiedziami),
  grafik pracowników, okres inwentaryzacji i „Ten komputer” (preferencje tego komputera):
  „Automatyczne uruchamianie w pełnym ekranie” (`StartFullscreenNotifier`, klucz `panel_pelny_ekran_przy_starcie`).
  Bez niej panel startuje zmaksymalizowany (`main.dart`), nie w małym oknie; wyjście z pełnego ekranu kuchni wraca
  do pełnego ekranu, gdy ta opcja jest włączona.
- Management (0048–0050): Podsumowanie dnia (`panel_day_summary`, uprawnienie `day_close`): sprzedaż według płatności
  (gotówka, karta z terminala, karta online z aplikacji i zadatki, inne), rabaty, raport dobowy z kasy fiskalnej
  (napiwków tu nie pokazujemy, są w statystykach zespołu;
  różnica między kartami z terminali a kartami w panelu przechodzi na gotówkę: mniej na terminalach = „Powinno być”
  więcej o tę kwotę i odwrotnie, z wyjaśnieniem; na górze baner z niezamkniętymi zamówieniami z tego dnia
  albo wcześniejszych i „Sprawdź”). Od 8.11.2026 (prośba użytkownika: „Prostszy, jedna kolumna”, `day_screen.dart`)
  bez kafli: jedna kolumna sekcji jak Ustawienia lokalu (`SettingsSection`/`SettingsRow`, do 860 px na środku):
  Sprzedaż (obrót, zamówienia netto, średni rachunek, formy płatności, kaucja), Kasa fiskalna (raport dobowy, netto
  z raportu, „Obrót w panelu” ze znaczkiem „Zgadza się” / „Różnica”, `_Match`), Terminale płatnicze („Karty
  w panelu”), Gotówka do koperty z rozbiciem, Gotówka w kasie (policzona, „Powinno być”), Platformy dostaw,
  Notatka z „Zapisz podsumowanie”, Petty cash.
  terminale (kilka, nazwa i kwota), policzona gotówka i notatka (`day_reports`, `panel_save_day_report`), petty cash
  (wydatki i wpłaty z kasy, `petty_cash`, `panel_add_petty`, `panel_delete_petty`); zgodność kwot zielona albo żółta różnica.
  Od 0079 (8.11.2026, prośby użytkownika): „Zamówienia netto” (opłacone bez anulowanych i pustych;
  „Część rachunku” ma ten sam stolik i chwilę otwarcia, więc liczy się raz z resztą rachunku, `orders_net`),
  „Średni rachunek” (netto z raportu dobowego, nowe pole „Netto z raportu”, `day_reports.fiscal_net_grosze`,
  `panel_save_day_report(p_fiscal_net)`; bez niego netto z panelu ze stawek menu, `revenue_net`, dostawa jak 8%;
  `averageBill`), „Kaucja” (składniki z kaucją w Inwentaryzacji, `kaucja_grosze`, `kaucja_count`) i „Gotówka do
  koperty” (`envelopeCash`: raport dobowy minus karta online i zadatki, minus terminale (suma wpisanych, bez nich
  karty z panelu; bez napiwków kartą, których nie ma w raporcie), minus przelewy i inne, minus kaucja; liczona na
  żywo z rozbiciem).
  Kalendarz (0080, Management → `/kalendarz`, uprawnienie `calendar`, w 0080 dostały je stanowiska ze `staff`,
  `day_close` albo `schedule`; `features/calendar/calendar_screen.dart`; zadanie „Kalendarz” z Todoist, wygląd jak
  Notion Calendar): po lewej `SidePanel` z „Nowe wydarzenie”, małym miesiącem (dziś na czerwono, zaznaczony zakres)
  i przełącznikami rodzajów; u góry miesiąc, „Dziś”, strzałki i widok Dzień / Tydzień / Miesiąc. Tydzień i dzień:
  siatka godzin (48 px na godzinę, co 15 min), pas „cały dzień”, czerwona kreska teraz; przeciąganie pustego miejsca
  tworzy wydarzenie, przeciąganie wydarzenia je przesuwa, dolna krawędź zmienia koniec; nakładające się stoją obok
  siebie (`layoutDay`, `PlacedEvent`). Miesiąc: wydarzenia w dniach, „+N więcej”, kliknięcie dnia otwiera dzień.
  Po prawej panel wydarzenia (`_EventPanel`): nazwa, rodzaj, cały dzień, od–do, kolor, opis, działy „Menu na
  wydarzenie”, kto dodał. Klawisze T, D, W, M, J/K i strzałki, Esc (nie w polach tekstowych). Rodzaje
  (`calendar_events.kind`): `special` (wydarzenie specjalne: promocja, zimowe menu; widzą goście, RLS
  `calendar_events_public` dla anon) i `staff` (spotkanie, szkolenie; tylko obsługa lokalu,
  `has_staff_role(..., 'staff')`). Zapis `panel_save_calendar_event` (najwyżej 400 dni, autor `private.note_author`),
  `panel_delete_calendar_event` (nie, gdy jest dział menu na wydarzenie). Menu tylko na wydarzenie: Menu → dział →
  „Tylko na wydarzenie…” (`menu_sections.event_id`, `setSectionEvent`, podpis „Tylko na: …”); poza czasem
  wydarzenia dział znika u gościa, w Zamówieniach panelu i u kelnera (`MenuSection.visibleAt`), a baza nie przyjmuje
  takiej pozycji (trigger `order_items_event_menu`, `private.event_menu_check`, liczy `scheduled_for` albo teraz).
  Table: sekcja „Wydarzenia” nad „Godziny otwarcia” na stronie lokalu (`_EventsCard`, `RestaurantEvent`,
  `restaurantEventWhen`, najwyżej 6 trwających albo przyszłych, „TRWA TERAZ”). Table for employees: zakładka
  Kalendarz (dawniej Grafik, `schedule_screen.dart`) pokazuje wydarzenia ze wszystkich lokali pracownika jako kropki
  w siatce i karty pod wybranym dniem (`calendar_screen.dart`: `StaffEvent`, `staffCalendarProvider`,
  `CalendarEventTile`, `eventColor`); „+” przy uprawnieniu `calendar` dodaje wydarzenie (`AddEventSheet`,
  `panel_save_calendar_event` z `p_member_id`).
  Zamknięcie dnia (0079, „Ustawienia lokalu” → „Zamknięcie dnia”, `restaurants.day_close` 00:00–08:00, co 30 min do
  06:00 w panelu): lokal otwarty do 2 w nocy ustawia 02:00 i sprzedaż do tej godziny liczy się do poprzedniego dnia.
  Baza: `private.day_close`, `private.business_day`, przesunięte `private.day_range` (podsumowanie dnia) i
  `private.month_range` (eksport, godziny i statystyki pracowników), `panel_sales_stats` i `panel_stats` dzień po
  dniu (godziny w „Sprzedaży w godzinach” zostają prawdziwe), „dziś” w `panel_kitchen_stats`; `panel_my_restaurants`
  zwraca `day_close`. Panel: `PanelRestaurant.dayClose`, `dayCloseProvider`, `businessDayOf`, `businessDayStart`,
  `businessToday`: „dziś” w Podsumowaniu dnia i Historii zamówień, zakres Historii zamówień, „Zakończone dziś”
  w Dostawach, „Dzisiaj” w statystykach zespołu, wcześniejsze dni w Niezamkniętych. Logi zostają od północy.
  Platformy dostaw (0067): lokal wpisuje je w „Ustawienia lokalu” → „Platformy dostaw” (np. Glovo, Uber Eats, Wolt;
  `restaurants.delivery_platforms`, `panel_set_delivery_platforms`), a w podsumowaniu dnia kwotę każdej platformy
  (`day_reports.platforms` jsonb, `panel_save_day_report(p_platforms)`); suma osobno, poza kasą fiskalną i „Powinno być”.
  Godziny pracy (uprawnienie `timesheet`; wcześniej „Czas pracy” w Pracownikach): miesiąc z sumą godzin każdego pracownika
  (rozwijane zmiany) albo tydzień dzień po dniu; poprawka zmiany co do minuty (`panel_save_shift` z `p_editor_id`)
  zapamiętuje godziny sprzed niej (`staff_shifts.original_*`, `edited_at`), poprawione są żółte z różnicą („+0:15”).
  Okno poprawki ma osobny dzień początku i końca (zmiana może trwać przez północ albo dłużej niż dobę; koniec innego
  dnia na liście jako „18:09 (2.10)”). Zmiany i grafik odświeżają się na żywo (`TableLive`: kanał zakłada się od nowa
  po zerwaniu połączenia, a dane i tak co minutę), czas trwającej zmiany rośnie co 30 s (`clockProvider`).
  Kody rabatowe (uprawnienie `discounts`, `discount_codes`): procent albo kwota, ważność od–do, limit użyć łącznie,
  włączanie; od 0063 minimalna kwota rachunku (`min_total_grosze`; rabat dopiero od niej, liczona od całego rachunku
  przed rabatem, także przy płatności za część; kopiowana do `reservations`/`orders.discount_min_grosze` przy użyciu
  kodu; poniżej progu `panel_order_due` zwraca `discount_missing`, a zamknięcie pokazuje „Brakuje …” i nie liczy
  użycia) i limit na jednego gościa (`max_uses_per_guest`, liczy rezerwacje konta w aplikacji bez odwołanych,
  trigger `reservations_discount_guard` i `guest_check_discount`);
  gość wpisuje kod przy rezerwacji w aplikacji (`guest_check_discount`, `book_table(p_discount_code)`), rabat odejmuje się
  od rachunku stolika (procent od każdej części, kwota raz; odwołanie rezerwacji oddaje użycie). Eksport (uprawnienie
  `export`, `panel_export_month`): za miesiąc rachunki z VAT (rabat rozłożony proporcjonalnie na stawki), zestawienie
  dzienne, czas pracy z wynagrodzeniem brutto i netto, petty cash. Od 0.21.0 „Zapisz PDF” (`export_pdf.dart`: A4,
  szerokie tabele poziomo, Geist z `table_core`, nagłówek tabeli na każdej stronie, suma pogrubiona, numery stron),
  obok mała ikona CSV dla Excela (średnik, przecinek, UTF-8 z BOM). Obie postaci z tej samej `ExportTable`
  (`export_csv.dart`: `salesTable`, `dailyTable`, `hoursTable`, `pettyTable`; CSV bez wiersza sumy jak dotąd poza
  rachunkami). Historia zamówień pokazuje obrót tylko z uprawnieniem `revenue`; wyszukiwanie w panelu po lewej
  szuka po imieniu, firmie, telefonie (ostatnie 9 cyfr) i adresie ze wszystkich dni (`panel_order_search`,
  najwyżej 100 zamkniętych i anulowanych, wiersz z dniem, telefonem i adresem).
  Niezamknięte zamówienia (`/niezamkniete`, uprawnienie `day_close`, `unclosed_screen.dart`, `unclosedOrdersProvider`
  na żywo): otwarte rachunki i niezakończone zamówienia na wynos ze wszystkich dni, z poprzednich dni osobno na górze
  (czerwone), filtr Wszystkie / Na sali / Na wynos, kto otworzył, pozycje (niewysłane, na kuchni, do wydania), kwota;
  „Otwórz rachunek” (`/zamowienia?stolik=`), „Otwórz” (Dostawy, Odbiór albo szkic w Zamówieniach), „Zamknij”
  (`SettleDialog`, z `orders_close`).
- Informacje dla pracowników (0062, Pracownicy → `/informacje`, `features/staff/announcements_screen.dart`):
  osoba z uprawnieniem `announcements` (w 0062 dostały je stanowiska z `staff`, ALL ma zawsze, właściciel hasłem konta)
  pisze tytuł i treść, wybiera odbiorców (Wszyscy / Pracujący tego dnia: przyjęte godziny w grafiku albo zmiana w dniu
  wysłania / Stanowiska / Osoby) i „Teraz” albo „Zaplanuj” (dzień i godzina); zmienia, usuwa, widzi „Przeczytało 3 z 8”
  i filtr Wszystkie / Wysłane / Zaplanowane. Reszta widzi tylko wysłane do siebie i „Przeczytane”. Tabele
  `staff_announcements`, `staff_announcement_reads` (RLS bez zasad, tylko funkcje): `panel_announcements`,
  `panel_save_announcement`, `panel_delete_announcement`, `panel_read_announcement`, `staff_announcements`,
  `staff_read_announcement`; odbiorcy liczone w `private.announcement_for`.
  Nowe uprawnienia `revenue`, `day_close`, `discounts`, `export` dostały w 0048 stanowiska z `staff` albo `stats`.
- Analiza oszustw (0070) działa w tle, bez zakładki (zakładkę „Analiza oszustw” `/oszustwa` usunęliśmy 31.10.2026
  na prośbę użytkownika; uprawnienie `fraud` zostało w bazie, w oknie stanowiska go nie ma). Ryzyko widać przy
  zamówieniu w Dostawach i Odbiorze (`features/deliveries/order_risk.dart`). Każde zamówienie gościa z aplikacji
  (dostawa, odbiór) dostaje
  ocenę 0–100 w `order_risks` (RLS bez zasad, tylko funkcje; trigger `orders_risk` na końcu transakcji zapisuje IP
  z nagłówków `private.request_ip` i liczy `private.fraud_assess`). Sygnały z punktami: ten sam gość (konto albo
  numer) w całym Table z kilkoma zamówieniami po co najmniej 5 sztuk jednego dania, dużo zamówień w 24 h, duża
  ilość w zamówieniu, kwota 3× wyższa niż zwykle w lokalu, nowe konto z dużą kwotą, nieudane płatności kartą,
  odrzucone zamówienia, ten sam numer albo IP na kilku kontach, IP z ipinfo.io (inny kraj, VPN/proxy/Tor/serwer,
  odległość od lokalu). Średnie ryzyko od 25, wysokie od 50. IP sprawdza funkcja Edge `fraud-ip`
  (`supabase/functions/fraud-ip`, token użytkownika, `panel_fraud_ip_input`, `panel_fraud_apply_ip`; sekret
  `IPINFO_TOKEN` wpisuje użytkownik), wywoływana przez panel raz na sesję dla niesprawdzonych zamówień
  (`orderRisksProvider`, który panel trzyma włączony na każdej zakładce w `shell.dart`, odświeża się przy nowym
  zamówieniu na wynos). Dostawy i Odbiór: znaczek „Ryzyko N” na karcie każdego zamówienia z aplikacji, także
  niskie (`RiskChip`, okno `showRiskDialog` z sygnałami i IP). AVS i CVV dojdą z operatorem płatności. Limity zamówień z aplikacji:
  „Ustawienia lokalu” → „Dostawa i odbiór” (`restaurants.takeaway_max_items`, `takeaway_max_per_item`; trigger
  `order_items_takeaway_limits` tylko dla pozycji dodanych przez gościa), w Table koszyk blokuje „+” i pokazuje
  przekroczenie (`RestaurantDetail.cartLimitProblem`, `canAddMore`).
- Logi i Time Machine (0072, pasek boczny pod „Ustawienia lokalu” → `/logi`, uprawnienie `activity` w grupie Lokal,
  w 0072 dostały je stanowiska z `day_close` albo `staff`; `features/activity/activity_screen.dart`). Układ jak
  Pracownicy (`SidePanelLayout`, `SidePanel`, od 2.11.2026): po lewej zwijany panel z jedną zakładką „Lista” (od
  4.11.2026, prośba użytkownika; wcześniej „Zdarzenia” i zakładka „Time Machine” z planem sali w chwili, stolikami,
  na wynos i osobami na zmianie: usunięta), wyszukiwaniem (tytuł, szczegóły, osoba), dniem (`StepSwitcher`
  z kalendarzem), wierszem „Time Machine” z przełącznikiem (`_MachineSwitch`, jak w UniFi) i filtrami z liczbą zdarzeń
  dnia (`FilterSection`: Rodzaj z kropką w kolorze grupy, `activityGroupLabel`; Osoba, w tym „Bez osoby”; puste grupy
  nie filtrują). Po prawej tabela jak Zespół (`_EventTable`: godzina z sekundami, zdarzenie z ikoną w kolorze grupy,
  szczegóły, osoba, kwota), najnowsze u góry. Time Machine działa na liście, wzór: film z UniFi (porty w tabeli
  zmieniają się razem z osią): włączony wysuwa zza panelu oś czasu (`sheet` w `SidePanelLayout`, jak okno dodawania
  w Pracownikach; nad osią „Na żywo / Historia”), a lista pokazuje dzień w wybranej chwili: kreska z godziną między
  wierszami (`_TimeMark`), zdarzenia do niej zwykłe, ostatnie przed nią zaznaczone (tło i kreska akcentu),
  późniejsze zamglone (przezroczystość 0,35 i lekkie rozmycie, jak odłączone porty w UniFi). Lista przewija się do
  kreski tylko wtedy, gdy kreska przeskoczy zdarzenie i wyjdzie poza widok (stała wysokość wiersza `_rowExtent`; na
  żywo nowe zdarzenia nie zabierają czytanego miejsca). Kliknięcie wiersza przewija oś do jego chwili co do
  mikrosekundy (czasy z bazy mają mikrosekundy) i zaznacza wiersze jego rachunku; przy wyłączonym Time Machine
  najpierw go włącza (`_openEvent`). Filtry działają też na oś. Oś (`_TimeRail`, kolumna `_railWidth`): godziny
  18 px od lewej krawędzi, równo z godziną na kresce (godziny pod pigułką z sekundami się nie rysują), przycięta do
  swojej karty (godziny nie wchodzą na przyciski skali). Oś przesuwa się pod stałą kreską z godziną i sekundami
  u góry (wcześniejsze chwile niżej; przeciąganie z bezwładnością, kółko myszy, Ctrl + kółko albo suwak −/+ zmienia
  skalę, kliknięcie wybiera chwilę), na osi ikony zdarzeń w kolorach grup (bliskie razem z liczbą, podpowiedź
  z listą, kliknięcie płynnie przewija oś do zdarzenia: `_jump`, 360–800 ms według odległości, przy „Ogranicz ruch”
  od razu; przeciąganie przerywa przewijanie). „Na żywo” trzyma chwilę na teraz (co sekundę, tylko przy włączonym
  Time Machine; dziś dane odświeżają się z zamówieniami), „Historia” ma dzień. Nic nowego się nie zapisuje:
  `panel_activity` składa zdarzenia z chwil przy zamówieniach, pozycjach (dodane, na kuchnię, gotowe, wydane,
  anulowane; to samo danie łączy `private.merge_item_names`), płatnościach, dostawach, rezerwacjach, zmianach
  i inwentaryzacji. Stan sali w chwili (`panel_time_machine_day`, 0073, model `TimeMachineDay.at`,
  `timeMachineDayProvider`) został w bazie i w modelach z testami, ale ekran go już nie pokazuje (stare
  `panel_time_machine` dla jednej chwili zostało dla starszych wersji panelu).
  Doszła tylko chwila anulowania pozycji (`order_items.cancelled_at`, trigger). Model zdarzenia z polskimi tytułami
  jest w `table_core` (`ActivityEvent`). Logów nie ma w aplikacji mobilnej (usunięte na prośbę użytkownika);
  `panel_activity(p_member_id)` zostało w bazie.
- Dane lokalu: logo, dane, poziom cen, dane właściciela, godziny, dni wyjątkowe.
- Flota (`/flota`, uprawnienie `fleet`, 0045) w układzie jak Pracownicy (4.11.2026, prośba użytkownika: lista zamiast
  kafli; `SidePanel` z „Dodaj pojazd” i filtrami Rodzaj / Stan / Dziś, tabela `_VehicleTable`: pojazd z ikoną
  w kolorze rodzaju i odznaką „Nieużywany”, rejestracja, VIN, dzisiejszy dostawca z zieloną kropką, ostatnia
  notatka z „+N”, aparat „Przebieg i zdjęcia”; kliknięcie wiersza otwiera okno pojazdu): `vehicles` (auto, skuter,
  rower, inny; nazwa, rejestracja unikalna
  w lokalu, VIN 17 znaków bez I/O/Q unikalny w lokalu (0046), w użyciu), `panel_save_vehicle`,
  `panel_delete_vehicle`. Od 0068 auto nie ma stałego dostawcy (`vehicles.member_id` zawsze puste): auto przypisuje się
  na dzień (`vehicle_days`, jedno auto i jeden dostawca na dzień, `panel_set_vehicle_day`, `panel_vehicle_days`) w oknie
  dnia Grafiku (`VehicleDayPicker`, zapisuje się od razu, poza szkicem) albo w Dostawach (stuknięcie dostawcy w pasku
  „na zmianie”); dostawca może też sam wybrać auto przy kontroli. Kontrola auta (`vehicle_checks`): w lokalu
  z aktywnymi pojazdami (`private.vehicle_check_required`) dostawca przed pierwszym kursem wpisuje przebieg i robi
  cztery zdjęcia dookoła (przód, tył, boki), a przed końcem zmiany to samo jeszcze raz (`staff_vehicle_status`,
  `staff_vehicle_check`; przebieg nie mniejszy niż ostatni, wymagany dla auta i skutera). Bez kontroli początku
  kolejka nie daje mu kursów (`private.vehicle_ready` w `private.courier_queue`). Zdjęcia: image_picker 1280 px,
  jakość 72, prywatny zasobnik `vehicle-photos` (`{lokal}/{auto}/{dzień}/...jpg`, `private.can_use_vehicle_photos`).
  Telefon: `vehicle_check.dart` (`VehicleCheckScreen`), otwiera się po zeskanowaniu kodu i przy „Zakończ zmianę”,
  karta przypomnienia w Dostawach. Panel: na karcie pojazdu „Dziś: dostawca” i „Przebieg i zdjęcia”
  (`features/fleet/vehicle_days.dart`, `VehicleChecksDialog`: 30 dni, dzień po dniu z przejechanymi km, zdjęcia
  z podpisanych adresów, kliknięcie powiększa). Notatki o pojeździe (0047): `vehicle_notes` (autor z zalogowanego pracownika albo
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
  zamówienia, wydatki, ostatnia wizyta, najbliższa rezerwacja. Bez rzędu nad listą (sortowania i liczników) i bez
  daty albo liczby przy kliencie na liście (31.10.2026, prośba użytkownika); lista w kolejności ostatniej wizyty,
  liczby w podsumowaniu. Układ: lista z wyszukiwaniem po lewej, po prawej
  wybrany klient (liczby, historia `panel_customer_history`, notatki) albo podsumowanie wszystkich. Klucz klienta
  liczy `private.customer_key` (0047; od 0059 najpierw telefon: numer z konta w aplikacji albo wpisany, ostatnie
  9 cyfr `private.customer_phone_key`, potem konto, potem imię, więc ten sam numer z aplikacji, panelu i rezerwacji
  to jeden klient). Klient z zamówienia na wynos dopisuje się sam do `restaurant_customers` (trigger
  `orders_remember_customer` przy przyjęciu i zmianie danych: imię, firma, NIP, ostatni adres), jest na liście od razu,
  a w karcie klienta widać firmę z NIP-em i adres (`panel_customers` zwraca `company`, `nip`, `address`). Notatki o kliencie: `customer_notes` (RLS: tylko obsługa lokalu,
  `has_staff_role`; goście ich nie widzą), `panel_add_customer_note`, `panel_delete_customer_note`, wspólny widżet
  `NotesView` (`shared/notes_view.dart`, Enter dodaje). Statystyki zespołu (`/zespol`, uprawnienie `stats`):
  `panel_team_stats` (godziny, zmiany, rachunki, pozycje, kursy, goście i pominięcia liczby gości, napiwki gotówką
  i kartą z `order_payments.member_id`, zarobek ze stawką widoczną od razu, sprzedaż na osobę) i `panel_team_summary`
  (obrót lokalu, goście, pominięcia, napiwki; kafel „Wypłaty z obrotu” = wynagrodzenia brutto / obrót); okres
  Dzisiaj / 7 dni / 14 dni / W tym miesiącu (`TeamPeriod`, `p_from` albo `p_days` albo `p_month`).
- Zakładki nie mają tytułów ani opisów (`PageHeader`: tylko akcje i rząd zakładek); nazwę widać w menu bocznym.
  Przyciski (`actions`) stoją po prawej w tym samym rzędzie co zakładki i filtry (`below`); osobny rząd nad nimi
  tylko z `actionsInRow: false`. Edycja sali ma same akcje (strefy są na planie).
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
  (szczegóły ze statystykami `panel_member_stats`). Zakładka „Pracownicy” wygląda jak „People” w UniFi (od 0.28.0,
  wzory od użytkownika; `staff_screen.dart`; panel, filtry, uchwyt, `PanelAction` i `RowBadge` są wspólne z Logami,
  Flotą i Statystykami w `shared/side_panel.dart`).
  Po lewej panel (`SidePanel`, 288 px) z zakładkami Zespół / Stanowiska
  z ikonami jak w UniFi (`SegmentedTabs(expand: true, icons:)`, `AppIcons.list` i `AppIcons.userGear`; według uprawnień
  `staff`/`staff_logins` i `positions`), wyszukiwaniem (imię albo telefon), wyborem lokalu pod wyszukiwaniem
  (`_RestaurantPicker`, jak wybór firmy w UniFi; widzi go tylko osoba ze stanowiskiem ALL albo pełny dostęp
  właściciela, zmienia lokal całego panelu), „Dodaj pracownika” („Dodaj stanowisko” w Stanowiskach) i filtrami
  z liczbą osób (`FilterSection`: Stanowisko; Stan: Na zmianie / Aktywni / Nieaktywni / Zwolnieni, na start
  zaznaczeni Aktywni; pusta grupa nie filtruje; pola wyboru `PanelCheck` bez okrągłej poświaty po najechaniu). Panel
  zwija uchwyt na kresce między panelem a treścią (`_EdgeButton` w `SidePanelLayout`: prostokąt 20×40 z zaokrąglonymi
  rogami, od 1.11.2026 na prośbę użytkownika, wcześniej kółko), z animacją: panel
  odjeżdża w lewo i gaśnie, przycisk jedzie z kreską (280 ms, przy „Ogranicz ruch” od razu). Filtry, zwinięte grupy i zwinięcie panelu są wspólne dla Pracowników i Grafiku
  (`_panelProvider`). Grafik to osobna podzakładka (`ScheduleScreen`, `/grafik`) z tym samym panelem: wybór okresu
  i „Edytuj” / „Anuluj” / „Zapisz” są w panelu zamiast „Dodaj pracownika”, siatka bez zmian. Po prawej Zespół jako
  tabela (`_TeamTable`: pole wyboru, imię z odznakami ALL / Ty / Nieaktywny / Zwolniony, telefon, stanowisko jako
  znaczek z „+1” za dodatkowe, Teraz: zielona kropka „od 18:50”, godziny w tym tygodniu, kod). Zaznaczeni (tylko
  z uprawnieniem `staff`) dostają pasek nad tabelą (`_SelectionBar`: „Aktywny”, „Nieaktywny”, „Zwolnij”;
  `panel_set_staff_status`, 0075). Zwolniony (`staff_members.dismissed_at`) jest nieaktywny, kończy trwającą zmianę
  i znika z przyszłego grafiku, a jego godziny pracy zostają (usunięcie pracownika kasowałoby jego zmiany);
  „Aktywny” przywraca go. Siebie nie da się wyłączyć ani zwolnić. Kliknięty pracownik pokazuje szczegóły w miejscu
  listy, nie w osobnym oknie (`_MemberDetails`: „‹ Zespół” wraca, dane, uprawnienia, kod i „Zmień kod”, statystyki
  z miesiąca; tak samo w Grafiku po kliknięciu nazwiska, „‹ Grafik”). Nowego pracownika dodaje, a istniejącego
  zmienia („Edytuj” w szczegółach) okno obok panelu jak „Add New Person” w UniFi (`_MemberSheet` w `_SheetFrame`:
  imię i nazwisko, telefon, stanowisko jako karty po dwie z samą nazwą, bez opisów, i kartą „Nowe stanowisko”,
  dodatkowe stanowiska przyciskiem „+ Dodaj stanowisko”, umowa i stawka, kolor, przy zmianie „Aktywny” i „Usuń”;
  zapis `_persistMember`). Nowe stanowisko to to samo okno dla roli (`_RoleEditor`: nazwa, uprawnienia w grupach
  z „Zaznacz wszystkie”). „Nowe stanowisko” z okna pracownika otwiera okno stanowiska nad nim, a po zapisie wraca
  z nowym stanowiskiem zaznaczonym. Stanowiska jako tabela (`_PositionsTable`: nazwa, systemowe z kłódką,
  uprawnienia, liczba pracowników); kliknięte stanowisko pokazuje się w miejscu tabeli (`_RoleEditor(inline: true)`:
  „‹ Stanowiska”, nazwa i uprawnienia w dwóch kolumnach, „Usuń” i „Zapisz” u góry, obok kto ma to stanowisko;
  systemowe tylko do podglądu).
  `SegmentedTabs` ma podświetlenie (`_SlidingSegments`), które przesuwa się do wybranej opcji (`IconTabs` od 1.11.2026 bez pigułki). Każdy pracownik ma czterocyfrowy kod, unikalny w lokalu
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
  Pasek boczny pokazuje zakładki zalogowanego pracownika; „Wyloguj” jest ikoną obok motywu, a „Zakończ zmianę”
  w menu pod jego kółkiem. Zakładka z pustym zbiorem w `_routePermissions` jest dla każdego (`canOpenRoute`):
  tak jest z „Informacje dla pracowników”. Właściciel otwiera panel hasłem konta restauracji (`ActingMember.account()`).
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
- Grafik (podzakładka „Grafik” `/grafik` w grupie Pracownicy, `ScheduleScreen`, uprawnienie `schedule`): pracownik zgłasza w aplikacji, od której do której może
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
  `private.schedule_deadline`); po nim aplikacja nie przyjmuje zgłoszeń (`check_schedule_deadline`). Okno zgłaszania
  (0081, 9.11.2026, prośba użytkownika): pracownik zgłasza godziny i „Nie mogę” tylko na jeden okres, pierwszy po
  bieżącym, którego termin jeszcze nie minął (bez terminu: następny okres); ani wcześniej, ani później
  (`private.schedule_window`, `private.schedule_period_end`, `check_schedule_window` w `staff_submit_hours`
  i `staff_mark_unavailable`; wycofanie `staff_delete_hours` bez zmian). Aplikacja: `staff_schedule_window`
  (`scheduleWindowProvider`, okno i termin). Od 0062 godziny
  mogą iść przez północ (koniec wcześniej niż początek = następny dzień, np. 18:00–02:00 to 8 h; w bazie
  `ends <> starts`), w panelu „następnego dnia” przy godzinach i suma godzin z doliczoną dobą. Uwaga pracownika
  na tydzień (`staff_week_notes`, `staff_set_week_note`; w panelu ikona przy nazwisku). Pracownik może mieć kilka
  stanowisk (`staff_member_positions`, `panel_set_member_positions`, okno pracownika „Dodatkowe stanowiska”; uprawnienia
  to suma, `private.member_permissions`, dostawca: `private.is_courier`), w grafiku stanowisko na dzień
  (`staff_schedule.position_id`, wybór w oknie dnia, widać w aplikacji). Pod siatką: przyjętych osób, godziny pracy dnia
  i ile osób na jakim stanowisku; kolumna „Tydzień” z godzinami pracownika.
- Statystyki (Management) w układzie jak Pracownicy (4.11.2026, prośba użytkownika; kafle i wykresy zostały): po
  lewej zwijany panel (bez wyszukiwania) z zakładkami Sprzedaż (`panel_sales_stats`) i Rezerwacje i goście
  i w Sprzedaży filtrami z liczbą rachunków w okresie: Rodzaj zamówienia (Na miejscu, Dostawa, Odbiór
  osobisty) i Obsługa (kto otworzył rachunek, „Bez przypisania” na końcu). Filtry liczy baza (0076:
  `panel_sales_stats(p_kinds, p_members)`, `''` = bez przypisania, liczby bez filtrów w `facets`; stara wersja bez
  filtrów usunięta, bo domyślne parametry obsługują starsze panele); w panelu `SalesQuery` z filtrami po przecinku.
  Okres 7D / 30D / 90D stoi w prawym górnym rogu treści, nad kaflami (5.11.2026, prośba użytkownika; wcześniej
  w panelu jako „7 dni”). W „Rezerwacje i goście” kafel „Polubienia” (wszystkie i „+N w tym okresie”, także plan Free)
  i wykres nowych polubień dzień po dniu (`panel_stats` od 0063: `likes`, `likes_total`); kafle mają równą wysokość. W Sprzedaży tabela „Sprzedaż w godzinach” (godziny z zamówieniami: liczba, kwota, na miejscu,
  dostawa, odbiór osobisty, wiersz „Razem”; `hourly` z `dine_in`, `delivery`, `pickup` od 0062). Historia zamówień jest osobną zakładką w grupie Rezerwacje.
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
- Edycja sali działa jak UniFi Design Center (od 1.11.2026, prośba użytkownika; `floor_screen.dart`, obsługa myszy,
  dotyku i klawiatury w `floor_plan_input.dart`, geometria w `plan_geometry.dart`). Plan na całą kartę, nad nim
  pływające panele: strefy i „+” w lewym górnym rogu, po prawej właściwości (nic nie zaznaczone: „Dodaj na plan”
  z gotowymi stolikami 2-, 4-, 6-osobowym, okrągłym, miejscem i elementem stałym do przeciągnięcia albo kliknięcia,
  pod nim Strefa; kilka zaznaczonych: wyrównanie, równe odstępy, Duplikuj, Usuń), w lewym dolnym rogu Cofnij,
  Ponów, Dopasuj, Przybliż, Oddal i podziałka, na dole pasek narzędzi (`IconTabs`): Zaznacz V, Przesuń widok H,
  Ściana W, Element stały R, Stolik T, Miejsce M, z podpowiedzią nad paskiem (przy zaznaczaniu tylko wtedy, gdy nic
  nie jest zaznaczone). Od 2.11.2026 (użytkownik: „tragiczna pod względem działania”): kierownik (`canManage`)
  edytuje od razu, bez „Edytuj układ” (`_loadDraft` w build: na start, po zapisie na świeżych danych z id i po
  „Odrzuć zmiany”; nagłówek „Odrzuć zmiany” i „Zapisz układ”, oba tylko przy zmianach); reszta obsługi widzi salę
  na żywo. Pola wymiarów (stolik, element, strefa) zapisują się po Enter albo wyjściu z pola (`_Commit`, bez
  „Zastosuj”; zły wpis wraca do bieżącej wartości), a zmiana z panelu nie zabiera zaznaczenia (`_update`). Widok
  (`PlanView`: skala px/cm i początek strefy) zmienia tylko obraz: kółko myszy przybliża wokół kursora, gładzik
  i dwa palce przesuwają i przybliżają, przeciąganie pustego miejsca, spacja, środkowy przycisk albo „Przesuń
  widok” przesuwa, Ctrl+0 dopasowuje, Ctrl+plus/minus. Zaznaczanie: klik (stolik także za krzesło), Shift albo Ctrl
  dodaje, ramka tylko z Shift albo Ctrl po pustym miejscu (obiekty, które przecina), Ctrl+A. Prawy przycisk:
  menu (`_contextMenu`; na obiekcie Duplikuj, Obróć o 90°, Kopiuj, Usuń, na pustym miejscu Wklej, Zaznacz
  wszystko, Dopasuj widok). Przeciąganie przesuwa całe zaznaczenie, a złapany obiekt staje na kratce co 10 cm
  (linie prowadzące do krawędzi i środków innych obiektów i strefy mają pierwszeństwo, Alt bez przyciągania),
  strzałki o 10 cm (Shift 50, Alt 1). Jeden zaznaczony ma uchwyty: rogi i boki
  (wymiary co 5 cm, przeciwna krawędź stoi), kółko obrotu nad krzesłami (co 15°, Shift co 1°), krzesła (krzesło
  zaznaczonego stolika przesuwa samo krzesło, niezaznaczonego łapie cały stolik); cienka
  ściana ma uchwyty tylko na końcach. Krawędzie strefy (prawa, dolna, róg) zmieniają jej wymiary co 10 cm, a w edycji
  wymiary strefy są przy górnej i lewej krawędzi. Ściana to element stały 12 cm (`wallElement`, wydłużony o pół
  grubości, żeby narożniki się domykały, kąt 0–179°): klik w kolejne narożniki, kąt co 15° (Shift dowolny),
  przyciąganie do końców innych ścian, Enter, Esc, dwuklik albo prawy przycisk kończy i wraca do zaznaczania
  (`_finishWall`, kolejna ściana od W). Plan i pływające panele mają osobne warstwy (`RepaintBoundary`), żeby ruch
  myszy nie odrysowywał cieni paneli. Delete usuwa zaznaczenie
  (pyta tylko o zapisane stoliki), Ctrl+C/V/D kopiuje kilka obiektów naraz, Ctrl+Z i Ctrl+Shift+Z albo Ctrl+Y.
  Na żywo ten sam plan: klik stolika pokazuje jego rezerwacje, przeciąganie przesuwa widok. Rezerwacje i Logi
  używają `FloorCanvas` bez widoku (strefa dopasowana do miejsca; podpis stolika może wystawać poza mały blat,
  `OverflowBox`). Zmiana nazwy strefy przenosi też jej elementy,
  a usunięcie pustej strefy usuwa jej elementy stałe.
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
  (historia zamówień i sprzedaż je pokazują). Historia zamkniętych rachunków: „Zamówienia” → „Historia zamówień”,
  w układzie jak Statystyki (5.11.2026, prośba użytkownika; `order_history_screen.dart`): po lewej zwijany panel
  z wyszukiwaniem i filtrami z liczbą rachunków dnia (Rodzaj: W restauracji / Dostawy / Odbiór osobisty,
  `HistoryKind`; Stan: Opłacone / Anulowane; puste grupy nie filtrują), dzień (`StepSwitcher`) w prawym górnym
  rogu, pod nim kafle (liczą wybrane rodzaje bez filtra stanu), lista z kwotą z dostawą i szczegóły rachunku.
  Paragon fiskalny i terminal płatniczy: „Drukarki i terminal” → „Paragony” i „Terminal” (niżej).
- Drukarki i terminal (pasek boczny → „Drukarki i terminal”, `/drukarki`, uprawnienie `profile` albo `orders`;
  `features/printing`, 6.11.2026, prośby użytkownika). W panelu po lewej zakładki Etykiety / Paragony / Terminal.
  Paragony (0078, `fiscal_printing.dart`, `novitus_xml.dart`, `fiscal_receipt.dart`, `cp1250.dart`): drukarka fiskalna
  albo kasoterminal na tym komputerze (`panel_drukarka_fiskalna`), na razie tylko protokół XML Novitus przez sieć
  (publiczny opis „Description of XML communication protocol” 1.0.2, novitus.pl/file/get/701; nazwy atrybutów jak
  w działającej bibliotece litex.novitus_xml: `ptu`, `quantityunit`, bo angielski opis myli je z „rate”): pakiety
  `<packet>` w Windows-1250, port domyślnie 6001, po każdej komendzie `<enq/>` (`lastcommanderror`) i numer błędu
  z `<error action="get"/>`; stawki PTU czytane z drukarki (`<taxrates action="get">`) i dopasowane do VAT z menu;
  paragon = aktywne pozycje (nazwa z wariantem, ilość, cena z dodatkami), dostawa (stawka do wyboru, domyślnie 8%),
  rabat do sumy, formy płatności (tylko gdy suma się zgadza; zadatek jako przelew), NIP firmy, numer systemowy
  („D12”, „O12”, „R” + początek id); otwarty paragon po przerwie anulowany przed nowym. Jeden paragon na rachunek:
  `fiscal_receipts` (RLS: czyta obsługa, zapis tylko funkcjami) i `panel_fiscal_claim` (rezerwacja przed wydrukiem,
  `p_force` po przerwanym wydruku), `panel_fiscal_done` (numer z drukarki), `panel_fiscal_release` (błąd),
  `panel_fiscal_pending` (kolejka). „Kasa główna” (`fiscalAutoPrintProvider` w `shell.dart`): ten komputer drukuje
  paragon za każdy opłacony rachunek lokalu zamknięty od włączenia (panel, telefon kelnera, wydanie na wynos),
  przy błędzie pauza minuta. Ręcznie: Historia zamówień → rachunek → „Wydrukuj paragon” (`FiscalReceiptRow`, numer
  i godzina wydrukowanego). „Wydruk niefiskalny” i „Sprawdź połączenie” (stan, tryb fiskalny/szkoleniowy, stawki).
  Posnet i Elzab nie mają publicznej dokumentacji protokołu (do zrobienia po dokumentacji od producenta).
  Terminal (`payment_terminal.dart`, `panel_terminal_platniczy`, klucze tylko na tym komputerze): Viva.com Cloud
  Terminal API (token `connect/token` z danymi „POS APIs”, `ecr/v1/transactions:sale` w groszach i walucie 985,
  odpytywanie `ecr/v1/sessions/{id}` co 2 s do 4 min, przerwanie DELETE sesji; demo albo produkcja) i Adyen
  Terminal API w chmurze (`device-api-test`/`device-api-live.adyen.com/v1/merchants/{konto}/devices/{POIID}/sync`,
  nagłówek `x-API-key`, nexo `PaymentRequest` w PLN, po 170 s `TransactionStatusRequest`, przerwanie
  `AbortRequest` na `/async`, „Sprawdź połączenie” przez `DiagnosisRequest`). Zamknięcie rachunku kartą (całość
  albo wybrane pozycje, `SettleDialog._terminal`) otwiera okno płatności (`showTerminalPayment`: kwota z napiwkiem,
  „Przerwij”), rachunek zamyka się dopiero po udanej płatności; podział „Równo” bez terminala. Polscy operatorzy
  (eService, Polcard, Elavon, PeP, PayTel) bez publicznej dokumentacji. Nic z tego nie było sprawdzone na prawdziwym
  urządzeniu (testy: udawana drukarka TCP i udawane API, `test/fiscal_terminal_test.dart`).
  Etykiety (0077, prośba użytkownika: etykiety na pudełka pizzy na wynos, edytor, wydruk testowy).
  Drukarka etykiet jest na tym komputerze (preferencje lokalne `panel_drukarka_etykiet`, `LabelPrinterSettings`):
  drukarka systemowa albo w sieci (IP, port 9100), język TSPL (Xprinter, TSC) albo ZPL (Zebra), ciemność, przerwa
  między etykietami, obrót o 180°, „Wydruk testowy” (wzór z edytora, także niezapisany, z przykładowym zamówieniem)
  i „Sam po przyjęciu zamówienia” (`labelAutoPrintProvider`, trzyma go `shell.dart`: drukuje zamówienia przyjęte
  po włączeniu, na tym komputerze, pamięta wydrukowane 3 dni w `panel_etykiety_wydrukowane`; błąd tylko w
  powiadomieniu, bez ponawiania). Ręcznie: ikona drukarki na karcie zamówienia w Dostawach i Odbiorze. Na tym
  komputerze: Xprinter XP-410B (USB, sterownik z typem danych RAW), etykiety 100 × 50 mm (od użytkownika).
  Wygląd etykiety jest wspólny dla lokalu (`label_templates`, RLS bez zasad: `panel_label_template` czyta obsługa,
  `panel_save_label_template` zapisuje `profile`; bez zapisu domyślny wzór 100 × 50 mm `LabelTemplate.standard`):
  rozmiar w mm, „Jedna etykieta na” każde danie (każda sztuka z „1/3”) albo całe zamówienie, rodzaje zamówień,
  działy menu (puste: wszystko, co robi kuchnia, bez napojów `show_in_kitchen = false`) i elementy (tekst, linia,
  ramka, kod QR, logo lokalu) z polami w klamrach (`labelFields`: {numer}, {sztuka}, {danie}, {dodatki},
  {pozycje}, {rodzaj}, {godzina}, {data}, {klient}, {telefon}, {adres}, {uwagi}, {platnosc}, {kwota}, {lokal});
  element ze wszystkimi polami pustymi znika w całości (`resolveLabelText`). Edytor (`printers_screen.dart`):
  panel po lewej (drukarka, kiedy drukować, zasady), etykieta na białym tle (przeciąganie co 0,5 mm, z Alt co 0,1,
  uchwyty rozmiaru, strzałki, Delete, Ctrl+D, Ctrl+Z / Ctrl+Shift+Z), przykład Dostawa / Odbiór, „Wydruk” pokazuje
  punkty drukarki, po prawej rozmiar etykiety z gotowymi rozmiarami albo właściwości elementu (tekst z „Wstaw pole”,
  czcionka w pt, pogrubienie, wyrównanie, biały na czarnym, „Zmniejsz, gdy się nie mieści”, położenie i rozmiar).
  Szkic przeżywa zmianę zakładki. Druk: ten sam kod rysuje edytor i etykietę w 8 punktach na mm (203 dpi,
  `rasterizeLabel`, Geist z polskimi znakami, logo rastrowane Floyd–Steinbergiem), potem BITMAP w TSPL (bit 0 =
  punkt wydrukowany) albo ^GFA w ZPL (`printer_commands.dart`). Wysyłka bez sterownika rysującego
  (`printer_transport.dart`): Windows winspool przez FFI (`ffi`, zadanie „RAW”), macOS `lp -o raw` (uprawnienie
  piaskownicy `com.apple.security.print`), sieć przez gniazdo; na tablecie tylko drukarka w sieci. Drukarka
  odłączona od USB nie zgłasza błędu: Windows trzyma zadanie w kolejce i drukuje po podłączeniu.
- Dostawy i odbiór osobisty (0039, 0040, tylko Pro): lokal włącza je w „Ustawienia lokalu” → „Dostawa i odbiór”
  (`delivery_enabled`, `pickup_enabled`, `takeaway_cash` = gotówka, `takeaway_card` = karta przy odbiorze (0074,
  domyślnie włączona), opłata, minimalne zamówienie, obszar). Gość zamawia w aplikacji Table (przycisk „Zamów”
  w lokalu, koszyk, `guest_place_order`; ceny liczy baza z menu), płaci kartą online, kartą przy odbiorze
  (`payment_choice = 'card_on_delivery'`: dostawcy przy drzwiach albo w lokalu; wydanie i dostarczenie zapisują
  płatność jako kartę, więc podsumowanie dnia liczy ją z terminalami) albo gotówką. Panel w „Nowe zamówienie”: Opłacone,
  Gotówka albo Karta przy odbiorze (`payment` w danych klienta). Uwagi do adresu (kod do klatki, piętro; z „Adres
  dostawy” w Koncie) to osobne pole tylko przy dostawie (`orders.address_note`, `p_address_note`), a „Uwagi do
  zamówienia” (`delivery_note`) są przy dostawie i odbiorze; dostawca i panel widzą je osobno. Operatora płatności jeszcze nie ma: `private.app_settings.payments_mode = 'test'`, karta opłaca się
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
  Mapy dostawców i śledzenia pozycji nie ma (0068): `staff_share_location`, `staff_courier_position` nic nie robią
  (dla starszych wersji aplikacji), `guest_courier_position` zwraca null, `courier_tracking` wyłączone, pozycje
  i trasy skasowane. Funkcja Edge `maps` i sekret `GOOGLE_MAPS_SERVER_KEY` zostały w Supabase, ale nic ich nie używa
  (do usunięcia przez użytkownika w panelu Supabase).
- Ekran kuchni (`/kuchnia`, uprawnienie `kitchen`, np. Kucharz): bileciki z pozycjami wysłanymi na kuchnię,
  pogrupowane po rachunku i chwili wysłania, najstarsze pierwsze. Czas liczony od wysłania z sekundami;
  kolory po progach z `restaurants.kitchen_warn_minutes`/`kitchen_late_minutes` (domyślnie 4 i 6 min).
  Zamówienie na wynos ma na bilecie adres dostawy z imieniem gościa albo „Odbiór osobisty · imię”.
  Stuknięcie pozycji albo „Gotowe” wywołuje `panel_kitchen_set` (sent ↔ ready, `ready_at`); cofnięta pozycja
  ma `recalled_at` i jest niebieska. Anulowane pozycje widać na czerwono. Sterowanie klawiaturą
  (1–9, strzałki, Spacja, Enter, Backspace, F, M, Esc; strzałki przechodzą między bilecikami, Spacja zbija
  i schodzi niżej, Enter zamyka bilecik i zaznacza następny), dolny pasek ze średnim czasem (`panel_kitchen_stats`),
  ustawienia (progi, wyprzedzenie zamówień na godzinę „Na wynos” i „Na dostawę”, pozycje ukryte,
  `panel_set_kitchen_config`). W ustawieniach kuchni też „Powiadomienia o rezerwacjach” na tym komputerze
  (`KitchenReservationAlertsNotifier`, preferencja lokalna; wyłączone wyciszają `ReservationAlerts` na ekranie kuchni,
  `kitchenSilent`). Pełny ekran chowa menu. Nowy bilecik dzwoni. Zamówienia na godzinę czekają w pasku
  „Zaplanowane” po prawej (tylko gdy są; godzina wejścia do kuchni, bez odliczania), o swojej porze przechodzą
  do bilecików (dzwonią) z paskiem „NA GODZINĘ · odbiór/u klienta HH:MM”. Kompletowanie pokazuje je dopiero wtedy.
- Kompletowanie (dawniej Wydanie; `/wydanie`, `features/serving`, uprawnienie `serving`, grupa Zamówienia; w 0042 dostały je stanowiska
  z `orders`): karty stolików z daniami gotowymi z kuchni (najdłużej czekające pierwsze, żółte po 2 min, czerwone
  po 4 min), stuknięcie pozycji albo „Wydane” wywołuje `panel_serve_items` (ready → served, `p_undo` cofa),
  pod kartą „Jeszcze na kuchni”. Od 0.21.0 wydana pozycja zostaje na karcie przekreślona i przygaszona jak zbita
  na kuchni (`order_items.served_at` z triggera, 0062; na karcie wydane od chwili, gdy czeka najstarsza gotowa),
  stuknięcie przekreślonej cofa wydanie; karta znika, gdy nic na niej nie czeka. Zamówienia na wynos w przygotowaniu: „Spakowane” (`panel_takeaway_ready`),
  gdy kuchnia zrobi wszystko. Nowe gotowe danie dzwoni (wyciszenie `servingMutedProvider`).
- Menu: zdjęcia dań (`menu_items.photo_url`, bucket `menu-photos`, panel zmniejsza zdjęcie do 1200 px JPG,
  goście widzą je w aplikacji Table: miniatura po prawej przy daniu, stuknięcie powiększa; menu gościa pobiera dane
  od nowa przy otwarciu i przeciągnięciem w dół, bo strona lokalu pod spodem trzyma stare). Uprawnienia: `menu` (zakładka), `menu_edit` (dania, ceny, sekcje, zdjęcia),
  `menu_availability` („Skończyło się”). Warianty (np. rozmiary, każdy z ceną), płatne dodatki, stawka VAT i „dostępne teraz”. Przy wariantach
  `price_grosze` to najniższa cena wariantu. „od” przed ceną tylko, gdy warianty mają różne ceny (`priceVaries`
  w modelach gościa, pracownika i panelu); jeden wariant (np. Tonic 200 ml) pokazuje samą cenę. „Skończyło się” może ustawić też kelner i kuchnia (`panel_set_menu_item_available`).
- Inwentaryzacja (`/inwentaryzacja`, `features/inventory`): zakładki Spis, Składniki, Dostawy i usunięcia, Historia
  (`SegmentedTabs` jak w Rezerwacjach, od 5.11.2026; tak samo „Aktywne / Zakończone dziś” w Dostawach i Odbiorze).
  Składniki (`inventory_items`: nazwa, jednostka ml/l/g/kg/szt, pojemność opakowania; usunięcie ustawia `deleted_at`,
  w historii zostają). Kaucja przy składniku (0079, `deposit_grosze`: przełącznik i 0,50 zł albo 1,00 zł w oknie
  składnika): sztuka = jedna kaucja, inne jednostki = jedna na opakowanie; suma dnia z ruchów sprzedaży opłaconych
  rachunków w Podsumowaniu dnia. Spis (`inventory_counts`, jeden otwarty na lokal, `inventory_count_lines` z ilością w opakowaniach
  oraz jednostką i pojemnością z chwili spisu): `panel_inventory_start`, `panel_inventory_set` (każda ilość zapisuje się
  od razu), `panel_inventory_finish`, `panel_inventory_discard`, lista `panel_inventory_counts`. Okres
  `restaurants.inventory_period` (day, week, two_weeks, month; `panel_set_inventory_period`), ustawia się w „Ustawienia lokalu”,
  następna inwentaryzacja liczona od ostatniej zakończonej. Uprawnienia: `inventory_edit` („Edytowanie składników”: składniki i okres)
  i `inventory_count` („Wpisywanie ilości składników”), grupa „Inwentaryzacja”. W spisie pełne opakowania i obok reszta
  w g/ml/szt (`inventory_count_lines.packages`, `loose`; `quantity` = opakowania z resztą, 6 miejsc po przecinku),
  „Razem” w mniejszej jednostce (np. mąka 50 kg: 1 op. + 2500 g = 52 500 g).
  Od 0071 (wszystko liczy się samo z ruchów `inventory_movements`, rodzaje sale, delivery, removal):
  składnik ma lokalizację (`location`, spis i lista pogrupowane, podpowiedzi w oknie składnika), nazwę opakowania
  (`pack_name`: zgrzewka, worek, puszka…, odmiana `packWord`/`packCount` w `table_core/inventory_format.dart`
  razem z `inventoryNumber`) i zwykły pojemnik. Pojemniki do ważenia lokalu (`inventory_containers`, waga pustego
  w g; Składniki → „Pojemniki”, `panel_save_inventory_container`): przy wadze w spisie wybór pojemnika, wpisuje się
  wagę z pojemnikiem, a baza zapisuje bez niego (`inventory_count_lines.gross`, `tare`, `container_name`;
  `panel_inventory_set(p_container_id)`). Spis pokazuje „Powinno być” (stan teraz) i różnicę w trakcie pisania.
  Dostawy (kiedy przyjechały, dostawca, numer dokumentu) i usunięcia (powód: przekazanie do innego lokalu, zwrot,
  strata, posiłek pracowniczy, inny; wyjaśnienie wymagane) to `inventory_docs` z `inventory_doc_lines`
  (`panel_inventory_save_doc`, `panel_inventory_docs`, `panel_inventory_delete_doc` tylko `inventory_edit`); ruchy
  mają datę wpisu, więc dostawa sprzed spisu się nie dubluje. `panel_inventory_stock` zwraca sprzedaż, dostawy
  i usunięcia osobno, `panel_inventory_counts` w pozycjach poprzednio / sprzedaż / dostawy / usunięte / „powinno
  być”, a w spisie `docs` od poprzedniej zakończonej inwentaryzacji (widać je na końcu spisu i w szczegółach).
  Szczegóły w Historii mają „Zapisz PDF” (`inventory_pdf.dart`, `exportPdfDocument` z kilkoma tabelami: spis,
  dostawy, usunięcia). Uprawnienia sprawdza `private.inventory_allowed` (konto panelu albo własny pracownik
  z uprawnieniem). Table for employees: przycisk „Inwentaryzacja” na karcie lokalu przy `inventory_count`
  (`inventory_screen.dart`, `staff_inventory` jednym zapytaniem; karty pogrupowane po lokalizacji, wyszukiwarka,
  pojemnik jako wybór, różnica na żywo, „Zapisz” po zmianie, „Zakończ inwentaryzację” na dole).
- Receptury (0037): w oknie dania w Menu sekcja „Składniki” (tylko w panelu): składnik z inwentaryzacji, ilość na
  porcję i jednostka (ml/l, g/kg, szt; `private.inventory_factor`), „Nowy składnik” dodaje go do Inwentaryzacji
  (insert z `menu_edit` albo `inventory_edit`). Tabela `menu_item_ingredients` (RLS: tylko obsługa lokalu, goście jej
  nie czytają), zapis `panel_set_menu_item_ingredients`. Trigger `order_items_inventory`: wysłanie pozycji (sent, ready,
  served) zapisuje zużycie w `inventory_movements` (ujemne, `kind = 'sale'`), anulowanie je usuwa. Stan teraz
  (`panel_inventory_stock`) = ostatnia inwentaryzacja składnika + ruchy od chwili, gdy go policzono. Historia pokazuje
  sprzedaż, dostawy, usunięcia, stan „powinno być” i różnicę. Warianty dania mają tę samą recepturę.

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
