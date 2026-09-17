# Table 0.1 · aplikacja dla gości

Pierwsza wersja aplikacji na telefony: odkrywanie lokali, ranking kuchni, menu, opinie,
rezerwacja stolika z automatycznym doborem i konto gościa logowane numerem telefonu.

Technologia: Flutter 3.47, Supabase, Riverpod, go_router, material_ui.

---

## 1. Zainstaluj narzędzia (Windows)

1. **Flutter 3.47.4.** Pobierz archiwum
   `https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.4-stable.zip`
   i rozpakuj do `C:\Users\andgo\develop`. Ścieżka nie może mieć spacji.
2. **Dodaj Fluttera do PATH.** Zmienne środowiskowe użytkownika, wpis `Path`, dodaj
   `%USERPROFILE%\develop\flutter\bin` i przesuń go na górę. Zamknij i otwórz terminale.
3. **Android Studio**, najnowsza wersja stabilna z `developer.android.com/studio`.
4. **Składniki SDK.** W Android Studio: Tools, SDK Manager.
   - SDK Platforms: **API 36**
   - SDK Tools: Build-Tools, Command-line Tools, Emulator, Platform-Tools, CMake, NDK
5. **Emulator.** Tools, Device Manager, utwórz telefon z włączoną akceleracją grafiki.
6. **Java.** Masz zainstalowaną Javę 26, która może psuć buildy Androida. Wskaż Flutterowi JDK z Android Studio:

   ```bash
   flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"
   ```

7. **Licencje Androida.** Przeczytaj i zaakceptuj:

   ```bash
   flutter doctor --android-licenses
   ```

8. **Sprawdzenie.** Wszystko przy Androidzie ma być na zielono:

   ```bash
   flutter doctor
   ```

Buildy na iPhone'a wymagają Maca albo macOS w chmurze. Na Windows testujesz na Androidzie.

## 2. Czcionka

Wgraj cztery pliki Figtree do `assets/fonts`. Instrukcja jest w `assets/fonts/WGRAJ_TUTAJ.txt`.

## 3. Wygeneruj foldery platform

W folderze projektu:

```bash
flutter create --platforms=android,ios --org pl.table --project-name table .
```

Polecenie dopisuje tylko brakujące pliki i nie nadpisuje kodu w `lib`.
Usuń wygenerowany przykładowy test, bo odwołuje się do nieistniejącej klasy:

```bash
del test\widget_test.dart
```

### Uprawnienia Androida

W `android/app/src/main/AndroidManifest.xml`, przed znacznikiem `<application`, dodaj:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<queries>
  <intent>
    <action android:name="android.intent.action.DIAL" />
    <data android:scheme="tel" />
  </intent>
</queries>
```

### Uprawnienia iOS

W `ios/Runner/Info.plist`, wewnątrz głównego `<dict>`, dodaj:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Table pokazuje najlepsze lokale w twojej okolicy.</string>
```

## 4. Supabase

1. Załóż konto na `supabase.com` i utwórz projekt w regionie **Frankfurt (eu-central-1)**.
2. **SQL Editor.** Wklej i uruchom po kolei każdy plik z `supabase/migrations`:
   `0001`, `0002`, `0003`, `0004`, `0005`, `0006`. Na końcu uruchom `supabase/seed.sql`.
3. **Authentication, Sign In / Providers, Phone.** Włącz logowanie telefonem i zostaw włączone potwierdzanie numeru.
4. **Authentication, Hooks, Send SMS.** Wybierz typ Postgres i funkcję `public.dev_send_sms_hook`.
   Od tej chwili kody SMS nie są wysyłane, tylko zapisywane w tabeli `private.dev_sms_outbox`.
5. **Project Settings, API Keys.** Skopiuj adres projektu i klucz publikowalny.
6. Skopiuj `env.example.json` do `env.json` i wpisz oba wartości. Plik `env.json` jest w `.gitignore`.

Jeśli panel nie pozwoli włączyć logowania telefonem bez podania dostawcy SMS, zapisz komunikat.
To jedyny krok konfiguracji, którego nie dało się sprawdzić bez konta.

## 5. Uruchomienie

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run --dart-define-from-file=env.json
```

### Scenariusz testowy

1. Na ekranie Odkrywaj zezwól na lokalizację albo wybierz Białystok z listy miast.
2. Otwórz **Pierogarnia Na Mostku** w Białymstoku i wybierz „Zarezerwuj stolik”.
3. Załóż konto dowolnym numerem, na przykład `600 000 001`, i hasłem z co najmniej 8 znakami.
4. Kod SMS odczytaj w Supabase: Table Editor, schemat `private`, tabela `dev_sms_outbox`.
5. Wybierz dzień, liczbę osób, godzinę i okazję, potem potwierdź rezerwację.
6. W zakładce Rezerwacje sprawdź rezerwację i ją odwołaj.
7. W Supabase w tabeli `table_holds` zobaczysz przydzielony stolik i jego dezaktywację po odwołaniu.

---

## Co jest w wersji 0.1

- Przeglądanie lokali bez logowania, ranking kuchni ze średnią ważoną i opis zasad rankingu
- Filtr kuchni i sortowanie po odległości
- Karta lokalu z ocenami w trzech osiach, godzinami, menu z alergenami i opiniami
- Przycisk „Zadzwoń” dla lokali w planie darmowym
- Rezerwacja dla lokali Pro: dzień, liczba osób, wolne godziny, okazja, wiadomość, alergie ze zgodą
- Automatyczny dobór stolika i blokada podwójnej rezerwacji w bazie
- Rejestracja numerem telefonu z hasłem i kodem SMS, logowanie kodem albo hasłem
- Lista rezerwacji z odwołaniem, opinia zweryfikowana po wizycie, opinia niezweryfikowana bez rezerwacji
- Profil z imieniem, wylogowanie i usuwanie konta

## Czego jeszcze nie ma

- **Weryfikacja paragonem.** Wymaga przechowywania zdjęć i moderacji.
- **E-mail do odzyskiwania konta, zmiana numeru i obsługa przejętego numeru.** Wymagają funkcji serwerowych.
- **Dodatkowy krok logowania** po długiej nieaktywności i na nowym urządzeniu.
- **Prawdziwa bramka SMS.** Kody trafiają do tabeli testowej.
- **Panel restauracji.** Rezerwacja liczy się jako zakończona po upływie jej czasu, bo nikt jeszcze nie oznacza wizyt.
- **Zdjęcia lokali, powiadomienia push, ikony aplikacji, jasny motyw.**

## Przed wydaniem

- Wyłącz hook `dev_send_sms_hook` i usuń tabelę `private.dev_sms_outbox`.
- Podłącz bramkę SMS, na przykład SMSAPI, i ustaw limity wysyłki.
- Usuń dane przykładowe: `delete from restaurants where is_example;`
- Zamień robocze logo na docelowe ikony i sprawdź nazwę pakietu `pl.table.app`.
