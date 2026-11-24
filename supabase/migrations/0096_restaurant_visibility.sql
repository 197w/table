-- Widoczność lokalu w aplikacji dla klientów (24.11.2026, prośba użytkownika: „w ustawieniach lokalu dodaj możliwość
-- wyłączenia i włączenia widoczności restauracji w aplikacji dla klientów”).
--
-- `restaurants.listed` decyduje, czy lokal widzą goście (wyszukiwarka, strona lokalu, rezerwacje, zamówienia).
-- Nowy lokal ma `listed = false` do weryfikacji przez Table, więc właściciel nie może go sam włączyć. Dlatego
-- `first_listed_at` zapamiętuje, kiedy lokal został włączony po raz pierwszy (weryfikacja, jak dotąd ręcznie przez
-- Table; dotychczasowe widoczne lokale dostają datę teraz). Włączać i wyłączać widoczność może kierownik albo
-- właściciel tylko lokalu, który kiedyś już był zweryfikowany. Wyłączony lokal znika dla gości; złożone rezerwacje
-- i zamówienia zostają.

alter table public.restaurants add column if not exists first_listed_at timestamptz;
update public.restaurants set first_listed_at = now() where listed and first_listed_at is null;

create or replace function private.restaurants_first_listed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.listed and new.first_listed_at is null then
    new.first_listed_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists restaurants_first_listed on public.restaurants;
create trigger restaurants_first_listed
  before insert or update of listed on public.restaurants
  for each row execute function private.restaurants_first_listed();

create or replace function public.panel_set_listed(p_restaurant_id uuid, p_listed boolean)
returns void
language plpgsql
security definer
set search_path = 'public'
as $$
begin
  perform private.require_staff(p_restaurant_id, 'manager');
  if p_listed is null then
    raise exception 'Wybierz, czy lokal ma być widoczny.';
  end if;
  if not exists (select 1 from restaurants where id = p_restaurant_id and first_listed_at is not null) then
    raise exception 'Lokal pojawi się w aplikacji dla klientów po weryfikacji przez Table.';
  end if;
  update restaurants set listed = p_listed where id = p_restaurant_id;
end;
$$;

revoke execute on function public.panel_set_listed(uuid, boolean) from public, anon;
grant execute on function public.panel_set_listed(uuid, boolean) to authenticated;
