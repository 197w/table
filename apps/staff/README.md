# Table for employees

Aplikacja dla pracowników lokalu (Android i iOS).

- Logowanie numerem telefonu i kodem SMS. Numer musi być ten sam, który kierownik wpisał w panelu
  (zakładka „Pracownicy”).
- „Zeskanuj kod”: wspólny kod QR z panelu w trybie obsługi zaczyna zmianę. Po skanie można
  jeszcze otworzyć panel na komputerze na uprawnienia swojego stanowiska.
- „Zamówienia” (stanowisko z uprawnieniem „Zamówienia”, w trakcie zmiany): stoliki, rachunek, menu,
  wysyłka na kuchnię, dania do wydania i zamknięcie rachunku.
- „Moje godziny”: zmiany z ostatnich 31 dni.

Uruchamianie: `flutter run -d <telefon> --dart-define-from-file=../../env.json`.
