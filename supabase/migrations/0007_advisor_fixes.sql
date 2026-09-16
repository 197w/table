-- Rarytka · migracja 0007
-- Poprawki po doradcy bezpieczeństwa i wydajności Supabase.

-- Stała ścieżka wyszukiwania w funkcjach pomocniczych.
alter function private.visit_minutes(integer) set search_path = '';
alter function private.cleanup_minutes(integer) set search_path = '';

-- Funkcja wyzwalacza nie może być dostępna przez API.
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Szybsze usuwanie konta, które zeruje user_id w zdarzeniach.
create index if not exists restaurant_events_user_idx on public.restaurant_events (user_id);

-- Świadomie pozostawione uwagi doradcy:
-- * Tabele dining_tables, table_holds, reviews i restaurant_events nie mają zasad RLS,
--   więc aplikacja nie ma do nich bezpośredniego dostępu. Dostęp jest tylko przez funkcje.
-- * Funkcje SECURITY DEFINER w schemacie public są celowo wystawione jako API aplikacji
--   i każda sprawdza uprawnienia gościa w środku.
