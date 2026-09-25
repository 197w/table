# Table Praca

Aplikacja dla pracowników lokalu (Android i iOS).

- Logowanie numerem telefonu i kodem SMS. Numer musi być ten sam, który kierownik wpisał w panelu
  (zakładka „Pracownicy”).
- „Zeskanuj kod z panelu”: skan kodu QR z panelu w trybie obsługi zaczyna zmianę i otwiera panel
  na uprawnienia stanowiska pracownika.
- „Moje godziny”: zmiany z ostatnich 31 dni.

Uruchamianie: `flutter run -d <telefon> --dart-define-from-file=../../env.json`.
