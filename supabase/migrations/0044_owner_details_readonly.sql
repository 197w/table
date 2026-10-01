-- Table · migracja 0044
-- Dane właściciela w panelu są tylko do odczytu. Zmieniać je będzie można tylko w Table Dev
-- (narzędzie zespołu Table), więc konta panelu tracą prawo do panel_set_owner_details.
-- Funkcja zostaje dla roli serwisowej. Nowy lokal nadal zapisuje NIP z rejestracji (panel_create_restaurant).

revoke execute on function public.panel_set_owner_details(uuid, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.panel_set_owner_details(uuid, text, text, text, text, text, text) to service_role;
