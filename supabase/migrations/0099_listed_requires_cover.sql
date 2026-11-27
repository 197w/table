-- Widoczność w aplikacji tylko z bannerem (27.11.2026, prośba użytkownika: „ustaw tak, aby restauracja mogła włączyć
-- swoją widoczność tylko w momencie, kiedy w »Dane lokalu« jest ustawiony banner”).
--
-- Banner to `restaurants.cover_url` (zdjęcie lokalu 1920 × 1080 px na liście lokali i na górze strony lokalu
-- w aplikacji Table). Nie da się włączyć widoczności lokalu bez banneru ani usunąć banneru widocznemu lokalowi.
-- Sprawdzamy tylko zmianę: lokal już widoczny bez banneru (dane testowe sprzed tej zasady) może dalej zmieniać
-- inne dane, a wpisy z plików seed (insert) nie są tu sprawdzane.

create or replace function private.restaurants_listed_cover()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.listed and nullif(btrim(coalesce(new.cover_url, '')), '') is null
     and (not old.listed or nullif(btrim(coalesce(old.cover_url, '')), '') is not null) then
    if old.listed then
      raise exception 'Lokal jest widoczny w aplikacji, więc banner można tylko zmienić. Żeby go usunąć, najpierw ukryj lokal.';
    end if;
    raise exception 'Najpierw dodaj banner w „Dane lokalu”. Bez niego lokal nie może być widoczny w aplikacji.';
  end if;
  return new;
end;
$$;

drop trigger if exists restaurants_listed_cover on public.restaurants;
create trigger restaurants_listed_cover
  before update of listed, cover_url on public.restaurants
  for each row execute function private.restaurants_listed_cover();
