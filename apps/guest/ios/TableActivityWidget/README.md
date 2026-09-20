# Kafel rezerwacji na ekranie blokady (Live Activity)

Te pliki czekają na rozszerzenie z widżetem. **Dopóki go nie ma, projekt buduje się normalnie**:
most do ActivityKit siedzi w `Runner/AppDelegate.swift`, a aplikacja po prostu nie pokazuje kafla.

Rozszerzenia nie da się podpisać na darmowym koncie Apple. Potrzebny jest płatny
Apple Developer Program.

## Gdy będzie płatne konto (robi się w Xcode na Macu)

1. File → New → Target → **Widget Extension**, nazwa `TableActivityWidget`,
   zaznaczone „Include Live Activity”, identyfikator `pl.table.app.TableActivityWidget`,
   ten sam zespół co `Runner`.
2. Usuń pliki, które Xcode wygenerował sam, i dodaj do celu rozszerzenia te z tego katalogu:
   `TableActivityWidget.swift`, `TableReservationAttributes.swift` oraz `Info.plist`.
3. `Runner/Info.plist` ma już `NSSupportsLiveActivities`.
4. Zbuduj i zainstaluj aplikację na telefonie. Kafel pojawia się, gdy do rezerwacji
   zostało mniej niż 1,5 godziny, a aplikacja była w tym czasie otwarta.

## Uwaga o typie danych

`TableReservationAttributes` istnieje w dwóch kopiach: tutaj i w `Runner/AppDelegate.swift`.
To dwa osobne moduły, więc tak jest poprawnie, ale **zmiana w jednym miejscu wymaga
takiej samej zmiany w drugim**, inaczej kafel nie odbierze danych z aplikacji.
