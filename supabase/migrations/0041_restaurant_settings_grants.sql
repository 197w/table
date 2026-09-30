-- Table · migracja 0041
-- Kierownik i właściciel zmieniają w „Dane lokalu” okres grafiku (0034) i ustawienia dostawy (0039).
-- Tabela restaurants ma zgody na zmianę tylko wybranych kolumn (0012), a tych kolumn brakowało,
-- więc zapis kończył się błędem uprawnień. Kto może zmieniać lokal, nadal pilnuje polityka
-- „Kierownik zmienia profil lokalu”. Zamówienia z dostawą i tak przyjmuje tylko plan Pro (guest_place_order).

grant update (schedule_period, delivery_enabled, pickup_enabled, takeaway_cash,
              delivery_fee_grosze, delivery_min_grosze, delivery_area)
  on public.restaurants to authenticated;
